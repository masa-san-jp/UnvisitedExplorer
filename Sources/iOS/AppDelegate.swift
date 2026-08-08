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
        // BGTaskScheduler への登録はこのメソッドが return する前に済ませる必要がある。
        Heartbeat.register()

        let engine = LocationEngine.shared

        if launchOptions?[.location] != nil {
            engine.noteLaunchedForLocationEvent()
        }

        // 起動理由によらず無条件に arm する。UI の表示を待たない。
        engine.start()

        Heartbeat.schedule()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // L2 のチェーンが切れていた場合の復旧点。
        LocationEngine.shared.refreshAnchorIfPossible()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 次回のハートビートを積み直す。submit 済みなら無害。
        Heartbeat.schedule()
    }
}
