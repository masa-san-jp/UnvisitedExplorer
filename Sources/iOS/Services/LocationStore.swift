import CoreLocation
import Foundation
import SwiftData

/// 全入力の唯一の入口(仕様 §3.5)。
/// L0〜L4 / Watch / インポートは必ずここを通す。フィルタを他所に分散させない。
@MainActor
final class LocationStore: ObservableObject {
    let container: ModelContainer
    private let context: ModelContext

    /// 重複排除の基準点。バックグラウンド起動は毎回新しいプロセスなので、
    /// メモリ上の状態だけに頼ると起動のたびに重複排除がリセットされる。
    private var lastAccepted: AcceptedPoint?

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
        context.autosaveEnabled = true
        lastAccepted = Self.loadLastAccepted(from: context)
    }

    @discardableResult
    func ingest(
        _ payload: LocationPayload,
        policy: IngestPolicy = .live,
        now: Date = Date()
    ) -> RecordingFilter.Decision {
        let decision = RecordingFilter.decide(
            payload,
            lastAccepted: lastAccepted,
            now: now,
            policy: policy
        )
        guard decision == .accept else { return decision }

        let payloadID = payload.id
        var duplicateDescriptor = FetchDescriptor<LocationSample>(
            predicate: #Predicate { $0.id == payloadID }
        )
        duplicateDescriptor.fetchLimit = 1
        if (try? context.fetch(duplicateDescriptor).first) != nil { return .rejectDuplicate }

        let cell = GeoGrid.cell(
            for: CLLocationCoordinate2D(
                latitude: payload.latitude,
                longitude: payload.longitude
            )
        )
        context.insert(LocationSample(payload: payload, gridKey: cell.key))

        let cellKey = cell.key
        var cellDescriptor = FetchDescriptor<VisitedCell>(
            predicate: #Predicate { $0.key == cellKey }
        )
        cellDescriptor.fetchLimit = 1

        if let existing = try? context.fetch(cellDescriptor).first {
            existing.lastVisitedAt = max(existing.lastVisitedAt, payload.timestamp)
            existing.firstVisitedAt = min(existing.firstVisitedAt, payload.timestamp)
            existing.visitCount += 1
        } else {
            context.insert(VisitedCell(cell: cell, timestamp: payload.timestamp))
        }

        try? context.save()

        lastAccepted = AcceptedPoint(
            timestamp: payload.timestamp,
            latitude: payload.latitude,
            longitude: payload.longitude
        )
        return .accept
    }

    func deleteAll(samples: [LocationSample], cells: [VisitedCell]) {
        samples.forEach(context.delete)
        cells.forEach(context.delete)
        try? context.save()
        lastAccepted = nil
    }

    private static func loadLastAccepted(from context: ModelContext) -> AcceptedPoint? {
        var descriptor = FetchDescriptor<LocationSample>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else { return nil }
        return AcceptedPoint(
            timestamp: latest.timestamp,
            latitude: latest.latitude,
            longitude: latest.longitude
        )
    }
}
