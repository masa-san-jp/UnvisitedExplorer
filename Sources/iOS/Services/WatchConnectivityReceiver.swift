import Foundation
import WatchConnectivity

final class WatchConnectivityReceiver: NSObject {
    private let ingest: @MainActor (LocationPayload) -> Void

    init(ingest: @escaping @MainActor (LocationPayload) -> Void) {
        self.ingest = ingest
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension WatchConnectivityReceiver: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["locationPayload"] as? Data,
              let payload = try? JSONDecoder().decode(LocationPayload.self, from: data) else { return }
        Task { @MainActor in ingest(payload) }
    }
}
