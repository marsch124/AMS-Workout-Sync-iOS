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

    /*
     * The three screens are pages you swipe between, as in AMS PARA, with a
     * bar of our own underneath — the page style has no tab bar of its own.
     */
    var body: some View {
        TabView(selection: $tab) {
            TodayView().tag("today")
            PlanTab().tag("plan")
            ProgressView().tag("progress")
            SettingsView().tag("settings")
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard)
        .safeAreaInset(edge: .bottom, spacing: 0) { BottomBar(tab: $tab, tint: tint) }
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
        case "progress": return Theme.progress
        case "settings": return Theme.settings
        default: return Theme.today
        }
    }
}


struct BottomBar: View {
    @Binding var tab: String
    let tint: Color

    private let items: [(id: String, label: String, icon: String)] = [
        ("today", "Today", "icon-today"), ("plan", "Sessions", "icon-plan"),
        ("progress", "Progress", "icon-progress"), ("settings", "Settings", "icon-settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { tab = item.id }
                } label: {
                    VStack(spacing: 3) {
                        Glyph(name: item.icon, size: 24)
                        Text(item.label).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(tab == item.id ? tint : Theme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }
}
