import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var engine: LocationEngine
    @EnvironmentObject private var store: LocationStore
    @Query(sort: \LocationSample.timestamp, order: .reverse) private var samples: [LocationSample]
    @Query(sort: \VisitedCell.lastVisitedAt, order: .reverse) private var cells: [VisitedCell]

    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirmation = false
    @State private var statusMessage: String?
    @State private var showImporter = false
    @State private var isImporting = false

    var body: some View {
        Form {
            Section("位置記録") {
                PermissionCard()
                if engine.launchedForLocationEvent {
                    Label(
                        "直近の起動は位置イベントによるバックグラウンド起動でした",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let error = engine.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section("探索リマインダー") {
                Toggle("毎日10時に通知", isOn: $dailyReminderEnabled)
                    .onChange(of: dailyReminderEnabled) { _, enabled in
                        Task { await updateReminder(enabled: enabled) }
                    }
            }

            Section("データ") {
                Button("過去データを取り込む") { showImporter = true }
                    .disabled(isImporting)
                if isImporting {
                    HStack {
                        ProgressView()
                        Text("取り込み中…").foregroundStyle(.secondary)
                    }
                }

                Button("GeoJSONを書き出す") { exportGeoJSON() }
                Button("CSVを書き出す") { exportCSV() }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("作成したファイルを共有", systemImage: "square.and.arrow.up")
                    }
                }

                Button("全データを削除", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }

            Section("プライバシー") {
                Text("取り込み・書き出しはどちらも端末内で完結します。ファイルの中身を外部へ送信することはありません。")
                Text("位置履歴は初期状態でこのiPhone内のSwiftDataにのみ保存します。クラウド同期や外部送信は実装していません。")
                Text("Apple Watchの手動探索モードで取得した位置だけ、WatchConnectivity経由でペアリング済みiPhoneへ転送します。")
            }

            if let statusMessage {
                Section { Text(statusMessage) }
            }
        }
        .navigationTitle("設定")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .xml, .commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await runImport(result) }
        }
        .confirmationDialog(
            "位置履歴をすべて削除しますか？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                store.deleteAll(samples: samples, cells: cells)
            }
        }
    }

    private func updateReminder(enabled: Bool) async {
        do {
            if enabled {
                try await NotificationService.requestAndScheduleDailyReminder()
            } else {
                NotificationService.cancelDailyReminder()
            }
        } catch {
            statusMessage = error.localizedDescription
            dailyReminderEnabled = false
        }
    }

    private func runImport(_ result: Result<[URL], Error>) async {
        let urls: [URL]
        switch result {
        case .success(let picked):
            urls = picked
        case .failure(let error):
            statusMessage = error.localizedDescription
            return
        }

        isImporting = true
        defer { isImporting = false }

        var total = ImportSummary()
        for url in urls {
            // ファイルAppやiCloud上のファイルはセキュリティスコープ付きで渡される。
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let name = url.lastPathComponent
                // 解析は重いのでメインスレッドから外す。
                let payloads = try await Task.detached(priority: .userInitiated) {
                    try LocationImporter.parse(data: try Data(contentsOf: url), fileName: name)
                }.value

                let summary = store.ingestHistorical(payloads)
                total.accepted += summary.accepted
                total.rejected += summary.rejected
                total.duplicated += summary.duplicated
                total.newCells += summary.newCells
                if let failure = summary.failure { total.failure = failure }
            } catch {
                statusMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }

        if let failure = total.failure {
            statusMessage = "取り込み中に保存へ失敗しました: \(failure)"
        } else {
            statusMessage = """
            取り込み完了: \(total.accepted)件を追加、\(total.newCells)セルが新規。
            重複 \(total.duplicated)件 / フィルタで棄却 \(total.rejected)件。
            """
        }
    }

    private func exportGeoJSON() {
        do {
            exportURL = try ExportService.writeGeoJSON(samples: Array(samples.reversed()))
            statusMessage = "GeoJSONを作成しました。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func exportCSV() {
        do {
            exportURL = try ExportService.writeCSV(samples: Array(samples.reversed()))
            statusMessage = "CSVを作成しました。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
