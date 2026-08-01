import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                VisitedMapView()
            }
            .tabItem { Label("地図", systemImage: "map") }

            NavigationStack {
                InsightsView()
            }
            .tabItem { Label("記録", systemImage: "chart.bar") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
