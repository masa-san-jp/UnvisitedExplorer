import UIKit

/// 記録エンジンを Scene の body 評価より前に起こすための入口(仕様 §3.4)。
///
/// CoreLocation は delegate が存在して初めてイベントを配信するため、
/// ここでの生成が遅れると起動理由となったイベント自体を取りこぼす。
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let engine = LocationEngine.shared

        if launchOptions?[.location] != nil {
            engine.noteLaunchedForLocationEvent()
        }

        // 起動理由によらず無条件で arm する。UI の表示を待たない。
        engine.start()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // L2 のチェーンが切れていた場合の復旧点。
        LocationEngine.shared.refreshAnchorIfPossible()
    }
}
