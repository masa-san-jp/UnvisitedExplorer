import CoreLocation
import Foundation
import SwiftData

@MainActor
final class LocationStore: ObservableObject {
    let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
        context.autosaveEnabled = true
    }

    func ingest(_ payload: LocationPayload) {
        guard payload.horizontalAccuracy >= 0, payload.horizontalAccuracy <= 500 else { return }
        guard abs(payload.latitude) <= 90, abs(payload.longitude) <= 180 else { return }

        let payloadID = payload.id
        var duplicateDescriptor = FetchDescriptor<LocationSample>(
            predicate: #Predicate { $0.id == payloadID }
        )
        duplicateDescriptor.fetchLimit = 1
        if (try? context.fetch(duplicateDescriptor).first) != nil { return }

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
    }

    func deleteAll(samples: [LocationSample], cells: [VisitedCell]) {
        samples.forEach(context.delete)
        cells.forEach(context.delete)
        try? context.save()
    }
}
