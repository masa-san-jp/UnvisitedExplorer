import CoreLocation
import Foundation

struct ExplorationSuggestion: Identifiable, Hashable {
    let cell: GridCell
    let distanceMeters: Double

    var id: String { cell.key }
    var title: String {
        distanceMeters < 1_000
            ? "未訪問エリア・約\(Int(distanceMeters))m"
            : String(format: "未訪問エリア・約%.1fkm", distanceMeters / 1_000)
    }
}

enum ExplorationSuggestionEngine {
    static func suggestions(
        from origin: CLLocationCoordinate2D,
        visitedKeys: Set<String>,
        count: Int = 3
    ) -> [ExplorationSuggestion] {
        let originCell = GeoGrid.cell(for: origin)
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        var candidates: [ExplorationSuggestion] = []

        for radius in 1...10 {
            for dx in -radius...radius {
                for dy in -radius...radius where abs(dx) == radius || abs(dy) == radius {
                    let cell = GridCell(
                        x: originCell.x + dx,
                        y: originCell.y + dy,
                        sizeMeters: originCell.sizeMeters
                    )
                    guard !visitedKeys.contains(cell.key) else { continue }
                    let center = cell.center
                    let distance = originLocation.distance(
                        from: CLLocation(latitude: center.latitude, longitude: center.longitude)
                    )
                    candidates.append(ExplorationSuggestion(cell: cell, distanceMeters: distance))
                }
            }
            if candidates.count >= count * 5 { break }
        }

        return candidates
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(count)
            .map { $0 }
    }
}
