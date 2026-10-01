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
    @State private var todayPath = NavigationPath()
    @State private var planPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            TodayView(path: $todayPath).tag("today")
            PlanTab(path: $planPath).tag("plan")
            ProgressView().tag("progress")
            SettingsView(path: $settingsPath).tag("settings")
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Pressing the tab you are already on comes back to its own first
            // screen, as every other app does (his ask, 2026-10-01).
            BottomBar(tab: $tab, tint: tint) { which in
                switch which {
                case "today": todayPath = NavigationPath()
                case "plan": planPath = NavigationPath()
                case "settings": settingsPath = NavigationPath()
                default: break
                }
            }
        }
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
    /* Told when the tab already open is pressed again. */
    var again: (String) -> Void = { _ in }

    /*
     * The four disciplines across the bar — his idea: swim, bike, run,
     * strength. The words carry the meaning, so the glyphs are free to say
     * what the app is about. Each still takes its page's colour.
     */
    private let items: [(id: String, label: String, icon: String, colour: Color)] = [
        ("today", "Today", "icon-swim", Theme.today), ("plan", "Sessions", "icon-bike", Theme.plan),
        ("progress", "Progress", "icon-run", Theme.progress), ("settings", "Settings", "icon-strength", Theme.settings)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                Button {
                    if tab == item.id {
                        again(item.id)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { tab = item.id }
                    }
                } label: {
                    // Each tab keeps its own colour whether it is open or not,
                    // and the open one sits on a patch of it — the AMS
                    // Instructions bar he pointed at (2026-09-30).
                    let chosen = tab == item.id
                    VStack(spacing: 3) {
                        Glyph(name: item.icon, size: 24).foregroundStyle(item.colour)
                        Text(item.label).font(.caption2.weight(.semibold))
                            .foregroundStyle(chosen ? item.colour : Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(chosen ? item.colour.opacity(0.16) : .clear)
                            .padding(.horizontal, 6)
                    )
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
