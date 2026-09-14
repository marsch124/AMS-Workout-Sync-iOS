import SwiftUI
import WorkoutCore

@main
struct AMSWorkoutSyncApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onChange(of: scenePhase) { _, phase in
                    // The plan may have been logged in the web app or edited in
                    // Excel since it was last read.
                    if phase == .active { store.refresh() }
                }
        }
    }
}

struct RootView: View {
    @State private var tab: String = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_TAB"] ?? "today"
        #else
        return "today"
        #endif
    }()

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label { Text("Today") } icon: { Image("icon-today") } }
                .tag("today")
            PlanTab()
                .tabItem { Label { Text("Plan") } icon: { Image("icon-plan") } }
                .tag("plan")
            SettingsView()
                .tabItem { Label { Text("Settings") } icon: { Image("icon-settings") } }
                .tag("settings")
        }
        .tint(tint)
        #if DEBUG
        .overlay {
            if let key = ProcessInfo.processInfo.environment["AMSWS_SESSION"] {
                NavigationStack { SessionView(key: key) }
            }
        }
        #endif
    }

    private var tint: Color {
        switch tab {
        case "plan": return Theme.plan
        case "settings": return Theme.settings
        default: return Theme.today
        }
    }
}
