import CoreLocation
import XCTest
@testable import UnvisitedExplorer

/// 精度棄却・重複排除の閾値境界(仕様 §10.1)。
final class RecordingFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let base = (latitude: 36.062, longitude: 139.667)

    private func payload(
        accuracy: Double = 10,
        offsetSeconds: TimeInterval = 0,
        latitudeOffset: Double = 0
    ) -> LocationPayload {
        LocationPayload(
            timestamp: now.addingTimeInterval(offsetSeconds),
            latitude: base.latitude + latitudeOffset,
            longitude: base.longitude,
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            speed: -1,
            course: -1,
            source: .iPhone
        )
    }

    private func decide(
        _ payload: LocationPayload,
        lastAccepted: AcceptedPoint? = nil,
        policy: IngestPolicy = .live
    ) -> RecordingFilter.Decision {
        RecordingFilter.decide(payload, lastAccepted: lastAccepted, now: now, policy: policy)
    }

    // MARK: - 精度

    func testThresholdIsDerivedFromCellSize() {
        XCTAssertEqual(RecordingPolicy.maxHorizontalAccuracy, 100)
    }

    func testAccuracyBoundary() {
        XCTAssertEqual(decide(payload(accuracy: 99)), .accept)
        XCTAssertEqual(decide(payload(accuracy: 100)), .accept)
        XCTAssertEqual(decide(payload(accuracy: 101)), .rejectAccuracy)
    }

    func testNegativeAccuracyIsRejected() {
        XCTAssertEqual(decide(payload(accuracy: -1)), .rejectAccuracy)
    }

    /// 以前は 500m を採用していたため、通っていないセルが踏破済みになっていた(Issue #2)。
    func testFiveHundredMetreFixIsRejected() {
        XCTAssertEqual(decide(payload(accuracy: 500)), .rejectAccuracy)
    }

    // MARK: - 鮮度

    func testStaleLiveFixIsRejected() {
        XCTAssertEqual(decide(payload(offsetSeconds: -301)), .rejectStale)
        XCTAssertEqual(decide(payload(offsetSeconds: -299)), .accept)
    }

    func testHistoricalImportSkipsTheFreshnessFilter() {
        let old = payload(offsetSeconds: -60 * 60 * 24 * 365)
        XCTAssertEqual(decide(old), .rejectStale)
        XCTAssertEqual(decide(old, policy: .historical), .accept)
    }

    // MARK: - 重複排除

    private func last(offsetSeconds: TimeInterval = 0) -> AcceptedPoint {
        AcceptedPoint(
            timestamp: now.addingTimeInterval(offsetSeconds),
            latitude: base.latitude,
            longitude: base.longitude
        )
    }

    /// 指定した実距離だけ北へずらすための緯度差を、実測から逆算する。
    /// 定数 111,320 を決め打ちすると 50m 境界の検証には誤差が大きすぎる。
    private func latitudeOffset(northBy metres: CLLocationDistance) -> Double {
        let origin = CLLocation(latitude: base.latitude, longitude: base.longitude)
        let probe = CLLocation(latitude: base.latitude + 0.01, longitude: base.longitude)
        let metresPerDegree = origin.distance(from: probe) / 0.01
        return metres / metresPerDegree
    }

    /// ヘルパ自体がずれていると境界テストが無意味になるので固定する。
    func testLatitudeOffsetHelperIsAccurate() {
        for metres in [49.0, 51.0] {
            let moved = CLLocation(
                latitude: base.latitude + latitudeOffset(northBy: metres),
                longitude: base.longitude
            )
            let actual = CLLocation(latitude: base.latitude, longitude: base.longitude)
                .distance(from: moved)
            XCTAssertEqual(actual, metres, accuracy: 0.5)
        }
    }

    func testDistanceThresholdIsFiftyMetres() {
        XCTAssertEqual(RecordingPolicy.minDistance, 50)
        XCTAssertEqual(RecordingPolicy.minInterval, 60)
    }

    func testJustUnderFiftyMetresWithinTheIntervalIsRejected() {
        let decision = decide(
            payload(offsetSeconds: 30, latitudeOffset: latitudeOffset(northBy: 49)),
            lastAccepted: last()
        )
        XCTAssertEqual(decision, .rejectDuplicate)
    }

    func testJustOverFiftyMetresIsAccepted() {
        let decision = decide(
            payload(offsetSeconds: 30, latitudeOffset: latitudeOffset(northBy: 51)),
            lastAccepted: last()
        )
        XCTAssertEqual(decision, .accept)
    }

    func testNearbyAndRecentIsRejected() {
        let decision = decide(
            payload(offsetSeconds: 59, latitudeOffset: 0.0001),
            lastAccepted: last()
        )
        XCTAssertEqual(decision, .rejectDuplicate)
    }

    func testEnoughTimeElapsedIsAccepted() {
        let decision = decide(
            payload(offsetSeconds: 61, latitudeOffset: 0.0001),
            lastAccepted: last()
        )
        XCTAssertEqual(decision, .accept)
    }

    func testEnoughDistanceMovedIsAccepted() {
        let decision = decide(
            payload(offsetSeconds: 30, latitudeOffset: 0.001),
            lastAccepted: last()
        )
        XCTAssertEqual(decision, .accept)
    }

    // MARK: - 座標

    func testOutOfRangeCoordinateIsRejected() {
        let broken = LocationPayload(
            timestamp: now,
            latitude: 91,
            longitude: 0,
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: -1,
            speed: -1,
            course: -1,
            source: .iPhone
        )
        XCTAssertEqual(decide(broken), .rejectCoordinate)
    }

    // MARK: - CLVisit の日付

    func testVisitTimestampPrefersDeparture() {
        let arrival = now.addingTimeInterval(-3_600)
        let departure = now.addingTimeInterval(-60)
        XCTAssertEqual(
            RecordingPolicy.visitTimestamp(arrival: arrival, departure: departure, now: now),
            departure
        )
    }

    func testVisitStillInProgressFallsBackToArrival() {
        let arrival = now.addingTimeInterval(-3_600)
        XCTAssertEqual(
            RecordingPolicy.visitTimestamp(arrival: arrival, departure: .distantFuture, now: now),
            arrival
        )
    }

    func testVisitWithNoUsableDatesFallsBackToNow() {
        XCTAssertEqual(
            RecordingPolicy.visitTimestamp(arrival: .distantPast, departure: .distantFuture, now: now),
            now
        )
    }
}
