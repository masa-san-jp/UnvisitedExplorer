import XCTest
@testable import UnvisitedExplorer

/// L3 の定数。Info.plist 側との整合は InfoPlistTests が見る。
final class HeartbeatTests: XCTestCase {
    func testIntervalIsOneHour() {
        XCTAssertEqual(Heartbeat.interval, 3600)
    }

    /// 識別子はバンドルIDを前置する (Apple の推奨する命名)。
    func testIdentifierIsNamespacedUnderTheBundle() {
        XCTAssertTrue(Heartbeat.identifier.hasPrefix("jp.masa.UnvisitedExplorer."))
    }
}
