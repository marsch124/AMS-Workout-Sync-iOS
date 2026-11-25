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

    @State private var moved: Moved?
    @State private var addingOn: DayKey?
    @State private var openExtra: ExtraSummary?

    struct Moved: Equatable {
        let changeID: String
        let text: String
    }
    struct DayKey: Identifiable { let id: String }

    private var monday: String { weekStart.isEmpty ? PlanView.weekStart(store.today) : weekStart }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let view = store.view {
                let days = view.week(of: monday, today: store.today)
                head(days, view)
                if store.canChangePlan {
                    Text("Drag a session to another day")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("week-hint")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(days) { day in
                            column(day, view)
                                // Seven to fill the width; never narrower than a card can be read.
                                .containerRelativeFrame(.horizontal) { w, _ in max(104, (w - 36) / 7) }
                        }
                    }
                }
                if let moved {
                    movedLine(moved)
                }
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

    // MARK: head

    private func headline(_ monday: String) -> String {
        guard let week = store.book?.week(on: monday) else {
            return Dates.short(monday) + " \u{2013} " + Dates.short(PlanView.addDays(monday, 6))
        }
        var parts = ["Week \(week.number)"]
        if !week.phase.isEmpty { parts.append(week.phase) }
        if week.isTest { parts.append("Test week") }
        else if week.isEasy { parts.append("Easy week") }
        else if !week.tag.isEmpty { parts.append(week.tag.capitalized) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func head(_ days: [PlanDay], _ view: PlanView) -> some View {
        let planned = days.reduce(0) { $0 + $1.plannedSeconds }
        let done = days.flatMap(\.training).filter { $0.state == .done }
            .reduce(0.0) { $0 + (Stats.actualSeconds($1, view.mapping) ?? Plan.plannedSeconds($1, view.mapping) ?? 0) }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(headline(monday))
                .font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                .lineLimit(2)
                .accessibilityIdentifier("week-title")
            Text(done > 0 ? "\(formatDuration(done)) done of \(formatDuration(planned))" : "\(formatDuration(planned)) planned")
                .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { buttons }
                HStack(spacing: 6) { buttons }.scaleEffect(0.9, anchor: .trailing)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        boardButton("Previous week", id: "week-prev") { weekStart = PlanView.addDays(monday, -7) }
        boardButton("This week", id: "week-this") { weekStart = PlanView.weekStart(store.today) }
        boardButton("Next week", id: "week-next") { weekStart = PlanView.addDays(monday, 7) }
    }

    /* Small, green, outlined: moving between weeks changes nothing in the plan. */
    private func boardButton(_ words: String, id: String, action: @escaping () -> Void) -> some View {
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
        guard store.canChangePlan, let w = store.workout(key), w.state == .todo,
              w.discipline.id != "rest", w.dayKey != dayKey,
              let change = store.moveSession(key, to: dayKey) else { return false }
        let title = change.title.isEmpty ? w.title : change.title
        moved = Moved(changeID: change.id, text: "\(title) moved to \(Dates.short(dayKey))")
        return true
    }

    private func movedLine(_ m: Moved) -> some View {
        HStack(spacing: 10) {
            Text(m.text).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                .lineLimit(2)
                .accessibilityIdentifier("week-moved")
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
            Spacer(minLength: 8)
            if canChange {
                Button("+ Add", action: add)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.plan)
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .accessibilityIdentifier("week-add-\(day.dayKey)")
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(day.isToday ? Theme.todayColumn : Theme.dayColumn))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.plan, lineWidth: targeted ? 2 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first else { return false }
            return drop(key)
        } isTargeted: { targeted = $0 }
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
        return s < 3600 ? "\(Int((s / 60).rounded())) min" : formatDuration(s)
    }

    private var face: some View {
        let sport = Theme.sport(workout.discipline.id)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(spacing: 0) {
            // The sport's colour; hatched, as everywhere, once the session is marked missed.
            Group {
                if state == .missed {
                    Rectangle().fill(Color.clear).overlay(Hatch().stroke(sport, lineWidth: 1.4))
                } else {
                    Rectangle().fill(sport)
                }
            }
            .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 4) {
                    Text(workout.title)
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if state == .done {
                        ZStack {
                            Circle().fill(Theme.today)
                            Glyph(name: "icon-check", size: 10).foregroundStyle(Color.white)
                        }
                        .frame(width: 17, height: 17)
                        .accessibilityLabel("Done")
                    }
                }
                if let minutes {
                    Text(minutes).font(.caption2).foregroundStyle(Theme.secondary)
                }
                if state == .missed {
                    Text("Missed").font(.caption2.weight(.semibold)).foregroundStyle(Theme.danger)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
        .clipShape(shape)
        .overlay(shape.strokeBorder(state == .missed ? Theme.danger.opacity(0.7) : Theme.border, lineWidth: state == .missed ? 1.5 : 0.5))
        .contentShape(shape)
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
                    .lineLimit(2).multilineTextAlignment(.leading)
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
