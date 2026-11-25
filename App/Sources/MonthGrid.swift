import SwiftUI
import WorkoutCore

/*
 * The Month view of the Plan page: the month as a calendar, a row per week.
 * On the left of each row the week's number, its tag, its planned hours and
 * what is done; then seven day cells, Monday to Sunday, each with one chip per
 * session. Days of the neighbouring months are dimmed. A session still to do
 * can be dragged to another day, as on the week board, with the same line to
 * undo it; a tap on a chip opens the session.
 */
struct MonthGrid: View {
    @EnvironmentObject var store: Store
    /* "2026-11". */
    let month: String
    /* The room under the heading on a wide window; when the full titles would not fit it, the chips say the sport. nil: width alone decides. */
    var fitHeight: CGFloat? = nil
    /* A tap on "+2 more": that day's week on the board. */
    let openWeek: (String) -> Void

    @State private var moved: MovedLine.Moved?
    @State private var openExtra: ExtraSummary?
    /* The grid's width: below about a hundred points a cell, the chips say the sport instead of the title. */
    @State private var width: CGFloat = 900
    /* How tall the weeks stand with full titles, measured on a hidden copy. */
    @State private var fullHeight: CGFloat = 0

    static let weekColumn: CGFloat = 74
    /* The most chips a cell shows; with more, the last line says how many more there are. */
    static let mostChips = 3

    private static let monthName: DateFormatter = Dates.formatter("MMMMyyyy")

    /* "November 2026". */
    /* The scroll place of a week's row, so the Plan page can bring today's week into view. */
    static func rowID(_ monday: String) -> String { "month-row-" + monday }

    /* Short sport words when a cell is narrow, or when the month with full titles would not fit the room. */
    private var compact: Bool {
        if (width - Self.weekColumn - 28) / 7 < 100 { return true }
        // The day names' line and the moved line's room above and below the weeks.
        if let fitHeight, fullHeight > 0, fullHeight + 24 > fitHeight { return true }
        return false
    }

    static func title(_ month: String) -> String {
        parseDayKey(PlanOverview.firstDay(month)).map { monthName.string(from: $0) } ?? month
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let view = store.view {
                HStack(spacing: 4) {
                    Color.clear.frame(width: Self.weekColumn, height: 1)
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { d in
                        Text(d).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                            .padding(.leading, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PlanOverview.grid(month), id: \.self) { row in
                        weekRow(row, view, compact: compact)
                            .id(Self.rowID(row[0]))
                    }
                }
                // The same weeks with full titles, never seen: their height decides whether the full titles fit.
                .background(alignment: .topLeading) {
                    if fitHeight != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(PlanOverview.grid(month), id: \.self) { row in
                                weekRow(row, view, compact: false)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        .hidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                MovedLine(moved: $moved)
            } else {
                EmptyWorkbook()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("month-grid")
        .sheet(item: $openExtra) { x in ExtraDetailView(extra: x).environmentObject(store) }
    }

    private func weekRow(_ row: [String], _ view: PlanView, compact: Bool) -> some View {
        let monday = row[0]
        let days = view.week(of: monday, today: store.today)
        return HStack(alignment: .top, spacing: 4) {
            weekLabel(monday, view)
                .frame(width: Self.weekColumn, alignment: .leading)
            ForEach(days) { day in
                MonthDayCell(day: day, sessions: shown(day), inMonth: day.dayKey.hasPrefix(month),
                             compact: compact,
                             mapping: view.mapping, canChange: store.canChangePlan,
                             more: { openWeek(day.dayKey) },
                             openExtra: { openExtra = $0 },
                             drop: { key in
                                 guard let m = MovedLine.move(store, key, to: day.dayKey) else { return false }
                                 moved = m
                                 return true
                             })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Every cell of the row as tall as its fullest day.
        .fixedSize(horizontal: false, vertical: true)
    }

    /* "Week 12", its tag, its planned hours and what is done, each on a line of its own. */
    private func weekLabel(_ monday: String, _ view: PlanView) -> some View {
        let week = store.book?.week(on: monday)
        let hours = PlanOverview.hours(view.plan, view.mapping, from: monday, to: PlanView.addDays(monday, 6))
        let tag: String? = week.flatMap { w in w.isTest ? "Test week" : (w.isEasy ? "Easy week" : nil) }
        return VStack(alignment: .leading, spacing: 1) {
            Text(week.map { "Week \($0.number)" } ?? Dates.short(monday))
                .font(.footnote.weight(.bold)).foregroundStyle(Theme.text)
            if let tag {
                Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(Theme.text)
            }
            if hours.planned > 0 {
                Text(formatDuration(hours.planned)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.text)
            }
            if hours.done > 0 {
                Text("\(formatDuration(hours.done)) done").font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.top, 5)
        .accessibilityElement(children: .combine)
    }

    /* As on the board: a rest row is not shown on a day that has a session moved onto it. */
    private func shown(_ day: PlanDay) -> [Workout] {
        day.isRest || day.training.isEmpty ? day.sessions : day.training
    }
}

/* One day of the month: its date, its chips, and a drop place for a dragged session. */
struct MonthDayCell: View {
    let day: PlanDay
    let sessions: [Workout]
    let inMonth: Bool
    let compact: Bool
    let mapping: Mapping
    let canChange: Bool
    let more: () -> Void
    let openExtra: (ExtraSummary) -> Void
    let drop: (String) -> Bool

    @State private var targeted = false

    private var count: Int { sessions.count + day.extras.count }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        // With more than fit, one line fewer of chips and the last line says how many more.
        let room = count > MonthGrid.mostChips ? MonthGrid.mostChips - 1 : count
        let showSessions = Array(sessions.prefix(room))
        let showExtras = Array(day.extras.prefix(max(0, room - showSessions.count)))
        VStack(alignment: .leading, spacing: 3) {
            Text(String(utc.component(.day, from: day.date)) + (day.isToday ? " \u{00B7} Today" : ""))
                .font(.caption.weight(day.isToday ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(day.isToday ? Theme.today : Theme.secondary)
            ForEach(showSessions) { w in
                MonthChip(workout: w, mapping: mapping, movable: canChange, compact: compact)
            }
            ForEach(showExtras) { x in
                Button { openExtra(x) } label: { MonthExtraChip(extra: x, compact: compact) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("month-extra-\(x.id)")
            }
            if count > room {
                Button(action: more) {
                    Text("+\(count - room) more")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Theme.today)
                        .padding(.vertical, 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("month-more-\(day.dayKey)")
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(day.isToday ? Theme.todayColumn : Theme.dayColumn))
        // The neighbouring months' days, dimmed.
        .opacity(inMonth ? 1 : 0.45)
        .overlay(shape.strokeBorder(Theme.plan, lineWidth: targeted ? 2 : 0))
        .contentShape(shape)
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first else { return false }
            return drop(key)
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("month-day-\(day.dayKey)")
    }
}

/* A session in a month cell: the sport's colour as the left edge, the short title with its length, the done tick or the missed mark. */
struct MonthChip: View {
    let workout: Workout
    let mapping: Mapping
    let movable: Bool
    var compact = false

    private var state: SessionState { workout.state }

    var body: some View {
        let chip = NavigationLink(value: workout.key) { face }
            .buttonStyle(.plain)
            .accessibilityIdentifier("month-chip-\(workout.key)")
        if movable && state == .todo && workout.discipline.id != "rest" {
            chip.draggable(workout.key)
        } else {
            chip
        }
    }

    private var minutes: String? {
        guard let s = Plan.plannedSeconds(workout, mapping), s > 0 else { return nil }
        // One way of writing a length everywhere: "45m", "1h 10m".
        return formatDuration((s / 60).rounded() * 60)
    }

    /* In a narrow cell the sport's own word ("Run", "Swim"), which always fits; else the session's short title. */
    private var name: String {
        compact && workout.discipline.id != "rest" ? workout.discipline.label : BoardCard.keepTogether(Self.chipTitle(workout.title))
    }

    /* Shorter still than the board's: the words before a comma or a plus, when that leaves something to read. */
    static func chipTitle(_ raw: String) -> String {
        var t = BoardCard.boardTitle(raw)
        for cut in [", ", " + "] {
            if let r = t.range(of: cut), t.distance(from: t.startIndex, to: r.lowerBound) >= 6 {
                t = String(t[..<r.lowerBound])
            }
        }
        return t
    }

    private var face: some View {
        let sport = Theme.sport(workout.discipline.id)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if compact {
                    // One word, made a little smaller rather than cut.
                    Text(name).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text(name).lineLimit(3).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
            // Its length, then the done tick or the missed word on the same line.
            HStack(spacing: 3) {
                // In a narrow cell a missed session says only that; its length is on its page.
                if let minutes, !(compact && state == .missed) {
                    Text(minutes).font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if state == .missed {
                    Text("Missed").font(.caption2.weight(.semibold)).foregroundStyle(Theme.danger)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if state == .done {
                    ZStack {
                        Circle().fill(Theme.today)
                        Glyph(name: "icon-check", size: 7).foregroundStyle(Color.white)
                    }
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("Done")
                }
            }
        }
        .padding(.leading, 7).padding(.trailing, 4).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Group {
                if state == .missed {
                    Rectangle().fill(Color.clear).overlay(Hatch().stroke(sport, lineWidth: 1.2))
                } else {
                    Rectangle().fill(sport)
                }
            }
            .frame(width: 3)
            .clipped()
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(state == .missed ? Theme.danger.opacity(0.7) : Theme.border, lineWidth: state == .missed ? 1.2 : 0.5))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([workout.title, minutes ?? "", state == .done ? "Done" : (state == .missed ? "Missed" : "")]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/* An extra in a month cell: dotted outline in its own colour and the paler tick, as extras carry everywhere. */
struct MonthExtraChip: View {
    let extra: ExtraSummary
    var compact = false

    var body: some View {
        let colour = Theme.sport(Extras.activity(extra.activity).colorId)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        // The name has the chip's whole width; the length and the paler tick share the line under it, as on a session chip.
        return VStack(alignment: .leading, spacing: 0) {
            Text(Extras.activity(extra.activity).label)
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(compact ? 0.6 : 0.7)
            HStack(spacing: 3) {
                if let m = extra.minutes {
                    Text(formatDuration(m * 60)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(Theme.today.opacity(0.6))
                    Glyph(name: "icon-check", size: 7).foregroundStyle(Color.white)
                }
                .frame(width: 12, height: 12)
                .accessibilityLabel("Done")
            }
        }
        .padding(.leading, 5).padding(.trailing, 4).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(colour.opacity(0.16)))
        .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(colour))
        .contentShape(shape)
    }
}
