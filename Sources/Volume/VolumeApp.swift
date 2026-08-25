import SwiftUI

@main
struct VolumeApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1040, height: 700)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
            WeekView()
                .tabItem { Label("Week", systemImage: "chart.bar.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
        }
    }
}
