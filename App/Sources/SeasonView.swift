import SwiftUI
import WorkoutCore

/*
 * The season of the wide look: every plan week up to the race as a bar. The
 * height is the week's planned hours, the colour its phase; an easy week is
 * pale and says "Easy" where there is room, a test week says "Test". A clear
 * outline marks the chosen week, a line marks today, and the race's flag stands
 * at the right with its name and date. Tap a bar to choose that week.
 */

/* The plan's weeks as the season draws them, worked out once for the bars and the phase rows. */
struct SeasonData {
    struct Week: Identifiable {
        var id: Int { number }
        let number: Int
        let monday: String
        let phase: String
        let phaseIndex: Int
        let seconds: Double
        let isEasy: Bool
        let isTest: Bool
    }
    struct Phase: Identifiable {
        var id: Int { index }
        let index: Int
        let name: String
        let first: String
        let last: String
        let weeks: Int
        let seconds: Double
    }

    let weeks: [Week]
    let phases: [Phase]
    let raceTitle: String
    let raceDay: String?

    @MainActor static func make(_ store: Store) -> SeasonData? {
        guard let view = store.view else { return nil }
        // Planned time per week, from the sessions as they are now (moves included).
        var seconds: [String: Double] = [:]
        for w in view.plan where w.discipline.id != "rest" {
            seconds[PlanView.weekStart(w.dayKey), default: 0] += Plan.plannedSeconds(w, view.mapping) ?? 0
        }
        // The book's own weeks; a plan read from Excel has none, so they are made from the sessions.
        var planWeeks = store.book?.weeks ?? []
        if planWeeks.isEmpty {
            let mondays = Set(view.plan.map { PlanView.weekStart($0.dayKey) }).sorted()
            planWeeks = mondays.enumerated().map { i, monday in
                let phase = view.plan.first { PlanView.weekStart($0.dayKey) == monday && !$0.phase.isEmpty }?.phase ?? ""
                return PlanWeek(number: i + 1, monday: monday, phase: phase, tag: "")
            }
        }
        planWeeks.sort { $0.monday < $1.monday }

        let road = Stats.road(view.visible, today: store.today, mapping: view.mapping)
        let raceDay = road?.isRace == true ? road?.raceDay : nil
        if let raceDay { planWeeks = planWeeks.filter { $0.monday <= raceDay } }
        guard !planWeeks.isEmpty else { return nil }

        var weeks: [Week] = []
        var phases: [Phase] = []
        for pw in planWeeks {
            let name = pw.phase.trimmingCharacters(in: .whitespaces)
            if let last = phases.last, last.name == name {
                phases[phases.count - 1] = Phase(index: last.index, name: name, first: last.first,
                                                 last: PlanView.addDays(pw.monday, 6), weeks: last.weeks + 1,
                                                 seconds: last.seconds + (seconds[pw.monday] ?? 0))
            } else {
                phases.append(Phase(index: phases.count, name: name, first: pw.monday,
                                    last: PlanView.addDays(pw.monday, 6), weeks: 1, seconds: seconds[pw.monday] ?? 0))
            }
            weeks.append(Week(number: pw.number, monday: pw.monday, phase: name, phaseIndex: phases.count - 1,
                              seconds: seconds[pw.monday] ?? 0, isEasy: pw.isEasy, isTest: pw.isTest))
        }
        return SeasonData(weeks: weeks, phases: phases,
                          raceTitle: road?.raceTitle ?? "", raceDay: raceDay)
    }
}

struct SeasonView: View {
    @EnvironmentObject var store: Store
    @Binding var weekStart: String

    private let barArea: CGFloat = 104

    var body: some View {
        if let data = SeasonData.make(store) {
            let chosen = weekStart.isEmpty ? PlanView.weekStart(store.today) : weekStart
            VStack(alignment: .leading, spacing: 4) {
                if let raceDay = data.raceDay { raceFlag(data, raceDay) }
                bars(data, chosen: chosen)
                    .frame(height: barArea)
                names(data)
                    .frame(height: 16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("season-view")
        }
    }

    // MARK: the race

    private func raceFlag(_ data: SeasonData, _ raceDay: String) -> some View {
        var words = Dates.short(raceDay)
        if let d = parseDayKey(raceDay) { words += " " + String(utc.component(.year, from: d)) }
        return HStack(spacing: 5) {
            Spacer(minLength: 0)
            Glyph(name: "icon-race", size: 16).foregroundStyle(Theme.season)
            Text((data.raceTitle.isEmpty ? "Race" : data.raceTitle) + " \u{00B7} " + words)
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.season)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("season-race")
    }

    // MARK: the bars

    private func bars(_ data: SeasonData, chosen: String) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let count = CGFloat(data.weeks.count)
            let barW = max(3, (geo.size.width - gap * (count - 1)) / count)
            let tallest = max(data.weeks.map(\.seconds).max() ?? 0, 1)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(data.weeks) { w in
                        bar(w, data: data, width: barW, tallest: tallest, chosen: w.monday == chosen)
                    }
                }
                if let x = todayX(data, barW: barW, gap: gap) {
                    Rectangle().fill(Theme.text).frame(width: 2, height: barArea)
                        .offset(x: x - 1)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("Today")
                        .accessibilityIdentifier("season-today")
                }
            }
        }
    }

    private func bar(_ w: SeasonData.Week, data: SeasonData, width: CGFloat, tallest: Double, chosen: Bool) -> some View {
        let colour = Theme.phase(w.phaseIndex, of: max(data.phases.count, 2))
        let height = max(4, (barArea - 16) * w.seconds / tallest)
        let word = w.isTest ? "Test" : (w.isEasy ? "Easy" : nil)
        return Button { weekStart = w.monday } label: {
            VStack(spacing: 1) {
                Spacer(minLength: 0)
                if let word, width >= 26 {
                    Text(word).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                }
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colour.opacity(w.isEasy ? 0.38 : 1))
                    .frame(height: height)
                    .overlay {
                        if chosen {
                            RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.text, lineWidth: 2)
                        }
                    }
            }
            .frame(width: width, height: barArea)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(w.number), \(w.phase)\(w.isEasy ? ", easy week" : "")\(w.isTest ? ", test week" : ""), \(formatDuration(w.seconds)) planned")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("season-week-\(w.number)")
    }

    /* The line stands in the week that holds today, at the day's place inside it. */
    private func todayX(_ data: SeasonData, barW: CGFloat, gap: CGFloat) -> CGFloat? {
        let today = store.today
        guard let i = data.weeks.firstIndex(where: { today >= $0.monday && today <= PlanView.addDays($0.monday, 6) }) else { return nil }
        let into = CGFloat(Stats.daysBetween(data.weeks[i].monday, today)) / 7
        return CGFloat(i) * (barW + gap) + barW * into
    }

    // MARK: the names under their weeks

    private func names(_ data: SeasonData) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let count = CGFloat(data.weeks.count)
            let barW = max(3, (geo.size.width - gap * (count - 1)) / count)
            ZStack(alignment: .topLeading) {
                let placed = placements(data, barW: barW, gap: gap)
                ForEach(placed, id: \.phase.index) { item in
                    Text(item.phase.name)
                        .font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                        .offset(x: item.x)
                }
            }
        }
    }

    /* A name is shown where it has room; one that would run into the name before it is left out (the rows below say it). */
    private func placements(_ data: SeasonData, barW: CGFloat, gap: CGFloat) -> [(phase: SeasonData.Phase, x: CGFloat)] {
        var out: [(phase: SeasonData.Phase, x: CGFloat)] = []
        var firstWeek = 0
        var edge: CGFloat = -.infinity
        for phase in data.phases {
            let x = CGFloat(firstWeek) * (barW + gap)
            let width = CGFloat(phase.name.count) * 5.6
            if !phase.name.isEmpty, x >= edge + 4 {
                out.append((phase, x))
                edge = x + width
            }
            firstWeek += phase.weeks
        }
        return out
    }
}

/* The phases as compact rows under the board: name, dates, weeks, hours, each figure beside its name. */
struct SeasonPhases: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let data = SeasonData.make(store) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phases").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                ForEach(data.phases.filter { !$0.name.isEmpty }) { phase in
                    let now = store.today >= phase.first && store.today <= phase.last
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.phase(phase.index, of: max(data.phases.count, 2)))
                            .frame(width: 14, height: 10)
                        Text(phase.name)
                            .font(.subheadline.weight(now ? .bold : .semibold)).foregroundStyle(Theme.text)
                            .frame(width: 110, alignment: .leading).lineLimit(1)
                        Text(Dates.short(phase.first) + " \u{2013} " + Dates.short(phase.last))
                            .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
                        Text("\(phase.weeks) week\(phase.weeks == 1 ? "" : "s")")
                            .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
                        Text(formatDuration(phase.seconds))
                            .font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("season-phase-\(phase.index)")
                }
            }
            .padding(.top, 4)
        }
    }
}
