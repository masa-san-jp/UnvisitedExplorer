import CoreLocation
import XCTest
@testable import UnvisitedExplorer

/// 座標変換は間違っていても地図上では一見それらしく見えるため、
/// スケール誤差はテストでしか捕まえられない(仕様 §10.1)。
final class GeoGridTests: XCTestCase {
    func testRoundTripThroughCellCenterIsStable() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 36.062, longitude: 139.667),   // 久喜
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: -33.868, longitude: 151.209),  // 南半球
            CLLocationCoordinate2D(latitude: 64.146, longitude: -21.942)    // 高緯度・西経
        ]

        for size in [250.0, 500.0, 1_000.0] {
            for coordinate in coordinates {
                let cell = GeoGrid.cell(for: coordinate, sizeMeters: size)
                let again = GeoGrid.cell(for: cell.center, sizeMeters: size)
                XCTAssertEqual(cell, again, "size=\(size) coordinate=\(coordinate)")
            }
        }
    }

    func testCellsStraddlingThePrimeMeridianDiffer() {
        let west = GeoGrid.cell(for: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.01))
        let east = GeoGrid.cell(for: CLLocationCoordinate2D(latitude: 51.5, longitude: 0.01))

        XCTAssertNotEqual(west, east)
        XCTAssertLessThan(west.x, 0, "西経は負のセル座標になる")
        XCTAssertGreaterThanOrEqual(east.x, 0)
    }

    func testNegativeLatitudeProducesNegativeGridY() {
        let southern = GeoGrid.cell(for: CLLocationCoordinate2D(latitude: -33.868, longitude: 151.209))
        XCTAssertLessThan(southern.y, 0)
    }

    func testCellSizeIsPartOfTheKey() {
        let coordinate = CLLocationCoordinate2D(latitude: 36.062, longitude: 139.667)
        let fine = GeoGrid.cell(for: coordinate, sizeMeters: 250)
        let coarse = GeoGrid.cell(for: coordinate, sizeMeters: 1_000)

        XCTAssertNotEqual(fine.key, coarse.key)
        XCTAssertTrue(fine.key.hasSuffix(":250"))
        XCTAssertTrue(coarse.key.hasSuffix(":1000"))
    }

    func testAdjacentCellsAreOneApartAndAboutOneCellWide() {
        let origin = GeoGrid.cell(for: CLLocationCoordinate2D(latitude: 36.062, longitude: 139.667))
        let neighbour = GridCell(x: origin.x + 1, y: origin.y, sizeMeters: origin.sizeMeters)

        let metres = CLLocation(latitude: origin.center.latitude, longitude: origin.center.longitude)
            .distance(
                from: CLLocation(
                    latitude: neighbour.center.latitude,
                    longitude: neighbour.center.longitude
                )
            )

        // Mercator 平面上で 250m なので、緯度36度の実距離は 250 * cos(36°) ≒ 202m。
        // 仕様 §3 のスケール歪みの前提が崩れていないことを固定する。
        XCTAssertEqual(metres, 250 * cos(36.062 * .pi / 180), accuracy: 5)
    }
}
