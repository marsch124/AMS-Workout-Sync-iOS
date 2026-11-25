import SwiftUI
import WorkoutCore

/*
 * The week board of the wide look: the whole week in seven columns, Monday to
 * Sunday. A session still to do can be dragged to another day (a drag, never
 * arrow buttons); the move is the same change the Change page makes, with only
 * the day new, and the board says so for eight seconds with a way to undo it.
 */
struct WeekBoard: View {
    @EnvironmentObject var store: Store
    /* The Monday shown. Empty means this week. */
    @Binding var weekStart: String
    /* The tallest a column is made to stand, so an empty day still takes a drop. */
    var columnHeight: CGFloat = 430
    /* The Plan page draws its own heading row and hint above the board. */
    var showsHead = true

    @State private var moved: MovedLine.Moved?
    @State private var addingOn: DayKey?
    @State private var openExtra: ExtraSummary?
    /* How many day columns stand side by side at once: seven when the window is wide enough. */
    @State private var visibleColumns = 7

    struct DayKey: Identifiable { let id: String }

    private var monday: String { weekStart.isEmpty ? PlanView.weekStart(store.today) : weekStart }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let view = store.view {
                let days = view.week(of: monday, today: store.today)
                if showsHead { head(days, view) }
                if let hint = hint {
                    Text(hint)
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("week-hint")
                }
                board(days, view)
                MovedLine(moved: $moved)
            } else {
                EmptyWorkbook()
            }
        }
        .accessibilityIdentifier("week-board")
        .sheet(item: $addingOn) { day in
            SessionEditView(key: nil, draft: SessionDraft(dayKey: day.id, sport: "run"))
                .environmentObject(store)
        }
        .sheet(item: $openExtra) { x in ExtraDetailView(extra: x).environmentObject(store) }
    }

    // MARK: the columns

    /* The narrowest a day column is made, so a title of three short lines still reads without breaking a word. */
    static let narrowest: CGFloat = 118
    static let gap: CGFloat = 6

    /* Whole columns only: as many as fit (at most seven), sharing the width exactly, so no heading is ever cut in half. */
    static func columns(in width: CGFloat) -> Int {
        min(7, max(1, Int((width + gap) / (narrowest + gap))))
    }

    private var hint: String? {
        var parts: [String] = []
        if store.canChangePlan { parts.append("Drag a session to another day") }
        if visibleColumns < 7 { parts.append("swipe sideways for the other days") }
        guard !parts.isEmpty else { return nil }
        let line = parts.joined(separator: " \u{00B7} ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    private func board(_ days: [PlanDay], _ view: PlanView) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(days) { day in
                        column(day, view)
                            .containerRelativeFrame(.horizontal) { w, _ in
                                let n = CGFloat(Self.columns(in: w))
                                return (w - Self.gap * (n - 1)) / n
                            }
                            .id(day.dayKey)
                    }
                }
                // Every column as tall as the tallest, so the "+ Add" lines sit in one row.
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            // A sideways swipe stops on a whole column.
            .scrollTargetBehavior(.viewAligned)
            // Counted only once the board has its width (a first pass at zero width would say one column).
            .onGeometryChange(for: Int.self) { $0.size.width > 50 ? Self.columns(in: $0.size.width) : 0 } action: { n in
                guard n > 0 else { return }
                visibleColumns = n
                showToday(days, proxy)
            }
            .onChange(of: monday) { showToday(days, proxy) }
        }
    }

    /* When only some days fit, the board starts where today can be seen. */
    private func showToday(_ days: [PlanDay], _ proxy: ScrollViewProxy) {
        guard let first = days.first, let last = days.last else { return }
        if let i = days.firstIndex(where: \.isToday), i >= visibleColumns {
            proxy.scrollTo(last.dayKey, anchor: .trailing)
        } else {
            proxy.scrollTo(first.dayKey, anchor: .leading)
        }
    }

    // MARK: head

    static func headline(_ book: PlanBook?, _ monday: String) -> String {
        guard let week = book?.week(on: monday) else {
            return Dates.short(monday) + " \u{2013} " + Dates.short(PlanView.addDays(monday, 6))
        }
        var parts = ["Week \(week.number)"]
        if !week.phase.isEmpty { parts.append(SeasonData.shortName(week.phase)) }
        if week.isTest { parts.append("Test week") }
        else if week.isEasy { parts.append("Easy week") }
        else if !week.tag.isEmpty { parts.append(week.tag.capitalized) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func head(_ days: [PlanDay], _ view: PlanView) -> some View {
        let planned = days.reduce(0) { $0 + $1.plannedSeconds }
        let done = days.flatMap(\.training).filter { $0.state == .done }
            .reduce(0.0) { $0 + (Stats.actualSeconds($1, view.mapping) ?? Plan.plannedSeconds($1, view.mapping) ?? 0) }
        let title = Text(Self.headline(store.book, monday))
            .font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            .accessibilityIdentifier("week-title")
        let figure = Text(done > 0 ? "\(formatDuration(done)) done of \(formatDuration(planned))" : "\(formatDuration(planned)) planned")
            .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.secondary)
            .lineLimit(1)
        // One line when it fits; else the buttons move to a line of their own; the title is never cut.
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                title.lineLimit(1).fixedSize()
                figure.fixedSize()
                Spacer(minLength: 8)
                HStack(spacing: 6) { buttons }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    title.lineLimit(1).fixedSize()
                    figure.fixedSize()
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) { buttons }
            }
            VStack(alignment: .leading, spacing: 4) {
                title.fixedSize(horizontal: false, vertical: true)
                figure
                HStack(spacing: 6) { buttons }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        StepButton(words: "Previous week", id: "week-prev") { weekStart = PlanView.addDays(monday, -7) }
        StepButton(words: "This week", id: "week-this") { weekStart = PlanView.weekStart(store.today) }
        StepButton(words: "Next week", id: "week-next") { weekStart = PlanView.addDays(monday, 7) }
    }

    // MARK: a day

    private func column(_ day: PlanDay, _ view: PlanView) -> some View {
        let sessions = shown(day)
        return DayColumn(day: day, sessions: sessions, mapping: view.mapping,
                         canChange: store.canChangePlan, height: columnHeight,
                         add: { addingOn = DayKey(id: day.dayKey) },
                         openExtra: { openExtra = $0 },
                         drop: { key in drop(key, on: day.dayKey) })
    }

    /* A rest row says "nothing today"; it is not shown on a day that has a session moved onto it. */
    private func shown(_ day: PlanDay) -> [Workout] {
        day.isRest || day.training.isEmpty ? day.sessions : day.training
    }

    // MARK: moving

    private func drop(_ key: String, on dayKey: String) -> Bool {
        guard let m = MovedLine.move(store, key, to: dayKey) else { return false }
        moved = m
        return true
    }
}

/* Small, green, outlined, with words: moving between weeks or months changes nothing in the plan. */
struct StepButton: View {
    let words: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(words)
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.today)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(Theme.today, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/* What a drag just moved, with a way to undo it, for eight seconds; the same line under the board and the month. */
struct MovedLine: View {
    @EnvironmentObject var store: Store
    @Binding var moved: Moved?

    struct Moved: Equatable {
        let changeID: String
        let text: String
        /* The rule book's calm grey line about this move, as on the Move page; nil when it has nothing to say. */
        var note: String? = nil
    }

    /*
     * A session still to do, dropped on another day: the same change the Change page makes, with only the day new.
     * The grey line is worked out from the plan before the move and never stops it.
     */
    @MainActor static func move(_ store: Store, _ key: String, to dayKey: String) -> Moved? {
        guard store.canChangePlan, let w = store.workout(key), w.state == .todo,
              w.discipline.id != "rest", w.dayKey != dayKey else { return nil }
        let note = SuggestionKeeper.shared.note(forMoving: key, to: dayKey)
        guard let change = store.moveSession(key, to: dayKey) else { return nil }
        let title = change.title.isEmpty ? w.title : change.title
        return Moved(changeID: change.id, text: "\(title) moved to \(Dates.short(dayKey))", note: note)
    }

    var body: some View {
        if let m = moved {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.text).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .accessibilityIdentifier("week-moved")
                    if let note = m.note {
                        Text(note).font(.footnote).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("week-moved-note")
                    }
                }
                if store.canUndo(m.changeID) {
                    Button("Undo") {
                        store.undoChange(m.changeID)
                        moved = nil
                    }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("week-undo")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            .task(id: m.changeID) {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if moved?.changeID == m.changeID { moved = nil }
            }
        }
    }
}

/* One day's column: its heading, its cards, its extras under a hairline, and "+ Add" at the foot. */
struct DayColumn: View {
    let day: PlanDay
    let sessions: [Workout]
    let mapping: Mapping
    let canChange: Bool
    let height: CGFloat
    let add: () -> Void
    let openExtra: (ExtraSummary) -> Void
    let drop: (String) -> Bool

    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(Dates.weekday.string(from: day.date).prefix(3)) + " " + String(utc.component(.day, from: day.date)))
                .font(.footnote.weight(day.isToday ? .heavy : .semibold))
                .foregroundStyle(day.isToday ? Theme.today : Theme.secondary)
            ForEach(sessions) { w in
                BoardCard(workout: w, mapping: mapping, movable: canChange)
            }
            if !day.extras.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 0.5).padding(.vertical, 2)
                ForEach(day.extras) { x in
                    Button { openExtra(x) } label: { BoardExtra(extra: x) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("week-extra-\(x.id)")
                }
            }
            Spacer(minLength: 6)
            if canChange {
                Button("+ Add", action: add)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.plan)
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .accessibilityIdentifier("week-add-\(day.dayKey)")
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(day.isToday ? Theme.todayColumn : Theme.dayColumn))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.plan, lineWidth: targeted ? 2 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first else { return false }
            return drop(key)
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week-day-\(day.dayKey)")
    }
}

/* A session on the board: its sport's colour as the left edge, the title (two lines), its length, and the done tick or missed mark the app uses everywhere. */
struct BoardCard: View {
    let workout: Workout
    let mapping: Mapping
    let movable: Bool

    private var state: SessionState { workout.state }
    private var lifts: Bool { movable && state == .todo && workout.discipline.id != "rest" }

    var body: some View {
        let card = NavigationLink(value: workout.key) { face }
            .buttonStyle(.plain)
            .accessibilityIdentifier("week-card-\(workout.key)")
        if lifts {
            card.draggable(workout.key)
        } else {
            card
        }
    }

    private var minutes: String? {
        guard let s = Plan.plannedSeconds(workout, mapping), s > 0 else { return nil }
        return formatDuration((s / 60).rounded() * 60)
    }

    /*
     * The title as the board shows it: the words before a dash, a bracket or a
     * slash (the session page has the rest), a title in capitals in ordinary
     * letters, and the part after a colon only when the part before it is too
     * short to say what the session is.
     */
    static func boardTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for cut in [" \u{2014} ", " \u{2013} ", " - ", " / ", " (", "; "] {
            if let r = t.range(of: cut), t.distance(from: t.startIndex, to: r.lowerBound) >= 3 {
                t = String(t[..<r.lowerBound])
            }
        }
        if let r = t.range(of: ": ") {
            let before = String(t[..<r.lowerBound])
            if before.count >= 6 { t = before }
        }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.count > 3, t == t.uppercased(), t != t.lowercased() {
            let low = t.lowercased()
            t = low.prefix(1).uppercased() + low.dropFirst()
        }
        return t.isEmpty ? raw : t
    }

    private var face: some View {
        let sport = Theme.sport(workout.discipline.id)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 1) {
            Text(Self.boardTitle(workout.title))
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                .lineLimit(4).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            // Its length on the left, the done tick on the same line at the right.
            HStack(alignment: .center, spacing: 4) {
                if let minutes {
                    Text(minutes).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                if state == .missed {
                    Text("Missed").font(.caption2.weight(.semibold)).foregroundStyle(Theme.danger).lineLimit(1)
                }
                Spacer(minLength: 0)
                if state == .done {
                    ZStack {
                        Circle().fill(Theme.today)
                        Glyph(name: "icon-check", size: 9).foregroundStyle(Color.white)
                    }
                    .frame(width: 15, height: 15)
                    .accessibilityLabel("Done")
                }
            }
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        // The sport's colour as the left edge; hatched, as everywhere, once the session is marked missed.
        .overlay(alignment: .leading) {
            Group {
                if state == .missed {
                    Rectangle().fill(Color.clear).overlay(Hatch().stroke(sport, lineWidth: 1.4))
                } else {
                    Rectangle().fill(sport)
                }
            }
            .frame(width: 4)
            .clipped()
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(state == .missed ? Theme.danger.opacity(0.7) : Theme.border, lineWidth: state == .missed ? 1.5 : 0.5))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([workout.title, minutes ?? "", state == .done ? "Done" : (state == .missed ? "Missed" : "")]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/* An extra below the hairline: dotted outline in its own colour, the paler tick extras carry everywhere. */
struct BoardExtra: View {
    let extra: ExtraSummary

    var body: some View {
        let activity = Extras.activity(extra.activity)
        let colour = Theme.sport(activity.colorId)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(extra.what.isEmpty ? extra.label : extra.what)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = extra.minutes {
                    Text(formatDuration(m * 60)).font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Theme.today.opacity(0.6))
                Glyph(name: "icon-check", size: 10).foregroundStyle(Color.white)
            }
            .frame(width: 17, height: 17)
            .accessibilityLabel("Done")
        }
        .padding(6)
        .background(shape.fill(colour.opacity(0.16)))
        .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])).foregroundStyle(colour))
        .contentShape(shape)
    }
}
