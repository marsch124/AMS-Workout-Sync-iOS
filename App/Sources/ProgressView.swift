import SwiftUI
import Charts
import WorkoutCore

/*
 * The Progress screen: the web app's, card for card — the road to the race,
 * is it working, twelve weeks, where the hours went, then what was kept.
 * Every figure comes from Stats, which tools/stats-parity.py checks against
 * the web app's AmsSync.stats() on the same workbooks.
 */
struct ProgressView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Progress").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 12)
                        .accessibilityIdentifier("progress-title")
                    if let p = store.progress, let mapping = store.mapping {
                        if let road = p.road { RoadCard(road: road, today: store.today) }
                        if !p.summary.any {
                            EmptyCard(title: "Nothing has happened yet",
                                      text: "Once sessions are behind you, this is where the patterns in them show up.")
                        } else {
                            TrendsCard(trends: p.trends)
                            WeeksCard(load: p.load, today: store.today)
                            MixCard(load: p.load)
                            if p.summary.counted < 12 {
                                Note(title: "Too early to read much into this.",
                                     text: "\(p.summary.counted) session\(p.summary.counted == 1 ? " has" : "s have") gone by. The figures below are real, but a fortnight of training is a fortnight — the patterns need more road behind them.")
                            }
                            SoFarCard(s: p.summary)
                            ConsistencyCard(s: p.summary)
                            SportCard(s: p.summary, mapping: mapping)
                            MovesCard(s: p.summary)
                        }
                        Text("Worked out from the sessions in your workbook each time this screen is opened. Nothing here is stored in the plan, and nothing here writes to it — the totals and the chart on your Progress sheet remain the ones Excel keeps.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    } else {
                        EmptyCard(title: "Nothing loaded", text: "Choose your plan in Settings and this fills itself in.")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - pieces

private func percent(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }

private func hoursShort(_ seconds: Double) -> String {
    if seconds < 60 { return "0" }
    let hours = Int(seconds / 3600)
    let minutes = Int(((seconds - Double(hours) * 3600) / 60).rounded())
    if hours == 0 { return "\(minutes)m" }
    return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
}

private func paceText(_ sport: String, _ kmh: Double) -> String {
    guard kmh > 0 else { return "—" }
    if sport == "bike" { return jsNumberString((kmh * 10).rounded() / 10) + " km/h" }
    let perKm = 3600 / kmh
    let per = sport == "swim" ? perKm / 10 : perKm
    var minutes = Int(per / 60)
    var seconds = Int((per - Double(minutes) * 60).rounded())
    if seconds == 60 { minutes += 1; seconds = 0 }
    return "\(minutes):" + String(format: "%02d", seconds) + (sport == "swim" ? " /100m" : " /km")
}

struct StatCard<Content: View>: View {
    let title: String
    var lede: String = ""
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Theme.text)
            if !lede.isEmpty { Text(lede).font(.subheadline).foregroundStyle(Theme.text) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

struct Figure: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
            Text(label).font(.caption).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Note: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Text(text).font(.footnote).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
    }
}

struct EmptyCard: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Text(text).font(.subheadline).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

// MARK: - the road to the race

struct RoadCard: View {
    let road: Stats.Road
    let today: String
    /* The race's own words are one tap away: a flag, not four lines of text. */
    @State private var raceOpen = false

    private var clock: (number: String, unit: String) {
        if road.daysToGo < 0 { return ("—", "the race has been") }
        if road.daysToGo == 0 { return ("Today", road.isRace ? "race day" : "the last day") }
        if road.daysToGo <= 21 { return (String(road.daysToGo), road.daysToGo == 1 ? "day to go" : "days to go") }
        return (String(road.weeksToGo), "weeks to go")
    }

    private func hours(_ s: Double) -> String { s >= 60 ? formatDuration(s) : "0m" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(clock.number).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.progress)
                    Text(clock.unit).font(.headline).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Button { withAnimation(.easeInOut(duration: 0.15)) { raceOpen.toggle() } } label: {
                    ZStack {
                        Circle().fill(Theme.progress.opacity(raceOpen ? 0.3 : 0.16))
                        Glyph(name: "icon-race", size: 20).foregroundStyle(Theme.progress)
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("race-what")
                .accessibilityLabel(raceOpen ? "Hide what the race is" : "What the race is")
            }
            if raceOpen {
                Text(road.raceTitle).font(.subheadline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("race-title")
            }
            Text(Dates.long(road.raceDay) + (parseDayKey(road.raceDay).map { " " + String(utc.component(.year, from: $0)) } ?? ""))
                .font(.subheadline).foregroundStyle(Theme.secondary)

            if !road.phases.isEmpty {
                let total = Double(max(1, Stats.daysBetween(road.start, road.raceDay)))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Each phase as wide as the days it covers: the plan's own shape.
                        HStack(spacing: 0) {
                            ForEach(Array(road.phases.enumerated()), id: \.element.id) { i, phase in
                                let width = Double(max(1, Stats.daysBetween(phase.from, phase.to) + 1)) / total
                                let isNow = today >= phase.from && today <= phase.to
                                let done = today > phase.to
                                Rectangle()
                                    .fill(Theme.progress.opacity(isNow ? 0.9 : (done ? 0.45 : 0.2 + Double(i % 4) * 0.06)))
                                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.surface).frame(width: 1.5) }
                                    .frame(width: geo.size.width * width)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        if road.started && road.through <= 1 {
                            Rectangle().fill(Theme.text).frame(width: 2, height: 22)
                                .offset(x: geo.size.width * road.through - 1)
                        }
                    }
                }
                .frame(height: 16)
                if let now = road.phases.first(where: { today >= $0.from && today <= $0.to }) {
                    Text("You are in ").font(.subheadline).foregroundStyle(Theme.secondary)
                    + Text(now.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                }
            }

            HStack(spacing: 8) {
                Figure(value: "\(road.done)", label: "done of \(road.sessions)")
                Figure(value: hours(road.doneSeconds), label: "banked of \(hours(road.plannedSoFar)) due")
                Figure(value: hours(road.plannedAll), label: "the whole build")
            }
            if road.behind > 0 {
                Text("\(road.behind) session\(road.behind == 1 ? "" : "s") behind you \(road.behind == 1 ? "was" : "were") never recorded.")
                    .font(.footnote).foregroundStyle(Theme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

// MARK: - is it working

struct TrendsCard: View {
    let trends: [Stats.Trend]
    private static let label = ["swim": "Swims", "bike": "Rides", "run": "Runs"]

    var body: some View {
        if trends.isEmpty { EmptyView() } else {
            let shown = trends.filter(\.enough)
            let waiting = trends.filter { !$0.enough }
            if shown.isEmpty, let nearest = waiting.max(by: { $0.have < $1.have }) {
                let soFar = nearest.have == 0 ? "there are none yet" : (nearest.have == 1 ? "there is one so far" : "there are \(nearest.have) so far")
                StatCard(title: "Is it working?",
                         lede: "Not enough logged yet to answer this honestly. It needs \(nearest.need) sessions of one sport carrying a distance, a time and an average heart rate — \(soFar).") { EmptyView() }
            } else {
                StatCard(title: "Is it working?",
                         lede: "How far you travel per heartbeat, then against now. Going faster at the same heart rate moves it; so does the same speed at a lower one. Both are fitness.") {
                    ForEach(shown) { t in
                        if let then = t.then, let now = t.now {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Self.label[t.sport] ?? t.sport).font(.subheadline.weight(.bold)).foregroundStyle(Theme.sportInk(t.sport))
                                HStack(spacing: 12) {
                                    half("then", paceText(t.sport, then.speed), then.hr)
                                    Text(t.verdict == "better" ? "↑" : (t.verdict == "down" ? "↓" : "→"))
                                        .font(.title.weight(.bold))
                                        .foregroundStyle(t.verdict == "better" ? Theme.today : (t.verdict == "down" ? Theme.danger : Theme.secondary))
                                    half("now", paceText(t.sport, now.speed), now.hr)
                                }
                                let change = Int((t.change * 100).rounded())
                                Text("\(change > 0 ? "+" : "")\(change)% · " + verdictText(t.verdict))
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                                Text("\(t.sessions) logged \(t.easyOnly ? "easy sessions" : "sessions of every kind"), the first \(then.sessions) against the last \(now.sessions).")
                                    .font(.caption).foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    let still = waiting.filter { $0.have > 0 }.map { (Self.label[$0.sport] ?? $0.sport).lowercased() + " (\($0.have) of \($0.need))" }
                    if !still.isEmpty {
                        Text("Not enough yet for " + still.joined(separator: ", ") + ".").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Text("Only sessions carrying a distance, a time and an average heart rate can be counted" +
                         (shown.contains(where: \.easyOnly) ? ", and easy ones are preferred where there are enough of them — steady work is where aerobic fitness shows" : "") +
                         ". Heart rate answers to heat, sleep, coffee and stress as well as to training, so this is worth reading over months rather than weeks.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func verdictText(_ v: String) -> String {
        switch v {
        case "better": return "Better — you are covering more ground for the same heartbeats."
        case "down": return "Down a little. Heat, fatigue, hills and a hard block all do this; one stretch is not a verdict."
        default: return "Holding steady."
        }
    }

    private func half(_ when: String, _ pace: String, _ hr: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(when).font(.caption).foregroundStyle(Theme.secondary)
            Text(pace).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
            Text("at \(Int(hr.rounded())) bpm").font(.caption).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - twelve weeks

struct WeeksCard: View {
    let load: Stats.Load
    let today: String

    var body: some View {
        let weeks = load.weeks.filter { $0.planned > 0 || $0.actual > 0 }
        if weeks.count < 3 { EmptyView() } else {
            let share = load.planned > 0 ? Int((load.actual / load.planned * 100).rounded()) : 0
            StatCard(title: "Twelve weeks",
                     lede: load.planned > 0 ? "\(hoursShort(load.actual)) of \(hoursShort(load.planned)) asked for over these twelve weeks — \(share)%." : "Nothing planned in these twelve weeks.") {
                Chart {
                    ForEach(load.weeks) { w in
                        BarMark(x: .value("Week", w.start), y: .value("Hours", w.actual / 3600))
                            .foregroundStyle(w.start == load.weeks.last?.start ? Theme.progress : Theme.progress.opacity(0.55))
                            .cornerRadius(3)
                        if w.planned > 0 {
                            RuleMark(xStart: .value("Week", w.start), xEnd: .value("Week", w.start), y: .value("Planned", w.planned / 3600))
                            RectangleMark(x: .value("Week", w.start), y: .value("Planned", w.planned / 3600), height: 2)
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: load.weeks.enumerated().filter { $0.offset % 3 == 0 || $0.offset == load.weeks.count - 1 }.map { $0.element.start }) { value in
                        AxisValueLabel {
                            if let s = value.as(String.self), let d = parseDayKey(s) {
                                Text(Dates.formatter("dMMM").string(from: d)).font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) { v in AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h))h").font(.caption2) } } } }
                .frame(height: 150)
                Text("Each column is a week: the hours you did, with a line across it where the plan asked you to reach. This week is still going, so its column is short by however much of it is left.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: - where the hours went

struct MixCard: View {
    let load: Stats.Load

    private func drift(_ s: Stats.SportLoad) -> Int { Int((s.shareActual * 100).rounded()) - Int((s.sharePlanned * 100).rounded()) }
    private func label(_ id: String) -> String { (Disciplines.five + Disciplines.compound).first { $0.id == id }?.label ?? id }

    var body: some View {
        let sports = load.sports.filter { $0.actual > 0 || $0.planned > 0 }
        if sports.count < 2 { EmptyView() } else {
            let drifted = sports.filter { abs(drift($0)) >= 5 }
            StatCard(title: "Where the hours went",
                     lede: "The same twelve weeks, by sport. Hours rather than sessions — a twenty-minute swim and a three-hour ride count as one apiece further down this screen, and nothing like each other here.") {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(sports.filter { $0.actual > 0 }) { s in
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.sport(s.sport))
                                .frame(width: max(2, geo.size.width * s.shareActual - 2))
                        }
                    }
                }
                .frame(height: 12)
                ForEach(sports) { s in
                    HStack(spacing: 8) {
                        Circle().fill(Theme.sport(s.sport)).frame(width: 10, height: 10)
                        Text(label(s.sport)).font(.subheadline).foregroundStyle(Theme.text)
                        Spacer()
                        Text(hoursShort(s.actual)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
                        Text("\(Int((s.shareActual * 100).rounded()))%").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text).frame(width: 44, alignment: .trailing)
                        if s.sharePlanned > 0 {
                            Text("plan \(Int((s.sharePlanned * 100).rounded()))%" + (abs(drift(s)) >= 5 ? " \(drift(s) > 0 ? "+" : "")\(drift(s))" : ""))
                                .font(.caption.monospacedDigit()).foregroundStyle(abs(drift(s)) >= 5 ? Theme.danger : Theme.secondary)
                                .frame(width: 82, alignment: .trailing)
                        }
                    }
                }
                Text(drifted.isEmpty
                     ? "The balance is within five points of what the plan asked for on every sport."
                     : drifted.map { label($0.sport) }.joined(separator: " and ") + (drifted.count == 1 ? " sits" : " sit") + " five points or more from the share the plan asked for. That is worth knowing rather than worth worrying about: a block often leans on purpose.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: - what was kept

struct SoFarCard: View {
    let s: Stats.Summary
    var body: some View {
        StatCard(title: "So far",
                 lede: "\(s.done) of \(s.counted) sessions behind you were completed" + (s.unlogged > 0 ? ", and \(s.unlogged) \(s.unlogged == 1 ? "was" : "were") never answered either way" : "") + ".") {
            HStack(spacing: 8) {
                Figure(value: "\(s.done)", label: "completed")
                Figure(value: "\(s.missed)", label: "missed")
                Figure(value: "\(s.unlogged)", label: "unanswered")
            }
            if s.unlogged > 0 {
                Text("An unanswered session counts against you here, because a plan you did not reply to is not a plan you kept. Log or dismiss them and this settles down.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct ConsistencyCard: View {
    let s: Stats.Summary
    var body: some View {
        let overall: Double? = s.answered > 0 ? Double(s.done) / Double(s.answered) : nil
        StatCard(title: "Consistency",
                 lede: s.streakCurrent > 0 ? "\(s.streakCurrent) in a row right now." : "The run ended at the last session. Longest so far is \(s.streakLongest).") {
            HStack(spacing: 8) {
                Figure(value: "\(s.streakCurrent)", label: "current run")
                Figure(value: "\(s.streakLongest)", label: "longest run")
                Figure(value: percent(overall), label: "of those answered")
            }
        }
    }
}

struct SportCard: View {
    let s: Stats.Summary
    let mapping: Mapping
    var body: some View {
        let worst = s.worst
        let lead: String = {
            if let w = worst, w.planned >= 3, let rate = w.rate, s.sports.count > 1, rate < 0.999 {
                return "\(w.label) is furthest behind, at \(percent(rate)) of its sessions kept."
            }
            return "Nothing is being dropped more than anything else."
        }()
        StatCard(title: "Which sport runs behind", lede: lead) {
            ForEach(s.sports) { row in
                HStack(spacing: 8) {
                    Circle().fill(Theme.sport(row.id)).frame(width: 10, height: 10)
                    Text(row.label).font(.subheadline).foregroundStyle(Theme.text).frame(width: 74, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surface2)
                            Capsule().fill(Theme.sport(row.id)).frame(width: geo.size.width * (row.rate ?? 0))
                        }
                    }
                    .frame(height: 8)
                    Text(percent(row.rate)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text).frame(width: 44, alignment: .trailing)
                    Text("\(row.done)/\(row.planned)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary).frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

struct MovesCard: View {
    let s: Stats.Summary
    var body: some View {
        let lead: String = s.moved > 0
            ? "\(s.moved) session\(s.moved == 1 ? " was" : "s were") moved rather than lost, against \(s.movesMissed) missed outright."
            : (s.movesMissed > 0 ? "\(s.movesMissed) session\(s.movesMissed == 1 ? "" : "s") missed, and none rescheduled." : "Nothing missed and nothing moved.")
        StatCard(title: "Missed, or moved", lede: lead) {
            HStack(spacing: 8) {
                Figure(value: "\(s.moved)", label: "moved and kept")
                Figure(value: "\(s.movesMissed)", label: "missed")
            }
            Text("Moving a session rewrites its date in the workbook, so the sheet keeps no record that it ever moved. This app remembers its own moves" +
                 (s.movesSince.map { " since " + Dates.short.string(from: $0) } ?? "") + ", on this phone only. Anything rescheduled in Excel or in the web app is invisible here.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}
