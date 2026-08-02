import CoreLocation
import SwiftData
import XCTest
@testable import UnvisitedExplorer

@MainActor
final class LocationStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: LocationSample.self,
            VisitedCell.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func payload(
        latitude: Double = 36.062,
        longitude: Double = 139.667,
        accuracy: Double = 10,
        offsetSeconds: TimeInterval = 0
    ) -> LocationPayload {
        LocationPayload(
            timestamp: now.addingTimeInterval(offsetSeconds),
            latitude: latitude,
            longitude: longitude,
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            speed: -1,
            course: -1,
            source: .iPhone
        )
    }

    private func counts(_ container: ModelContainer) throws -> (samples: Int, cells: Int) {
        let context = container.mainContext
        return (
            try context.fetch(FetchDescriptor<LocationSample>()).count,
            try context.fetch(FetchDescriptor<VisitedCell>()).count
        )
    }

    func testAcceptedPayloadCreatesSampleAndCell() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        XCTAssertEqual(store.ingest(payload(), now: now), .accepted)

        let result = try counts(container)
        XCTAssertEqual(result.samples, 1)
        XCTAssertEqual(result.cells, 1)
    }

    func testLowAccuracyPayloadIsNotPersisted() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        XCTAssertEqual(store.ingest(payload(accuracy: 500), now: now), .rejected(.rejectAccuracy))

        let result = try counts(container)
        XCTAssertEqual(result.samples, 0)
        XCTAssertEqual(result.cells, 0)
    }

    func testRepeatedNearbyPayloadIsDeduplicated() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        XCTAssertEqual(store.ingest(payload(), now: now), .accepted)
        XCTAssertEqual(
            store.ingest(payload(offsetSeconds: 30), now: now),
            .rejected(.rejectDuplicate)
        )

        XCTAssertEqual(try counts(container).samples, 1)
    }

    func testDistantPayloadCreatesASecondCell() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        XCTAssertEqual(store.ingest(payload(), now: now), .accepted)
        XCTAssertEqual(
            store.ingest(payload(latitude: 36.1, offsetSeconds: 120), now: now),
            .accepted
        )

        let result = try counts(container)
        XCTAssertEqual(result.samples, 2)
        XCTAssertEqual(result.cells, 2)
    }

    func testRevisitingTheSameCellIncrementsVisitCount() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        // セル境界に依存しないよう、セル中心を基準に取る。
        // 250m の Mercator セルは緯度36度で実測約202m四方なので、
        // 中心から東へ約70m 動いても同じセルに留まる。
        let center = GeoGrid
            .cell(for: CLLocationCoordinate2D(latitude: 36.062, longitude: 139.667))
            .center
        let eastwardOffset = 70.0 / (111_320 * cos(center.latitude * .pi / 180))

        XCTAssertEqual(
            store.ingest(
                payload(latitude: center.latitude, longitude: center.longitude),
                now: now
            ),
            .accepted
        )
        XCTAssertEqual(
            store.ingest(
                payload(
                    latitude: center.latitude,
                    longitude: center.longitude + eastwardOffset,
                    offsetSeconds: 120
                ),
                now: now
            ),
            .accepted
        )

        let cells = try container.mainContext.fetch(FetchDescriptor<VisitedCell>())
        XCTAssertEqual(cells.count, 1, "同一セル内の移動で2セット目のセルが作られている")
        XCTAssertEqual(cells.first?.visitCount, 2)
    }

    /// バックグラウンド起動は毎回新しいプロセスになる。重複排除の基準点を
    /// メモリ上にしか持たないと、起動のたびに同じ地点が二重記録される。
    func testDeduplicationStateIsSeededFromTheDatabase() throws {
        let container = try makeContainer()
        let first = LocationStore(container: container)
        XCTAssertEqual(first.ingest(payload(), now: now), .accepted)

        // プロセスが落ちて再起動した状況を模す。
        let restarted = LocationStore(container: container)
        XCTAssertEqual(
            restarted.ingest(payload(offsetSeconds: 30), now: now),
            .rejected(.rejectDuplicate)
        )

        XCTAssertEqual(try counts(container).samples, 1)
    }

    func testDeleteAllClearsBothModels() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)
        XCTAssertEqual(store.ingest(payload(), now: now), .accepted)

        let context = container.mainContext
        XCTAssertTrue(
            store.deleteAll(
                samples: try context.fetch(FetchDescriptor<LocationSample>()),
                cells: try context.fetch(FetchDescriptor<VisitedCell>())
            )
        )

        let result = try counts(container)
        XCTAssertEqual(result.samples, 0)
        XCTAssertEqual(result.cells, 0)
    }
}
