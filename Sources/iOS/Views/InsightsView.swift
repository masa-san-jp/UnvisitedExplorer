import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(sort: \VisitedCell.lastVisitedAt, order: .reverse) private var cells: [VisitedCell]
    @Query(sort: \LocationSample.timestamp, order: .reverse) private var samples: [LocationSample]

    var body: some View {
        List {
            Section("探索状況") {
                metric("訪問済みセル", value: "\(cells.count)")
                metric("位置サンプル", value: "\(samples.count)")
                metric("推定訪問面積", value: visitedArea)
                metric("直近7日の新規セル", value: "\(newCellsLastSevenDays)")
            }

            Section("記録元") {
                metric("iPhone", value: "\(samples.filter { $0.source == .iPhone }.count)")
                metric("Apple Watch", value: "\(samples.filter { $0.source == .appleWatch }.count)")
            }
        }
        .navigationTitle("記録")
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
