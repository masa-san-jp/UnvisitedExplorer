import BackgroundTasks
import Foundation

/// L3 時刻ハートビート(仕様 §3.3)。
///
/// 「1時間おき」に見えるが、実際の発火タイミングは OS が使用パターン・電池残量・
/// 低電力モードから決める。強制終了後は次に手動起動するまで発火しない。
/// したがってこれは**保険**であり、記録の主軸は L0〜L2。
enum Heartbeat {
    /// Info.plist の BGTaskSchedulerPermittedIdentifiers と一致していること。
    /// 食い違うと登録時にクラッシュするため、ユニットテストで固定している。
    static let identifier = "jp.masa.UnvisitedExplorer.heartbeat"
    static let interval: TimeInterval = 3600

    /// `didFinishLaunchingWithOptions` が return する前に呼ぶ必要がある。
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // シミュレータや権限なしでは submit が失敗する。記録の主軸ではないので握る。
            NSLog("ハートビートの登録に失敗: \(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // リクエストは発火時に消費される。最初に次回を積まないと二度と発火しない。
        schedule()

        Task { @MainActor in
            // expirationHandler と通常完了の両方から setTaskCompleted が呼ばれると
            // クラッシュするため、一度きりに制限する。
            let once = OnceBox()
            task.expirationHandler = {
                Task { @MainActor in
                    once.run { task.setTaskCompleted(success: false) }
                }
            }
            LocationEngine.shared.performHeartbeat { success in
                once.run { task.setTaskCompleted(success: success) }
            }
        }
    }
}

/// MainActor 上でのみ使う一度きりガード。
@MainActor
private final class OnceBox {
    private var done = false

    func run(_ body: () -> Void) {
        guard !done else { return }
        done = true
        body()
    }
}
