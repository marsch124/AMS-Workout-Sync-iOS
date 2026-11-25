import SwiftUI
import WorkoutCore

/*
 * His numbers beside the Plan page's view: time by sport in what is shown
 * (this week, this month or the season), the load of the last twelve weeks,
 * how much of the plan was followed so far, and the weeks to the race. Each
 * figure sits beside its name; no judgement words.
 */
struct PlanNumbers: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var diary = Diary.shared
    let from: String
    let to: String
    /* "This week", "November 2026", "The season". */
    let scope: String
    /* One column beside the view; two when they stand under it. */
    var columns = 1

    var body: some View {
        if let view = store.view {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns),
                      alignment: .leading, spacing: 8) {
                bySport(view)
                load(view)
                followed(view)
                race(view)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan-numbers")
        }
    }

    private func card<Content: View>(_ title: String, note: String = "", id: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.progress)
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: by sport

    private func bySport(_ view: PlanView) -> some View {
        let sports = PlanOverview.bySport(view.plan, view.mapping, from: from, to: to)
        let most = max(sports.map(\.hours.planned).max() ?? 0, 1)
        return card("By sport", note: scope, id: "plan-by-sport") {
            if sports.isEmpty {
                Text("Nothing planned").font(.footnote).foregroundStyle(Theme.secondary)
            }
            ForEach(sports) { s in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(s.label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(s.hours.done > 0 ? "\(formatDuration(s.hours.done)) of \(formatDuration(s.hours.planned))"
                                              : formatDuration(s.hours.planned))
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                    }
                    // Planned as the pale bar, done as the solid part, as the week strip draws them.
                    GeometryReader { geo in
                        let colour = Theme.sport(s.sport)
                        let planned = geo.size.width * s.hours.planned / most
                        ZStack(alignment: .leading) {
                            Capsule().fill(colour.opacity(0.3)).frame(width: max(4, planned))
                            Capsule().fill(colour).frame(width: min(planned, max(0, planned * s.hours.done / max(s.hours.planned, 1))))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    // MARK: load

    private func load(_ view: PlanView) -> some View {
        let plan = store.displayed
        let extras = store.allExtras
        let outside = Load.outside(diary.found, recorded: Load.recorded(plan, extras: extras, mapping: view.mapping))
        let items = Load.items(plan, extras: extras, mapping: view.mapping, outside: outside, answers: diary.answers)
        let starts = Stats.recentWeekStarts(12, today: store.today)
        let weeks = Load.weeks(items, starts: starts)
        let usual = Load.usual(weeks, firstDay: items.map(\.dayKey).min())
        let tallest = max(weeks.map(\.total).max() ?? 0, 1)
        let now = weeks.last?.total ?? 0
        return card("Load, last 12 weeks", id: "plan-load") {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.progress.opacity(i == weeks.count - 1 ? 1 : 0.55))
                        .frame(height: max(2, 44 * w.total / tallest))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44, alignment: .bottom)
            Text("This week \(Int(now.rounded()))" + (usual.map { " \u{00B7} usual \(Int($0.rounded()))" } ?? ""))
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: plan followed

    private func followed(_ view: PlanView) -> some View {
        let f = PlanOverview.followed(view.plan, from: from, to: to, today: store.today)
        return card("Plan followed", note: scope, id: "plan-followed") {
            if let percent = f.percent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(f.done) of \(f.due) sessions").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("\(percent) %").font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
                }
            } else {
                Text("Nothing due yet").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    // MARK: to the race

    @ViewBuilder
    private func race(_ view: PlanView) -> some View {
        if let road = Stats.road(view.visible, today: store.today, mapping: view.mapping), road.isRace,
           let weeks = PlanOverview.weeksTo(road.raceDay, today: store.today) {
            card("To the race", id: "plan-race") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(weeks) week\(weeks == 1 ? "" : "s")").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(raceDate(road.raceDay)).font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func raceDate(_ day: String) -> String {
        var words = Dates.short(day)
        if let d = parseDayKey(day) { words += " " + String(utc.component(.year, from: d)) }
        return words
    }
}
