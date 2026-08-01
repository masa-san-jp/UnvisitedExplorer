import SwiftData
import SwiftUI

@main
@MainActor
struct UnvisitedExplorerApp: App {
    private let container: ModelContainer
    @StateObject private var store: LocationStore
    @StateObject private var recorder: LocationRecorder
    private let watchReceiver: WatchConnectivityReceiver

    init() {
        do {
            let container = try ModelContainer(for: LocationSample.self, VisitedCell.self)
            let store = LocationStore(container: container)
            self.container = container
            _store = StateObject(wrappedValue: store)
            _recorder = StateObject(
                wrappedValue: LocationRecorder { payload in
                    store.ingest(payload)
                }
            )
            watchReceiver = WatchConnectivityReceiver { payload in
                store.ingest(payload)
            }
        } catch {
            fatalError("SwiftDataの初期化に失敗しました: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(recorder)
        }
        .modelContainer(container)
    }
}
