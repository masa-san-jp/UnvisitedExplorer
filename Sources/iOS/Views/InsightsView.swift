import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(sort: \VisitedCell.lastVisitedAt, order: .reverse) private var cells: [VisitedCell]
    @Query(sort: \LocationSample.timestamp, order: .reverse) private var samples: [LocationSample]
    @Query private var stats: [RecordingStat]

    var body: some View {
        List {
            Section("探索状況") {
                metric("訪問済みセル", value: "\(cells.count)")
                metric("位置サンプル", value: "\(samples.count)")
                metric("推定訪問面積", value: visitedArea)
                metric("直近7日の新規セル", value: "\(newCellsLastSevenDays)")
            }

            Section {
                if let latest = samples.first {
                    metric("最後の記録", value: latest.timestamp.formatted(.relative(presentation: .named)))
                } else {
                    Text("まだ1件も記録されていません。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("動作確認")
            } footer: {
                Text("アプリを閉じたまま数km移動したあと、ここが増えていれば常時記録が効いています。")
            }

            Section {
                if activeStats.isEmpty {
                    Text("まだどの経路からも配信がありません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeStats, id: \.layerRawValue) { stat in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(stat.layer.label)
                                Spacer()
                                Text("採用 \(stat.accepted) / 棄却 \(stat.rejected)")
                                    .foregroundStyle(.secondary)
                            }
                            if let fired = stat.lastFiredAt {
                                Text("最終: \(fired.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("記録経路の内訳")
            } footer: {
                Text("どの層が動いていないかを切り分けるための内訳です。棄却が多い層は精度不足の可能性があります。")
            }

            Section("記録元") {
                metric("iPhone", value: "\(samples.filter { $0.source == .iPhone }.count)")
                metric("Apple Watch", value: "\(samples.filter { $0.source == .appleWatch }.count)")
            }
        }
        .navigationTitle("記録")
    }

    /// 一度でも配信があった層だけを、仕様 §3.1 の順で出す。
    private var activeStats: [RecordingStat] {
        RecordingLayer.displayOrder.compactMap { layer in
            stats.first { $0.layerRawValue == layer.rawValue }
        }
    }

    private var visitedArea: String {
        let area = Double(cells.count) * pow(GeoGrid.defaultCellSizeMeters, 2) / 1_000_000
        return String(format: "%.2f km²", area)
    }

    private var newCellsLastSevenDays: Int {
        let threshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return cells.filter { $0.firstVisitedAt >= threshold }.count
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
