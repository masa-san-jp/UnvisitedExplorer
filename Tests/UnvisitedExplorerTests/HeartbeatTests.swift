import XCTest
@testable import UnvisitedExplorer

/// L3 の設定は Info.plist とコードの2箇所に分かれており、食い違うと
/// `BGTaskScheduler.register` が実行時にクラッシュする。ここで固定する。
final class HeartbeatTests: XCTestCase {
    private var infoPlist: [String: Any] {
        // アプリをホストにしたユニットテストなので Bundle.main はアプリ本体。
        Bundle.main.infoDictionary ?? [:]
    }

    func testIdentifierIsPermittedInInfoPlist() {
        let permitted = infoPlist["BGTaskSchedulerPermittedIdentifiers"] as? [String]
        XCTAssertNotNil(permitted, "BGTaskSchedulerPermittedIdentifiers が Info.plist にない")
        XCTAssertTrue(
            permitted?.contains(Heartbeat.identifier) == true,
            "Heartbeat.identifier (\(Heartbeat.identifier)) が Info.plist に登録されていない。"
            + "登録時にクラッシュする。実際の値: \(permitted ?? [])"
        )
    }

    func testBackgroundModesCoverBothRecordingPaths() {
        let modes = infoPlist["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("location"), "L0〜L2 と L4 に必要")
        XCTAssertTrue(modes.contains("fetch"), "L3 の BGAppRefreshTask に必要")
    }

    func testIntervalIsOneHour() {
        XCTAssertEqual(Heartbeat.interval, 3600)
    }

    /// 識別子はバンドルIDを前置しておく (Apple の推奨する命名)。
    func testIdentifierIsNamespacedUnderTheBundle() {
        XCTAssertTrue(Heartbeat.identifier.hasPrefix("jp.masa.UnvisitedExplorer."))
    }
}
