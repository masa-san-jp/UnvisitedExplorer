import CoreLocation
import Foundation

public struct GridCell: Identifiable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let sizeMeters: Double

    public var id: String { key }
    public var key: String { "\(x):\(y):\(Int(sizeMeters))" }

    public init(x: Int, y: Int, sizeMeters: Double) {
        self.x = x
        self.y = y
        self.sizeMeters = sizeMeters
    }

    public var center: CLLocationCoordinate2D {
        GeoGrid.coordinate(gridX: x, gridY: y, sizeMeters: sizeMeters)
    }

    public var polygonCoordinates: [CLLocationCoordinate2D] {
        let minX = Double(x) * sizeMeters
        let minY = Double(y) * sizeMeters
        let maxX = minX + sizeMeters
        let maxY = minY + sizeMeters
        return [
            GeoGrid.coordinate(mercatorX: minX, mercatorY: minY),
            GeoGrid.coordinate(mercatorX: maxX, mercatorY: minY),
            GeoGrid.coordinate(mercatorX: maxX, mercatorY: maxY),
            GeoGrid.coordinate(mercatorX: minX, mercatorY: maxY)
        ]
    }
}

public enum GeoGrid {
    public static let defaultCellSizeMeters = 250.0
    private static let earthRadius = 6_378_137.0
    private static let maxLatitude = 85.051_128_78

    public static func cell(
        for coordinate: CLLocationCoordinate2D,
        sizeMeters: Double = defaultCellSizeMeters
    ) -> GridCell {
        let projected = mercator(coordinate)
        return GridCell(
            x: Int(floor(projected.x / sizeMeters)),
            y: Int(floor(projected.y / sizeMeters)),
            sizeMeters: sizeMeters
        )
    }

    public static func coordinate(gridX: Int, gridY: Int, sizeMeters: Double) -> CLLocationCoordinate2D {
        coordinate(
            mercatorX: (Double(gridX) + 0.5) * sizeMeters,
            mercatorY: (Double(gridY) + 0.5) * sizeMeters
        )
    }

    public static func coordinate(mercatorX x: Double, mercatorY y: Double) -> CLLocationCoordinate2D {
        let longitude = x / earthRadius * 180.0 / .pi
        let latitude = (2.0 * atan(exp(y / earthRadius)) - .pi / 2.0) * 180.0 / .pi
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func mercator(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let latitude = min(max(coordinate.latitude, -maxLatitude), maxLatitude)
        let x = earthRadius * coordinate.longitude * .pi / 180.0
        let y = earthRadius * log(tan(.pi / 4.0 + latitude * .pi / 360.0))
        return (x, y)
    }
}
