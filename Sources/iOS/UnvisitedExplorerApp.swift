import SwiftData
import SwiftUI

@main
@MainActor
struct UnvisitedExplorerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = LocationEngine.shared

    private let watchReceiver: WatchConnectivityReceiver

    init() {
        watchReceiver = WatchConnectivityReceiver { payload in
            _ = LocationEngine.shared.store.ingest(payload, layer: .watch)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(engine.store)
        }
        .modelContainer(Persistence.container)
    }
}
