import SwiftUI
import WorkoutCore

/*
 * The Year view of the Plan page: every month of the plan, from its first
 * month to its last, as a compact block — the month's name with its planned
 * and done hours beside it, and a small calendar where each day is a square
 * in the colour of its main session's sport, filled the way the week strip
 * fills its bars: solid once recorded, pale while still to do, hatched when
 * missed; an empty square is a rest day. Race day is in the race's colour,
 * today is outlined. A tap on a month opens it in the Month view.
 */
struct YearView: View {
    @EnvironmentObject var store: Store
    let openMonth: (String) -> Void

    var body: some View {
        if let view = store.view {
            let byDay = Dictionary(grouping: view.visible, by: \.dayKey)
            let keys = view.plan.map(\.dayKey)
            let road = Stats.road(view.visible, today: store.today, mapping: view.mapping)
            let raceDay = road?.isRace == true ? road?.raceDay : nil
            let months = PlanOverview.months(from: keys.min() ?? store.today, to: keys.max() ?? store.today)
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 250), spacing: 10, alignment: .top)],
                          alignment: .leading, spacing: 10) {
                    ForEach(months, id: \.self) { m in
                        Button { openMonth(m) } label: {
                            block(m, view, byDay: byDay, raceDay: raceDay)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("year-month-\(m)")
                    }
                }
                key(hasRace: raceDay != nil)
                SeasonPhases(columns: 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("year-view")
        }
    }

    private func block(_ month: String, _ view: PlanView, byDay: [String: [Workout]], raceDay: String?) -> some View {
        let hours = PlanOverview.hours(view.plan, view.mapping, from: PlanOverview.firstDay(month), to: PlanOverview.lastDay(month))
        let isNow = month == PlanOverview.month(of: store.today)
        return VStack(alignment: .leading, spacing: 6) {
            let name = Text(MonthGrid.title(month))
                .font(.subheadline.weight(.bold)).foregroundStyle(isNow ? Theme.today : Theme.text)
                .lineLimit(1)
            let figure = Text(hours.done > 0 ? "\(formatDuration(hours.planned)) \u{00B7} \(formatDuration(hours.done)) done"
                                             : formatDuration(hours.planned))
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary)
                .lineLimit(1)
            // The hours always on the line under the name, in the same place on every month.
            VStack(alignment: .leading, spacing: 1) { name.minimumScaleFactor(0.8); figure.minimumScaleFactor(0.8) }
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                        Text(d).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                let rows = PlanOverview.grid(month)
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(row, id: \.self) { day in
                            square(day, inMonth: day.hasPrefix(month), sessions: byDay[day] ?? [],
                                   mapping: view.mapping, raceDay: raceDay)
                        }
                    }
                }
                // Every month as tall as one of six weeks, so the cards line up in an even grid.
                ForEach(rows.count..<6, id: \.self) { _ in
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { _ in
                            Color.clear.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MonthGrid.title(month)), \(formatDuration(hours.planned)) planned, \(formatDuration(hours.done)) done")
    }

    @ViewBuilder
    private func square(_ day: String, inMonth: Bool, sessions: [Workout], mapping: Mapping, raceDay: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        Group {
            if !inMonth {
                Color.clear
            } else if day == raceDay {
                shape.fill(Theme.sport("race"))
            } else if let main = PlanOverview.main(sessions, mapping) {
                yearFill(main.discipline.id, main.state)
            } else {
                shape.strokeBorder(Theme.border, lineWidth: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay {
            if inMonth && day == store.today {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Theme.today, lineWidth: 1.5)
                    .padding(-2)
            }
        }
    }

    /* As the week strip fills its bars; "still to do" in the night-raised tint (Theme.stillToDo), so sports read apart at night. */
    @ViewBuilder
    private func yearFill(_ sport: String, _ state: SessionState) -> some View {
        if state == .todo {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Theme.stillToDo(sport))
        } else {
            StateFill(sport: sport, state: state, corner: 2.5)
        }
    }

    /* The meanings in words, small and grey, with the same squares. */
    private func key(hasRace: Bool) -> some View {
        FlowRow(spacing: 12) {
            keyItem(StateFill(sport: "run", state: .done, corner: 2.5), "Recorded")
            keyItem(yearFill("run", .todo), "Still to do")
            keyItem(StateFill(sport: "run", state: .missed, corner: 2.5), "Missed")
            keyItem(RoundedRectangle(cornerRadius: 2.5).strokeBorder(Theme.border, lineWidth: 1), "Rest day")
            if hasRace { keyItem(RoundedRectangle(cornerRadius: 2.5).fill(Theme.sport("race")), "Race day") }
            keyItem(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.today, lineWidth: 1.5), "Today")
            Text("Colour = the day's main sport \u{00B7} Tap a month to open it")
                .font(.caption2).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("year-key")
    }

    private func keyItem<V: View>(_ mark: V, _ words: String) -> some View {
        HStack(spacing: 4) {
            mark.frame(width: 10, height: 10)
            Text(words).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
}
