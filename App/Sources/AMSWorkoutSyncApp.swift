import SwiftUI
import WorkoutCore

@main
struct AMSWorkoutSyncApp: App {
    @StateObject private var store = IntentStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() { ReminderCentre.shared.start() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { SuggestionKeeper.shared.attach(store); ReminderCentre.shared.attach(store) }
                .onChange(of: scenePhase) { _, phase in
                    // The plan may have been logged in the web app or edited in
                    // Excel since it was last read.
                    if phase == .active {
                        store.refresh()
                        ReminderCentre.shared.replan()
                        // The night's numbers arrive while the app is closed, and
                        // Today read them once, at first sight. Opening the app
                        // is when they are wanted (27 October 2026: the line
                        // appeared only after a visit to Settings forced a
                        // second read).
                        Task { await HealthImport.shared.readMorning() }
                        // The hikes and gym sessions outside the plan, for Load.
                        Task { await Diary.shared.readHealth(today: store.today) }
                        Neighbours.shared.cameToFront(today: store.today)
                        Neighbours.shared.tickFromNeighbours(store: store)
                        Task { await GarminStrengthTick.run(store: store) }
                    }
                    // Going to the background: what was just logged goes to iCloud now, not at the next opening.
                    if phase == .background { store.cloud.goingToBackground() }
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

    /* The wide look (iPad, and the iPad app on the Mac) sits behind regular width. An iPhone turned on its side can
       report regular width too; it keeps the phone look, which is the one he placed. */
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var wide: Bool { sizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone }

    var body: some View {
        if wide {
            WideRoot()
                .tint(Theme.today)
                .overlay { debugScreens }
        } else {
            phoneBody
        }
    }

    private var phoneBody: some View {
        TabView(selection: $tab) {
            TodayView(path: $todayPath,
                      goToSettings: { withAnimation(.easeInOut(duration: 0.2)) { tab = "settings" } })
                .tag("today")
            PlanTab(path: $planPath).tag("plan")
            BodyView().tag("body")
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
        .overlay { debugScreens }
        // amsworkoutsync://today, from Workouts or Magic Morning: the first screen.
        .onOpenURL { url in
            if let key = ReminderCentre.shared.sessionKey(from: url) {
                tab = "today"
                todayPath = NavigationPath([key])
                return
            }
            guard url.host == "today" else { return }
            tab = "today"
            todayPath = NavigationPath()
        }
        // Round 28: amsworkoutsync://session/<key> and a Spotlight result open that session's page; Spotlight is kept up to date.
        .systemLinks { target in
            switch target {
            case .session(let key):
                tab = "today"
                todayPath = NavigationPath()
                todayPath.append(key)
            case .page(let name):
                // 2.11: the page's tab; the iPhone has no Sessions tab, so "sessions" opens Plan.
                tab = name == "sessions" ? "plan" : name
            case .today:
                break   // the .onOpenURL above already opened Today
            }
        }
    }

    /* Screen walks, DEBUG only: one page opened straight away, for a picture. */
    @ViewBuilder private var debugScreens: some View {
        #if DEBUG
            if ProcessInfo.processInfo.environment["AMSWS_FAKE_DONE"] != nil { let _ = store.debugSeedDone() }
            if let key = ProcessInfo.processInfo.environment["AMSWS_SESSION"] {
                NavigationStack { SessionView(key: key) }
            }
            if ProcessInfo.processInfo.environment["AMSWS_AWAY_PAGE"] != nil {
                NavigationStack { AwayPage() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_NOGYM"] != nil, ProcessInfo.processInfo.environment["AMSWS_SESSION"] == nil,
               let w = store.displayed.first(where: { $0.discipline.id == "strength" && !$0.logged }) ?? store.displayed.first(where: { $0.discipline.id == "strength" }) {
                NavigationStack { SessionView(key: w.key) }
            }
            // Screen walks: the first done session of a sport (AMSWS_DONE=run|bike|swim), or of any sport (=any).
            // Screen walks: the first planned (not done) session of a sport, e.g. AMSWS_PLANNED=swim.
            if let sp = ProcessInfo.processInfo.environment["AMSWS_PLANNED"], let w = store.displayed.first(where: { !$0.logged && $0.discipline.id == sp }) {
                NavigationStack { SessionView(key: w.key) }
            }
            let day = ProcessInfo.processInfo.environment["AMSWS_DONE_DAY"]   // optional: only that day
            if let sp = ProcessInfo.processInfo.environment["AMSWS_DONE"], let w = store.displayed.first(where: { $0.logged && (sp == "any" || $0.discipline.id == sp) && (day == nil || $0.dayKey == day) }) {
                NavigationStack { SessionView(key: w.key) }
            }
            // Screen walks: the Time in zones card alone on a Progress-coloured page (with AMSWS_ZONES_CARD=1).
            if ProcessInfo.processInfo.environment["AMSWS_ZONES_ONLY"] != nil {
                ScrollView { ZonesWeekCard().padding(16) }.background(Theme.bg.ignoresSafeArea()).environmentObject(store)
            }
            if ProcessInfo.processInfo.environment["AMSWS_REMINDERS_PAGE"] != nil {
                NavigationStack { RemindersSettingsView() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_CHANGES"] != nil {
                NavigationStack { PlanChangesView() }
            }
            // Suggestions: the stop-sign page, the Settings page with three sample rows, "Something hurts?".
            if ProcessInfo.processInfo.environment["AMSWS_STOP"] != nil {
                StopSignView()
            }
            if ProcessInfo.processInfo.environment["AMSWS_ILL"] != nil {
                IllnessView()
            }
            if ProcessInfo.processInfo.environment["AMSWS_SUGGEST_LOG"] != nil {
                let _ = SuggestionKeeper.shared.debugSeedLog()
                NavigationStack { SuggestionsSettingsView() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_HURTS"] != nil, ProcessInfo.processInfo.environment["AMSWS_SESSION"] == nil,
               let w = store.displayed.first(where: { $0.dayKey <= store.today && $0.discipline.id != "rest" && $0.logged })
                   ?? store.displayed.first(where: { $0.dayKey == store.today && $0.discipline.id != "rest" }) {
                NavigationStack { SessionView(key: w.key) }
            }
            if ProcessInfo.processInfo.environment["AMSWS_SAFETY"] != nil {
                let _ = store.debugSeedSafetyCopies()
                NavigationStack { SafetyCopiesView() }
            }
            FavouritesDebugScreens()
            RaceWeekDebugScreens().environmentObject(store)
            PlanMakerDebugScreens()
            if ProcessInfo.processInfo.environment["AMSWS_SLEEP_NEED_PAGE"] != nil {
                NavigationStack { SleepNeedView() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_MOBILITY"] != nil {
                NavigationStack { MobilityStrengthView() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_RACE_PAGE"] != nil {
                NavigationStack { RacePage() }.environmentObject(store)
            }
            if ProcessInfo.processInfo.environment["AMSWS_GEAR_PAGE"] != nil {
                NavigationStack { GearPage() }.environmentObject(store)
            }
            if ProcessInfo.processInfo.environment["AMSWS_MOVEIN"] != nil {
                NavigationStack { MoveInView() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_ZONES"] != nil || ProcessInfo.processInfo.environment["AMSWS_TEST"] != nil {
                NavigationStack { ZonesView() }
            }
            // Screen walks: Settings → Extra activities, or the first extra's own screen.
            // Garmin's morning numbers: the settings page, or the plate with invented numbers.
            if ProcessInfo.processInfo.environment["AMSWS_GARMIN_PAGE"] != nil {
                NavigationStack { GarminSettingsView() }.environmentObject(store)
            }
            // 2.22: How this works (=1), or it with one part's bigger view open (=today, =week, …).
            if let part = ProcessInfo.processInfo.environment["AMSWS_GUIDE"] {
                NavigationStack { GuideView(openFirst: part == "1" ? nil : part) }.environmentObject(store)
            }
            if ProcessInfo.processInfo.environment["AMSWS_CLAUDE_PAGE"] != nil {
                NavigationStack { ClaudeSettingsView() }.environmentObject(store)
            }
            if ClaudeDebug.ask != nil {
                NavigationStack { ClaudeAskView(inSheet: true) }.environmentObject(store)
            }
            if ProcessInfo.processInfo.environment["AMSWS_MORNING_PLATE"] != nil {
                MorningNumbersView(numbers: GarminReader.invented(day: store.today), today: store.today)
            }
            ProgressRound28Debug()
            LogExtrasDebug().environmentObject(store)
            if ProcessInfo.processInfo.environment["AMSWS_EXTRAS"] != nil {
                NavigationStack { ExtrasListView() }
            }
            if ProcessInfo.processInfo.environment["AMSWS_EXTRA_DETAIL"] != nil, let x = store.allExtras.first(where: { $0.dayKey == store.today }) ?? store.allExtras.first {
                ExtraDetailView(extra: x).environmentObject(store)
            }
            CoachDebugScreens()
            if ProcessInfo.processInfo.environment["AMSWS_POOL_CARD"] != nil, let w = store.displayed.first(where: { $0.discipline.id == "swim" }) {
                PoolCardView(title: w.title, set: w.swimSet, close: {})
            }
        #endif
    }

    private var tint: Color {
        switch tab {
        case "plan": return Theme.plan
        case "body": return Theme.body
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
        // Body sits in the middle with a mark of its own, the heart with a pulse line (his yes to the picture, 25 Nov 2026).
        ("body", "Body", "icon-body", Theme.body),
        ("progress", "Progress", "icon-run", Theme.progress), ("settings", "Settings", "icon-strength", Theme.settings)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                Button {
                    if tab == item.id {
                        again(item.id)
                    } else {
                        tab = item.id
                    }
                } label: {
                    // Each tab keeps its own colour whether it is open or not,
                    // and the open one's colour fills its whole cell — the full
                    // width of its quarter, from the top edge of the bar down to
                    // the bottom of the phone. It was a rounded pill floating
                    // inside the cell until he drew the cells he meant and chose
                    // this (2 October 2026).
                    let chosen = tab == item.id
                    VStack(spacing: 3) {
                        Glyph(name: item.icon, size: 24).foregroundStyle(item.colour)
                        Text(item.label).font(.caption2.weight(.semibold))
                            .foregroundStyle(chosen ? item.colour : Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(chosen ? item.colour.opacity(0.16) : .clear)
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
