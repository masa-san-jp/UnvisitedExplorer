import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var recorder: LocationRecorder
    @EnvironmentObject private var store: LocationStore
    @Query(sort: \LocationSample.timestamp, order: .reverse) private var samples: [LocationSample]
    @Query(sort: \VisitedCell.lastVisitedAt, order: .reverse) private var cells: [VisitedCell]

    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirmation = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("位置記録") {
                PermissionCard()
                if let error = recorder.lastError {
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
                Text("位置履歴は初期状態でこのiPhone内のSwiftDataにのみ保存します。クラウド同期や外部送信は実装していません。")
                Text("Apple Watchの手動探索モードで取得した位置だけ、WatchConnectivity経由でペアリング済みiPhoneへ転送します。")
            }

            if let statusMessage {
                Section { Text(statusMessage) }
            }
        }
        .navigationTitle("設定")
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
