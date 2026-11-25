import SwiftUI
import WorkoutCore

/* What the Plan page shows under the season: a week, a month, or the whole season. */
enum PlanMode: String, CaseIterable {
    case week, month, year

    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

/*
 * The Plan page of the wide look (his pick, 25 Nov 2026, option 2: "The Mac
 * app is where I get the total overview … per week, per month, per year").
 * The season bars always on top across the whole width; under them the switch
 * Week · Month · Year with the heading of what is shown and its hours; then
 * the chosen view, with his numbers in a column on the right — or under the
 * view when the window is too narrow for both.
 */
struct PlanPage: View {
    @EnvironmentObject var store: Store
    @Binding var mode: PlanMode
    /* The Monday of the week shown. */
    @Binding var weekStart: String
    /* The month shown, "2026-11". */
    @Binding var month: String
    @Binding var path: NavigationPath

    /* The numbers stand beside the view only when the view keeps room for seven readable day columns. */
    static let numbersWidth: CGFloat = 290
    static let besideFrom: CGFloat = 1150

    /* The height of everything above the view (season, heading, hint), so the month knows the room left under it. */
    @State private var topHeight: CGFloat = 0

    private var monday: String { weekStart.isEmpty ? PlanView.weekStart(store.today) : weekStart }
    private var shownMonth: String { month.isEmpty ? PlanOverview.month(of: store.today) : month }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        page(width: geo.size.width - 32, height: geo.size.height)
                            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
                    }
                    // When the month cannot fit the window, it opens with today's week in view.
                    .onAppear { showTodaysWeek(proxy) }
                    .onChange(of: mode) { showTodaysWeek(proxy) }
                    .onChange(of: shownMonth) { showTodaysWeek(proxy) }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .refreshable { store.refresh() }
            .navigationDestination(for: String.self) { key in
                SessionView(key: key).readableWidth(760)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func page(width: CGFloat, height: CGFloat) -> some View {
        if let view = store.view {
            let beside = width >= Self.besideFrom
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    SeasonView(weekStart: $weekStart, chosenWeeks: chosenWeeks, pick: { picked in
                        weekStart = picked
                        mode = .week
                    })
                    head(view)
                    ClaudeAskButton()
                    // The board says it itself, with "swipe sideways" beside it when not all days fit.
                    if store.canChangePlan && mode == .month {
                        Text("Drag a session to another day")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                            .accessibilityIdentifier("plan-hint")
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                if beside {
                    HStack(alignment: .top, spacing: 14) {
                        content(columnHeight: max(260, height - 330), fitHeight: height - topHeight - 12 - 10 - 24)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        PlanNumbers(from: range(view).from, to: range(view).to, scope: scopeWords, columns: 1)
                            .frame(width: Self.numbersWidth)
                    }
                } else {
                    content(columnHeight: 260, fitHeight: height - topHeight - 12 - 10 - 24)
                    PlanNumbers(from: range(view).from, to: range(view).to, scope: scopeWords, columns: 2)
                }
            }
        } else {
            EmptyWorkbook()
        }
    }

    // MARK: what is chosen

    /* The bars outlined above: the week shown, the weeks of the month shown, none for the year. */
    private var chosenWeeks: [String] {
        switch mode {
        case .week: return [monday]
        case .month: return PlanOverview.grid(shownMonth).compactMap(\.first)
        case .year: return []
        }
    }

    /* The days the heading and the numbers count: the week, the month, or the plan from first to last. */
    private func range(_ view: PlanView) -> (from: String, to: String) {
        switch mode {
        case .week: return (monday, PlanView.addDays(monday, 6))
        case .month: return (PlanOverview.firstDay(shownMonth), PlanOverview.lastDay(shownMonth))
        case .year:
            let days = view.plan.map(\.dayKey)
            return (days.min() ?? store.today, days.max() ?? store.today)
        }
    }

    // MARK: the heading row

    private func headline(_ view: PlanView) -> String {
        switch mode {
        case .week: return WeekBoard.headline(store.book, monday)
        case .month: return MonthGrid.title(shownMonth)
        case .year:
            let (from, to) = range(view)
            let a = String(from.prefix(4)), b = String(to.prefix(4))
            return a == b ? "Season \(a)" : "Season \(a)\u{2013}\(b.suffix(2))"
        }
    }

    private func head(_ view: PlanView) -> some View {
        let (from, to) = range(view)
        let hours = PlanOverview.hours(view.plan, view.mapping, from: from, to: to)
        let title = Text(headline(view))
            .font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            .accessibilityIdentifier("plan-title")
        let figure = Text(hours.done > 0 ? "\(formatDuration(hours.planned)) planned \u{00B7} \(formatDuration(hours.done)) done"
                                         : "\(formatDuration(hours.planned)) planned")
            .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.secondary)
            .lineLimit(1)
        // The switch and the buttons on one line, the title always on its own line under them, so it keeps
        // one place whatever week or month is shown; on a narrow window everything stacks; the title is never cut.
        return ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    PlanSwitch(mode: $mode)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) { steps }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    title.lineLimit(1).fixedSize()
                    figure.fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                PlanSwitch(mode: $mode)
                title.fixedSize(horizontal: false, vertical: true)
                figure
                HStack(spacing: 6) { steps }
            }
        }
    }

    @ViewBuilder private var steps: some View {
        PlanPrintButton(stepLook: true)
        switch mode {
        case .week:
            StepButton(words: "Previous week", id: "week-prev") { weekStart = PlanView.addDays(monday, -7) }
            StepButton(words: "This week", id: "week-this") { weekStart = PlanView.weekStart(store.today) }
            StepButton(words: "Next week", id: "week-next") { weekStart = PlanView.addDays(monday, 7) }
        case .month:
            StepButton(words: "Previous month", id: "month-prev") { month = PlanOverview.adding(-1, to: shownMonth) }
            StepButton(words: "This month", id: "month-this") { month = PlanOverview.month(of: store.today) }
            StepButton(words: "Next month", id: "month-next") { month = PlanOverview.adding(1, to: shownMonth) }
        case .year:
            EmptyView()
        }
    }

    // MARK: the view and the numbers

    @ViewBuilder
    private func content(columnHeight: CGFloat, fitHeight: CGFloat?) -> some View {
        switch mode {
        case .week:
            WeekBoard(weekStart: $weekStart, columnHeight: columnHeight, showsHead: false)
        case .month:
            MonthGrid(month: shownMonth, fitHeight: fitHeight, openWeek: { day in
                weekStart = PlanView.weekStart(day)
                mode = .week
            })
        case .year:
            YearView(openMonth: { m in
                month = m
                mode = .month
            })
        }
    }

    /* Today's week row brought into view in the Month when it is this month; a row already in view does not move. */
    private func showTodaysWeek(_ proxy: ScrollViewProxy) {
        guard mode == .month, shownMonth == PlanOverview.month(of: store.today) else { return }
        let row = MonthGrid.rowID(PlanView.weekStart(store.today))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            proxy.scrollTo(row, anchor: .bottom)
        }
    }

    private var scopeWords: String {
        switch mode {
        case .week: return monday == PlanView.weekStart(store.today) ? "This week" : "Week of " + Dates.short(monday)
        case .month: return MonthGrid.title(shownMonth)
        case .year: return "The season"
        }
    }
}

/* Week · Month · Year: three words in one switch, the chosen one filled in the plan's blue. */
struct PlanSwitch: View {
    @Binding var mode: PlanMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PlanMode.allCases, id: \.self) { m in
                let on = m == mode
                Button { mode = m } label: {
                    Text(m.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? Color.white : Theme.plan)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(on ? Theme.plan : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("plan-switch-\(m.rawValue)")
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(Theme.plan.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-switch")
    }
}
