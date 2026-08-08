import CoreLocation
import SwiftData
import XCTest
@testable import UnvisitedExplorer

@MainActor
final class LocationStoreImportTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_600_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: LocationSample.self,
            VisitedCell.self,
            RecordingStat.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// 互いに十分離れた点を作る。0.01度 ≒ 1.1km なので重複排除には掛からない。
    private func payloads(_ count: Int) -> [LocationPayload] {
        (0..<count).map { index in
            LocationImporter.make(
                timestamp: base.addingTimeInterval(Double(index) * 600),
                latitude: 36.0 + Double(index) * 0.01,
                longitude: 139.0,
                accuracy: 20
            )
        }
    }

    private func counts(_ container: ModelContainer) throws -> (samples: Int, cells: Int) {
        let context = container.mainContext
        return (
            try context.fetch(FetchDescriptor<LocationSample>()).count,
            try context.fetch(FetchDescriptor<VisitedCell>()).count
        )
    }

    func testHistoricalPointsAreStoredDespiteBeingOld() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        let summary = store.ingestHistorical(payloads(3))

        XCTAssertTrue(summary.isSuccess)
        XCTAssertEqual(summary.accepted, 3)
        XCTAssertEqual(summary.newCells, 3)
        XCTAssertEqual(try counts(container).samples, 3)
    }

    /// 鮮度フィルタは .historical では効かない。効いていたら1件も入らない。
    func testFreshnessFilterDoesNotApplyToImports() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        let ancient = LocationImporter.make(
            timestamp: Date(timeIntervalSince1970: 0),
            latitude: 36.062,
            longitude: 139.667,
            accuracy: 20
        )
        XCTAssertEqual(store.ingestHistorical([ancient]).accepted, 1)
    }

    /// 同じファイルを2回取り込んでも増えないこと。
    func testReimportingTheSameFileIsIdempotent() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)
        let batch = payloads(5)

        let first = store.ingestHistorical(batch)
        let second = store.ingestHistorical(batch)

        XCTAssertEqual(first.accepted, 5)
        XCTAssertEqual(second.accepted, 0)
        XCTAssertEqual(second.duplicated, 5)
        XCTAssertEqual(try counts(container).samples, 5)
    }

    func testAccuracyFilterStillAppliesToImports() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        let sloppy = LocationImporter.make(
            timestamp: base,
            latitude: 36.062,
            longitude: 139.667,
            accuracy: 500
        )
        let summary = store.ingestHistorical([sloppy])

        XCTAssertEqual(summary.accepted, 0)
        XCTAssertEqual(summary.rejected, 1)
        XCTAssertEqual(try counts(container).samples, 0)
    }

    /// 逆順で渡しても、時系列に並べ替えてから重複排除するので結果が変わらないこと。
    func testOrderOfInputDoesNotChangeTheOutcome() throws {
        let forward = try makeContainer()
        let backward = try makeContainer()
        let batch = payloads(6)

        let a = LocationStore(container: forward).ingestHistorical(batch)
        let b = LocationStore(container: backward).ingestHistorical(batch.reversed())

        XCTAssertEqual(a.accepted, b.accepted)
        XCTAssertEqual(try counts(forward).samples, try counts(backward).samples)
    }

    /// バッチ保存の境界 (500件) をまたいでも取りこぼさないこと。
    func testImportCrossesTheBatchBoundary() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)

        let summary = store.ingestHistorical(payloads(750))

        XCTAssertTrue(summary.isSuccess)
        XCTAssertEqual(summary.accepted, 750)
        XCTAssertEqual(try counts(container).samples, 750)
    }

    /// 取り込み後にライブ記録へ戻っても、古い点を基準に重複判定しないこと。
    func testLiveRecordingResumesAgainstTheNewestPointAfterImport() throws {
        let container = try makeContainer()
        let store = LocationStore(container: container)
        store.ingestHistorical(payloads(3))

        let now = Date()
        let live = LocationPayload(
            timestamp: now,
            latitude: 36.5,
            longitude: 139.5,
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: -1,
            speed: -1,
            course: -1,
            source: .iPhone
        )
        XCTAssertEqual(store.ingest(live, now: now), .accepted)
    }
}
