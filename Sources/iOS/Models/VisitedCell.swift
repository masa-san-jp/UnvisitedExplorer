import CoreLocation
import Foundation
import SwiftData

@Model
final class VisitedCell {
    @Attribute(.unique) var key: String
    var gridX: Int
    var gridY: Int
    var cellSizeMeters: Double
    var firstVisitedAt: Date
    var lastVisitedAt: Date
    var visitCount: Int

    init(cell: GridCell, timestamp: Date) {
        key = cell.key
        gridX = cell.x
        gridY = cell.y
        cellSizeMeters = cell.sizeMeters
        firstVisitedAt = timestamp
        lastVisitedAt = timestamp
        visitCount = 1
    }

    var gridCell: GridCell {
        GridCell(x: gridX, y: gridY, sizeMeters: cellSizeMeters)
    }

    var center: CLLocationCoordinate2D { gridCell.center }
    var polygonCoordinates: [CLLocationCoordinate2D] { gridCell.polygonCoordinates }
}
