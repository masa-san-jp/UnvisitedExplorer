import SwiftData
import XCTest
@testable import UnvisitedExplorer

/// レイヤー別の集計 (仕様 §10.3)。実機で「どの層が動いていないか」を
/// 切り分ける唯一の手段なので、採用・棄却の両方が残ることを固定する。
@MainActor
final class RecordingStatTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: LocationSample.self, VisitedCell.self, RecordingStat.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func payload(
        latitude: Double = 36.062,
        accuracy: Double = 10,
        offsetSeconds: TimeInterval = 0
    ) -> LocationPayload {
        LocationPayload(
            timestamp: now.addingTimeInterval(offsetSeconds),
            latitude: latitude,
            longitude: 139.667,
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            speed: -1,
            course: -1,
            source: .iPhone
        )
    }

    private func stats(_ container: ModelContainer) throws -> [RecordingLayer: RecordingStat] {
        let rows = try container.mainContext.fetch(FetchDescriptor<RecordingStat>())
        return Dictionary(rows.map { ($0.layer, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func testAcceptedDeliveryIsCountedAgainstItsLayer() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        XCTAssertEqual(store.ingest(payload(), layer: .geofence, now: now), .accepted)

        let stat = try XCTUnwrap(try stats(container)[.geofence])
        XCTAssertEqual(stat.accepted, 1)
        XCTAssertEqual(stat.rejected, 0)
        XCTAssertEqual(stat.lastAcceptedAt, now)
    }

    /// 棄却は保存されないため、集計に残らないと「配信が来ていない」と区別できない。
    func testRejectedDeliveryIsStillRecorded() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        XCTAssertEqual(
            store.ingest(payload(accuracy: 500), layer: .significantChange, now: now),
            .rejected(.rejectAccuracy)
        )

        let stat = try XCTUnwrap(try stats(container)[.significantChange])
        XCTAssertEqual(stat.accepted, 0)
        XCTAssertEqual(stat.rejected, 1)
        XCTAssertEqual(stat.lastFiredAt, now, "配信自体はあったことが残ること")
        XCTAssertNil(stat.lastAcceptedAt)
    }

    func testLayersAreCountedSeparately() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        store.ingest(payload(), layer: .significantChange, now: now)
        store.ingest(payload(latitude: 36.2, offsetSeconds: 120), layer: .visit, now: now)
        store.ingest(payload(latitude: 36.4, offsetSeconds: 240), layer: .heartbeat, now: now)

        let all = try stats(container)
        XCTAssertEqual(all[.significantChange]?.accepted, 1)
        XCTAssertEqual(all[.visit]?.accepted, 1)
        XCTAssertEqual(all[.heartbeat]?.accepted, 1)
    }

    func testImportIsAggregatedInOneRow() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        let batch = (0..<5).map { index in
            LocationImporter.make(
                timestamp: now.addingTimeInterval(Double(index) * 600),
                latitude: 36.0 + Double(index) * 0.01,
                longitude: 139.0,
                accuracy: 20
            )
        }
        store.ingestHistorical(batch)

        let stat = try XCTUnwrap(try stats(container)[.imported])
        XCTAssertEqual(stat.accepted, 5)
    }

    func testSamplesCarryTheirLayerForExport() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)
        store.ingest(payload(), layer: .heartbeat, now: now)

        let stored = try container.mainContext.fetch(FetchDescriptor<LocationSample>())
        XCTAssertEqual(stored.first?.layer, .heartbeat)
    }

    /// 全削除したのにカウンタだけ残ると、実機での確認が誤解を生む。
    func testDeleteAllClearsCounters() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)
        store.ingest(payload(), layer: .geofence, now: now)

        let context = container.mainContext
        store.deleteAll(
            samples: try context.fetch(FetchDescriptor<LocationSample>()),
            cells: try context.fetch(FetchDescriptor<VisitedCell>())
        )

        XCTAssertTrue(try stats(container).isEmpty)
    }
}
