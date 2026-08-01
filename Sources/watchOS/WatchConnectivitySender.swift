import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivitySender: NSObject, ObservableObject {
    @Published private(set) var status = "接続準備中"

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            status = "WatchConnectivity非対応"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func enqueue(_ payload: LocationPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        WCSession.default.transferUserInfo(["locationPayload": data])
        status = "iPhoneへ転送待ち"
    }
}

extension WatchConnectivitySender: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            status = error == nil ? "転送可能" : "接続エラー"
        }
    }
}
