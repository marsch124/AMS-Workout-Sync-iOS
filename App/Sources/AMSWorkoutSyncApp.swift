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
    @EnvironmentObject var store: Store
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
            if ProcessInfo.processInfo.environment["AMSWS_ZONES"] != nil {
                NavigationStack { ZonesView() }
            }
            // Screen walks: Settings → Extra activities, or the first extra's own screen.
            if ProcessInfo.processInfo.environment["AMSWS_EXTRAS"] != nil {
                NavigationStack { ExtrasListView() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_EXTRA_DETAIL"] != nil, let x = store.allExtras.first(where: { $0.dayKey == store.today }) ?? store.allExtras.first {
                ExtraDetailView(extra: x).environmentObject(store)
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

    /*
     * The four disciplines across the bar — his idea: swim, bike, run,
     * strength. The words carry the meaning, so the glyphs are free to say
     * what the app is about. Each still takes its page's colour.
     */
    private let items: [(id: String, label: String, icon: String)] = [
        ("today", "Today", "icon-swim"), ("plan", "Sessions", "icon-bike"),
        ("progress", "Progress", "icon-run"), ("settings", "Settings", "icon-strength")
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
                .accessibilityIdentifier("tab-" + item.id)
            }
        }
        .padding(.top, 6)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }
}
