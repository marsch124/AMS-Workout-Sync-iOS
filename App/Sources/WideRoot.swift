import SwiftUI
import WorkoutCore

/* The side list's rows, in order (his pick, 25 Nov 2026: one Plan page holds the week, the month and the year). */
enum SideRow: String, CaseIterable {
    case today, plan, sessions, body, progress, settings

    var title: String {
        switch self {
        case .today: return "Today"
        case .plan: return "Plan"
        case .sessions: return "Sessions"
        case .body: return "Body"
        case .progress: return "Progress"
        case .settings: return "Settings"
        }
    }

    /* Each word in its part's colour. */
    var colour: Color {
        switch self {
        case .today: return Theme.today
        case .plan: return Theme.week
        case .sessions: return Theme.plan
        case .body: return Theme.body
        case .progress: return Theme.progress
        case .settings: return Theme.settings
        }
    }
}

/*
 * The wide look's root: a side list on the left, the chosen page on the right
 * (his pick, 25 Nov 2026: one Plan page with Week, Month and Year, the season
 * always on top, his numbers beside it). The app opens on Today.
 */
struct WideRoot: View {
    @EnvironmentObject var store: Store
    @State private var selection: SideRow = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["AMSWS_SIDE"], let row = SideRow(rawValue: name) { return row }
        #endif
        return .today
    }()
    /* The Plan page's view, the week it shows (its Monday's day key) and the month ("2026-11"). */
    @State private var planMode: PlanMode = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["AMSWS_PLAN"], let mode = PlanMode(rawValue: name) { return mode }
        #endif
        return .week
    }()
    @State private var weekStart: String = ""
    @State private var month: String = ""
    @State private var todayPath = NavigationPath()
    @State private var sessionsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var planPath = NavigationPath()
    /* Round 28: the Keys plate (AMSWS_KEYS=1 opens it for a picture) and ⌘N's new-session page. */
    @State private var showKeys: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_KEYS"] != nil
        #else
        return false
        #endif
    }()
    @State private var newSessionOn: WeekBoard.DayKey?

    var body: some View {
        HStack(spacing: 0) {
            SideList(selection: $selection, again: backToFirstScreen, openKeys: { showKeys = true })
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
        }
        .onAppear {
            if weekStart.isEmpty { weekStart = PlanView.weekStart(store.today) }
            if month.isEmpty { month = PlanOverview.month(of: store.today) }
        }
        .background { wideKeys }
        .sheet(isPresented: $showKeys) { KeysPlate() }
        .sheet(item: $newSessionOn) { day in
            SessionEditView(key: nil, draft: SessionDraft(dayKey: day.id, sport: "run")).environmentObject(store)
        }
        .systemLinks { target in
            switch target {
            case .today:
                selection = .today
                todayPath = NavigationPath()
            case .session(let key):
                selection = .today
                todayPath = NavigationPath()
                todayPath.append(key)
            case .page(let name):
                // 2.11: amsworkoutsync://plan and the other pages pick that row of the side list.
                if let row = SideRow(rawValue: name) { selection = row }
            }
        }
    }

    /* Round 28: ⌘N, ← →, ⌘T, ⌘F, ? — hooks into this root's own state. */
    private var wideKeys: some View {
        WideKeys(
            newSession: {
                guard store.canChangePlan else { return }
                newSessionOn = WeekBoard.DayKey(id: KeyGuide.newSessionDay(
                    today: store.today, onPlan: selection == .plan, mode: planMode.rawValue, weekStart: weekStart, month: month))
            },
            step: { direction in
                guard selection == .plan, planPath.isEmpty, !showKeys, newSessionOn == nil else { return }
                switch planMode {
                case .week: weekStart = PlanView.addDays(weekStart.isEmpty ? PlanView.weekStart(store.today) : weekStart, 7 * direction)
                case .month: month = PlanOverview.adding(direction, to: month.isEmpty ? PlanOverview.month(of: store.today) : month)
                case .year: break
                }
            },
            today: {
                if selection == .plan {
                    weekStart = PlanView.weekStart(store.today)
                    month = PlanOverview.month(of: store.today)
                } else {
                    selection = .today
                    todayPath = NavigationPath()
                }
            },
            focusSearch: { SearchFocus.focus() },
            showKeys: { showKeys = true })
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .today:
            TodayView(path: $todayPath, goToSettings: { selection = .settings })
                .readableWidth(760)
        case .plan:
            PlanPage(mode: $planMode, weekStart: $weekStart, month: $month, path: $planPath)
        case .sessions:
            PlanTab(path: $sessionsPath)
                .environment(\.wideReadableLimit, 760)
        case .body:
            BodyView()
        case .progress:
            ProgressView()
        case .settings:
            SettingsView(path: $settingsPath)
                .readableWidth(680)
        }
    }

    /* Pressing the row already open comes back to its own first screen, as the phone's bar does. */
    private func backToFirstScreen(_ row: SideRow) {
        switch row {
        case .today: todayPath = NavigationPath()
        case .plan: planPath = NavigationPath()
        case .sessions: sessionsPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        case .body, .progress: break
        }
    }
}

struct SideList: View {
    @EnvironmentObject var store: Store
    @Binding var selection: SideRow
    var again: (SideRow) -> Void = { _ in }
    var openKeys: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Triathlon")
                .font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 10).padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(SideRow.allCases.enumerated()), id: \.element) { index, row in
                rowButton(row, index)
            }
            Spacer(minLength: 12)
            Button(action: openKeys) {
                Text("Keys")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.settings)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keys-open")
            syncLine
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(width: 216)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidePanel.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.border).frame(width: 0.5).ignoresSafeArea()
        }
    }

    private func rowButton(_ row: SideRow, _ index: Int) -> some View {
        let on = selection == row
        return Button {
            if on { again(row) } else { selection = row }
        } label: {
            Text(row.title)
                .font(.headline)
                .foregroundStyle(row.colour)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? Theme.surface : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(on ? Theme.border : Color.clear, lineWidth: 0.5))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("side-" + row.rawValue)
    }

    /* The sync dot is always with its words: the dot alone never carries the meaning. */
    private var syncLine: some View {
        let status = store.syncStatus
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(status.tint).frame(width: 8, height: 8)
            Text(status.words)
                .font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.words)
        .accessibilityIdentifier("sync-status")
    }
}
