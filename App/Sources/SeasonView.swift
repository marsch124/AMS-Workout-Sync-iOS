import SwiftUI
import WorkoutCore

/*
 * The season of the wide look: every plan week up to the race as a bar. The
 * height is the week's planned hours, the colour its phase, always in full:
 * an easy week carries the letter E above its bar and a test week T (the
 * words Easy and Test where a bar is wide enough). Pale is not used here: it
 * means "still to do" elsewhere. A clear
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

    /* A phase's own name, before its dash or colon: "Base 2 \u{2014} Aerobic Development" is "Base 2". */
    static func shortName(_ phase: String) -> String {
        var t = phase.trimmingCharacters(in: .whitespaces)
        for cut in [" \u{2014} ", " \u{2013} ", " - ", ": ", " ("] {
            if let r = t.range(of: cut), t.distance(from: t.startIndex, to: r.lowerBound) >= 2 {
                t = String(t[..<r.lowerBound])
            }
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? phase : t
    }

    /* The race's own short name from its session title, when it has one of a few words; else nil and the flag says "Race". */
    static func raceName(_ title: String) -> String? {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("race") {
            t = String(t.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: " :\u{2014}\u{2013}-\u{00B7}"))
        }
        for cut in [",", ":", " \u{2014} ", " \u{2013} ", " - ", " (", " / "] {
            if let r = t.range(of: cut) { t = String(t[..<r.lowerBound]) }
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.count >= 2 && t.count <= 24 ? t : nil
    }

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
    /* The Mondays outlined as chosen: nil is the week shown; empty outlines nothing (the Year view). */
    var chosenWeeks: [String]? = nil
    /* What a tap on a bar does; nil chooses that week. */
    var pick: ((String) -> Void)? = nil

    private let barArea: CGFloat = 104
    /* From this bar width the whole words Easy and Test fit; below it the letters E and T stand in. */
    private static let wordWidth: CGFloat = 26
    /* The room a letter or word takes above its bar. */
    private static let markHeight: CGFloat = 12
    @State private var lettersShown = true
    private let gap: CGFloat = 2

    var body: some View {
        if let data = SeasonData.make(store) {
            let chosen = Set(chosenWeeks ?? [weekStart.isEmpty ? PlanView.weekStart(store.today) : weekStart])
            VStack(alignment: .leading, spacing: 3) {
                if let raceDay = data.raceDay { raceFlag(data, raceDay) }
                bars(data, chosen: chosen)
                    .frame(height: barArea)
                names(data)
                key(data)
                    .padding(.top, 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("season-view")
        }
    }

    // MARK: the race

    private func raceFlag(_ data: SeasonData, _ raceDay: String) -> some View {
        var date = Dates.short(raceDay)
        if let d = parseDayKey(raceDay) { date += " " + String(utc.component(.year, from: d)) }
        let name = SeasonData.raceName(data.raceTitle) ?? "Race"
        return HStack(spacing: 4) {
            Spacer(minLength: 0)
            Glyph(name: "icon-race", size: 14).foregroundStyle(Theme.season)
            Text(name + " \u{00B7} " + date)
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.season)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("season-race")
    }

    // MARK: the bars

    private func barWidth(_ width: CGFloat, _ count: Int) -> CGFloat {
        max(3, (width - gap * CGFloat(count - 1)) / CGFloat(count))
    }

    private func barHeight(_ w: SeasonData.Week, tallest: Double) -> CGFloat {
        max(4, (barArea - 16) * w.seconds / tallest)
    }

    private func bars(_ data: SeasonData, chosen: Set<String>) -> some View {
        GeometryReader { geo in
            let barW = barWidth(geo.size.width, data.weeks.count)
            let tallest = max(data.weeks.map(\.seconds).max() ?? 0, 1)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(data.weeks) { w in
                        bar(w, data: data, width: barW, tallest: tallest, chosen: chosen.contains(w.monday))
                    }
                }
                outline(data, chosen: chosen, barW: barW, tallest: tallest)
                if let x = todayX(data, barW: barW) {
                    todayMark(x: x, width: geo.size.width)
                }
            }
            .onAppear { lettersShown = barW < Self.wordWidth }
            .onChange(of: barW < Self.wordWidth) { _, narrow in lettersShown = narrow }
        }
    }

    /* The chosen week (or the weeks of the chosen month): one clear outline standing just outside their bars. */
    @ViewBuilder
    private func outline(_ data: SeasonData, chosen: Set<String>, barW: CGFloat, tallest: Double) -> some View {
        let picked = data.weeks.indices.filter { chosen.contains(data.weeks[$0].monday) }
        if let first = picked.first, let last = picked.last {
            // The outline goes round a week's letter too.
            let top = picked.map { i -> CGFloat in
                let w = data.weeks[i]
                return barHeight(w, tallest: tallest) + (w.isEasy || w.isTest ? Self.markHeight : 0)
            }.max() ?? 4
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.text, lineWidth: 2)
                .frame(width: CGFloat(last - first + 1) * (barW + gap) - gap + 6, height: top + 6)
                .offset(x: CGFloat(first) * (barW + gap) - 3, y: barArea - top - 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /* Today: a thin green line through the bars, its word once at the top. */
    private func todayMark(x: CGFloat, width: CGFloat) -> some View {
        let wordLeft = x + 50 > width
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.today).frame(width: 1.5, height: barArea - 2)
                .offset(x: x - 0.75, y: 2)
            Text("Today")
                .font(.caption2.weight(.semibold)).foregroundStyle(Theme.today)
                .fixedSize()
                .frame(width: 44, alignment: wordLeft ? .trailing : .leading)
                .offset(x: wordLeft ? x - 47 : x + 3, y: -1)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today")
        .accessibilityIdentifier("season-today")
    }

    private func bar(_ w: SeasonData.Week, data: SeasonData, width: CGFloat, tallest: Double, chosen: Bool) -> some View {
        let colour = Theme.phase(w.phaseIndex, of: max(data.phases.count, 2))
        let height = barHeight(w, tallest: tallest)
        let word = w.isTest ? "Test" : (w.isEasy ? "Easy" : nil)
        let letter = PlanOverview.weekLetter(isEasy: w.isEasy, isTest: w.isTest)
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return Button { if let pick { pick(w.monday) } else { weekStart = w.monday } } label: {
            VStack(spacing: 1) {
                Spacer(minLength: 0)
                if let word, let letter {
                    Text(width >= Self.wordWidth ? word : letter)
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                        .frame(height: Self.markHeight - 1)
                }
                shape
                    .fill(colour)
                    .frame(height: height)
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
    private func todayX(_ data: SeasonData, barW: CGFloat) -> CGFloat? {
        let today = store.today
        guard let i = data.weeks.firstIndex(where: { today >= $0.monday && today <= PlanView.addDays($0.monday, 6) }) else { return nil }
        let into = (CGFloat(Stats.daysBetween(data.weeks[i].monday, today)) + 0.5) / 7
        return CGFloat(i) * (barW + gap) + barW * into
    }

    // MARK: the names under their weeks

    /* Each phase's short name in its colour, centred under its weeks; names pushed apart only as far as they must be. */
    private func names(_ data: SeasonData) -> some View {
        let shown = data.phases.filter { !$0.name.isEmpty }
        var firstWeek: [Int: Int] = [:]
        var at = 0
        for p in data.phases { firstWeek[p.index] = at; at += p.weeks }
        let spans = shown.map { (first: firstWeek[$0.index] ?? 0, weeks: $0.weeks) }
        return PhaseNameRow(spans: spans, weekCount: data.weeks.count, gap: gap) {
            ForEach(shown) { phase in
                Text(SeasonData.shortName(phase.name))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.phase(phase.index, of: max(data.phases.count, 2)))
                    .lineLimit(1).fixedSize()
            }
        }
        .accessibilityHidden(true)
    }

    /* What the letters mean and what a tap does, said on the screen itself. */
    private func key(_ data: SeasonData) -> some View {
        return Text(PlanOverview.seasonKey(hasEasy: data.weeks.contains(where: \.isEasy),
                                           hasTest: data.weeks.contains(where: \.isTest), lettersShown: lettersShown))
            .font(.caption2).foregroundStyle(Theme.secondary)
            .accessibilityIdentifier("season-key")
    }
}

/*
 * Lays the phase names in one row: each centred under its weeks, kept inside
 * the row, and pushed sideways just enough that no two touch.
 */
struct PhaseNameRow: Layout {
    let spans: [(first: Int, weeks: Int)]
    let weekCount: Int
    let gap: CGFloat
    private let space: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 300, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = min(spans.count, subviews.count)
        guard n > 0, weekCount > 0 else { return }
        let step = (bounds.width + gap) / CGFloat(weekCount)
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        var left: [CGFloat] = (0..<n).map { i in
            let centre = (CGFloat(spans[i].first) + CGFloat(spans[i].weeks) / 2) * step - gap / 2
            return min(max(0, centre - widths[i] / 2), max(0, bounds.width - widths[i]))
        }
        for i in 1..<max(n, 1) where i < n {
            left[i] = max(left[i], left[i - 1] + widths[i - 1] + space)
        }
        if n > 0 { left[n - 1] = min(left[n - 1], bounds.width - widths[n - 1]) }
        for i in stride(from: n - 2, through: 0, by: -1) {
            left[i] = min(left[i], left[i + 1] - widths[i] - space)
        }
        for i in 0..<subviews.count {
            if i < n {
                subviews[i].place(at: CGPoint(x: bounds.minX + max(0, left[i]), y: bounds.minY),
                                  anchor: .topLeading, proposal: .unspecified)
            } else {
                subviews[i].place(at: CGPoint(x: -10_000, y: bounds.minY), proposal: .zero)
            }
        }
    }
}

/* The phases as compact rows under the board: the name with room to be read, then dates, weeks and hours beside it. */
struct SeasonPhases: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let data = SeasonData.make(store) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phases").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(data.phases.filter { !$0.name.isEmpty }) { phase in
                        row(phase, data)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func row(_ phase: SeasonData.Phase, _ data: SeasonData) -> some View {
        let now = store.today >= phase.first && store.today <= phase.last
        let dates = Dates.short(phase.first) + " \u{2013} " + Dates.short(phase.last)
        let weeks = "\(phase.weeks) week\(phase.weeks == 1 ? "" : "s")"
        let hours = formatDuration(phase.seconds)
        return GridRow {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.phase(phase.index, of: max(data.phases.count, 2)))
                    .frame(width: 14, height: 10)
                Text(phase.name)
                    .font(.subheadline.weight(now ? .bold : .semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(phase.name), \(dates), \(weeks), \(hours)\(now ? ", now" : "")")
            .accessibilityIdentifier("season-phase-\(phase.index)")
            Text(dates).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1).accessibilityHidden(true)
            Text(weeks).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1).accessibilityHidden(true)
            Text(hours).font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary).lineLimit(1).accessibilityHidden(true)
        }
    }
}
