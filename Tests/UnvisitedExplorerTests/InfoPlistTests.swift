import XCTest
@testable import UnvisitedExplorer

/// ビルド後のアプリに設定が実際に入っているかを検証する。
///
/// project.yml で `info:` を指定すると XcodeGen が Config/iOS-Info.plist を
/// 生成し直し、手書きの設定が丸ごと消える。コンパイルは通るため、
/// このテストがないと実機で初めて気づくことになる
/// (位置情報の許可文言が無いと権限要求の時点でクラッシュする)。
final class InfoPlistTests: XCTestCase {
    /// アプリをホストにしたユニットテストなので Bundle.main はアプリ本体。
    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    private var diagnostics: String {
        "実際のキー: \(info.keys.sorted())"
    }

    func testHostBundleIsTheApp() {
        XCTAssertEqual(
            info["CFBundleIdentifier"] as? String,
            "jp.masa.UnvisitedExplorer",
            "テストがアプリをホストにしていない。以降の検証が無意味になる。\(diagnostics)"
        )
    }

    // MARK: - 位置情報の許可

    func testLocationUsageDescriptionsArePresent() {
        for key in [
            "NSLocationWhenInUseUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription"
        ] {
            let value = info[key] as? String
            XCTAssertFalse(
                (value ?? "").isEmpty,
                "\(key) が無い。権限要求の時点でクラッシュする。\(diagnostics)"
            )
        }
    }

    func testBackgroundModesCoverEveryRecordingLayer() {
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("location"), "L0〜L2 / L4 に必要。\(diagnostics)")
        XCTAssertTrue(modes.contains("fetch"), "L3 の BGAppRefreshTask に必要。\(diagnostics)")
    }

    // MARK: - L3

    func testHeartbeatIdentifierIsPermitted() {
        let permitted = info["BGTaskSchedulerPermittedIdentifiers"] as? [String]
        XCTAssertNotNil(permitted, "BGTaskSchedulerPermittedIdentifiers が無い。\(diagnostics)")
        XCTAssertTrue(
            permitted?.contains(Heartbeat.identifier) == true,
            "Heartbeat.identifier (\(Heartbeat.identifier)) が Info.plist に無い。"
            + "BGTaskScheduler.register が実行時にクラッシュする。実際の値: \(permitted ?? [])"
        )
    }

    // MARK: - 表示

    func testDisplayNameIsSetSeparatelyFromProductName() {
        // PRODUCT_NAME は ASCII に保つ必要があるため、表示名はここが担う。
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "未踏マップ", diagnostics)
    }
}
