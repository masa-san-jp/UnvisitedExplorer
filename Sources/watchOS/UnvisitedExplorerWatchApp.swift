import SwiftUI

@main
@MainActor
struct UnvisitedExplorerWatchApp: App {
    @StateObject private var sender: WatchConnectivitySender
    @StateObject private var recorder: WatchLocationRecorder

    init() {
        let sender = WatchConnectivitySender()
        _sender = StateObject(wrappedValue: sender)
        _recorder = StateObject(wrappedValue: WatchLocationRecorder(sender: sender))
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(sender)
                .environmentObject(recorder)
        }
    }
}
