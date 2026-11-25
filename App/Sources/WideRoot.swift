import SwiftUI
import WorkoutCore

/* The side list's rows, in order. */
enum SideRow: String, CaseIterable {
    case today, week, season, sessions, progress, settings

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .season: return "Season"
        case .sessions: return "Sessions"
        case .progress: return "Progress"
        case .settings: return "Settings"
        }
    }

    /* Each word in its part's colour. */
    var colour: Color {
        switch self {
        case .today: return Theme.today
        case .week: return Theme.week
        case .season: return Theme.season
        case .sessions: return Theme.plan
        case .progress: return Theme.progress
        case .settings: return Theme.settings
        }
    }
}

/*
 * The wide look's root: a side list on the left (his pick, 25 Nov 2026: "1 and 3
 * both"), the chosen page on the right. The app opens on Today.
 */
struct WideRoot: View {
    @EnvironmentObject var store: Store
    @State private var selection: SideRow = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["AMSWS_SIDE"], let row = SideRow(rawValue: name) { return row }
        #endif
        return .today
    }()
    /* The week the Week and Season pages show: the Monday's day key. Both pages share it. */
    @State private var weekStart: String = ""
    @State private var todayPath = NavigationPath()
    @State private var sessionsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var weekPath = NavigationPath()
    @State private var seasonPath = NavigationPath()

    var body: some View {
        HStack(spacing: 0) {
            SideList(selection: $selection, again: backToFirstScreen)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
        }
        .onAppear { if weekStart.isEmpty { weekStart = PlanView.weekStart(store.today) } }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .today:
            TodayView(path: $todayPath, goToSettings: { selection = .settings })
                .readableWidth(680)
        case .week:
            WeekPage(season: false, weekStart: $weekStart, path: $weekPath)
        case .season:
            WeekPage(season: true, weekStart: $weekStart, path: $seasonPath)
        case .sessions:
            PlanTab(path: $sessionsPath)
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
        case .week: weekPath = NavigationPath()
        case .season: seasonPath = NavigationPath()
        case .sessions: sessionsPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        case .progress: break
        }
    }
}

struct SideList: View {
    @EnvironmentObject var store: Store
    @Binding var selection: SideRow
    var again: (SideRow) -> Void = { _ in }

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

/*
 * The Week page (look 1) and the Season page (look 3): the same week board, the
 * Season page with every week of the plan above it and the phases below.
 */
struct WeekPage: View {
    @EnvironmentObject var store: Store
    let season: Bool
    @Binding var weekStart: String
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if season { SeasonView(weekStart: $weekStart) }
                    WeekBoard(weekStart: $weekStart, columnHeight: season ? 250 : 430)
                    if season { SeasonPhases() }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .refreshable { store.refresh() }
            .navigationDestination(for: String.self) { key in
                SessionView(key: key).readableWidth(680)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
