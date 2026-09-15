import Foundation

/*
 * What the plan says about how the training is actually going — a port of
 * js/stats.js, with the row builders from js/sync.js and the road from
 * js/ui.js. The Progress sheet's cells are formulas that carry Excel's last
 * answer, so nothing here reads them: every figure is derived from the
 * session rows, none are stored, nothing writes anything.
 *
 *   - which sport quietly runs behind the others
 *   - how consistent the last stretch has been
 *   - how often a session was moved rather than lost
 *   - whether any of it is working: distance per heartbeat, then against now
 *   - twelve weeks against what they asked for, and where the hours went
 *   - the road to the race
 */

public struct MoveRecord: Codable, Equatable {
    public let from: String
    public let to: String
    public let disciplineId: String
    public let at: Date
    public init(from: String, to: String, disciplineId: String, at: Date) {
        self.from = from; self.to = to; self.disciplineId = disciplineId; self.at = at
    }
}

public enum Stats {
    // MARK: kept

    public enum Outcome: String { case done, missed, unlogged }

    struct Past {
        let key: String
        let dayKey: String
        let discipline: Discipline
        let order: Int
        let plannedSeconds: Double
        let outcome: Outcome
    }

    public struct SportRow: Identifiable, Equatable {
        public var id: String
        public let label: String
        public let order: Int
        public var planned = 0, done = 0, missed = 0, unlogged = 0
        public var plannedSeconds = 0.0, doneSeconds = 0.0
        public var rate: Double? = nil
    }

    public struct Summary: Equatable {
        public let any: Bool
        public let counted: Int, done: Int, missed: Int, unlogged: Int, answered: Int
        public let firstDay: String?, lastDay: String?
        public let streakCurrent: Int, streakLongest: Int
        public let sports: [SportRow]
        public let worst: SportRow?
        public let moved: Int, movesMissed: Int
        public let keptByMoving: Double?
        public let movesSince: Date?
    }

    static func moveFor(_ w: Workout, _ moves: [String: MoveRecord]) -> MoveRecord? {
        guard let move = moves[w.key] else { return nil }
        if !move.disciplineId.isEmpty && move.disciplineId != w.discipline.id { return nil }
        return move
    }

    /* Past, non-rest sessions, oldest first. Today is neither due nor behind. */
    public static func summarise(_ plan: [Workout], moves: [String: MoveRecord], movesSince: Date?, today: String, mapping: Mapping) -> Summary {
        let past: [Past] = plan
            .filter { $0.discipline.id != "rest" && !$0.dayKey.isEmpty && $0.dayKey < today }
            .map { w in
                let outcome: Outcome = w.missed ? .missed : (w.logged ? .done : .unlogged)
                return Past(key: w.key, dayKey: w.dayKey, discipline: w.discipline, order: Disciplines.order(w.discipline.id),
                            plannedSeconds: Plan.plannedSeconds(w, mapping) ?? 0, outcome: outcome)
            }
            .enumerated().sorted { a, b in a.element.dayKey != b.element.dayKey ? a.element.dayKey < b.element.dayKey : a.offset < b.offset }
            .map(\.element)

        let done = past.filter { $0.outcome == .done }.count
        let missed = past.filter { $0.outcome == .missed }.count
        let unlogged = past.filter { $0.outcome == .unlogged }.count

        // Streaks: a missed or unanswered session breaks the run.
        var run = 0, longest = 0
        for p in past { if p.outcome == .done { run += 1; longest = max(longest, run) } else { run = 0 } }
        var current = 0
        for p in past.reversed() { if p.outcome != .done { break }; current += 1 }

        // By sport, in training order; minutes as well as counts.
        var rows: [SportRow] = []
        var index: [String: Int] = [:]
        for p in past {
            let id = p.discipline.id
            if index[id] == nil {
                index[id] = rows.count
                rows.append(SportRow(id: id, label: p.discipline.label, order: p.order))
            }
            let i = index[id]!
            rows[i].planned += 1
            switch p.outcome {
            case .done: rows[i].done += 1; rows[i].doneSeconds += p.plannedSeconds
            case .missed: rows[i].missed += 1
            case .unlogged: rows[i].unlogged += 1
            }
            rows[i].plannedSeconds += p.plannedSeconds
        }
        for i in rows.indices where rows[i].planned > 0 { rows[i].rate = Double(rows[i].done) / Double(rows[i].planned) }
        rows = rows.enumerated().sorted { a, b in a.element.order != b.element.order ? a.element.order < b.element.order : a.offset < b.offset }.map(\.element)
        let worst = rows.reduce(nil as SportRow?) { low, row in
            guard let low else { return row }
            return (row.rate ?? 0) < (low.rate ?? 0) ? row : low
        }

        // Moved rather than lost: only past, only not missed in the end.
        let moved = plan.filter { w in
            w.discipline.id != "rest" && w.dayKey < today && !w.missed
        }.filter { w in
            guard let m = moveFor(w, moves) else { return false }
            return !m.from.isEmpty && !m.to.isEmpty && m.from != m.to
        }.count
        let total = missed + moved

        return Summary(any: !past.isEmpty, counted: past.count, done: done, missed: missed, unlogged: unlogged,
                       answered: done + missed, firstDay: past.first?.dayKey, lastDay: past.last?.dayKey,
                       streakCurrent: current, streakLongest: longest, sports: rows, worst: worst,
                       moved: moved, movesMissed: missed, keptByMoving: total > 0 ? Double(moved) / Double(total) : nil,
                       movesSince: movesSince)
    }

    // MARK: rows

    public struct Actuals {
        public let sport: String, dayKey: String
        public let minutes: Double, km: Double, hr: Double, rpe: Double
    }

    /* What a logged session actually recorded, one shape and one set of units. */
    public static func actualsOf(_ w: Workout, _ mapping: Mapping) -> Actuals {
        let units = mapping.units
        func number(_ s: String?) -> Double {
            let n = jsParseFloat(firstCommaToDot(s ?? ""))
            return n.isNaN ? 0 : n
        }
        var minutes = 0.0, distance = 0.0, hr = 0.0, rpe = 0.0
        if let typed = w.pending, !typed.missed {
            let seconds = parseDuration(typed.actualDuration)
            minutes = seconds.map { $0 / 60 } ?? 0
            distance = number(typed.actualDistance)
            hr = number(typed.avgHr)
            rpe = number(typed.rpe)
            if (typed.distanceUnit ?? "km") == "m" { distance /= 1000 }
            else if units.distance == "m" && typed.distanceUnit == nil { distance /= 1000 }
        } else {
            func cell(_ id: String) -> Double { w.results[id]?.number ?? 0 }
            let seconds = cell("actualDuration") != 0 ? (durationFromCell(cell("actualDuration"), units.duration) ?? 0) : 0
            minutes = seconds != 0 ? seconds / 60 : 0
            distance = cell("actualDistance")
            if units.distance == "m" { distance /= 1000 }
            hr = cell("avgHr")
            rpe = cell("rpe")
        }
        return Actuals(sport: w.discipline.id, dayKey: w.dayKey, minutes: minutes, km: distance, hr: hr, rpe: rpe)
    }

    /* What a logged session actually took, where the sheet or the queue says. */
    public static func actualSeconds(_ w: Workout, _ mapping: Mapping) -> Double? {
        if let typed = w.pending, !typed.missed { return parseDuration(typed.actualDuration) }
        if let n = w.results["actualDuration"]?.number { return durationFromCell(n, mapping.units.duration) }
        return nil
    }

    public static func trendRows(_ plan: [Workout], _ mapping: Mapping) -> [Actuals] {
        plan.filter { $0.discipline.id != "rest" && $0.logged && !$0.missed }.map { actualsOf($0, mapping) }
    }

    public struct LoadRow { public let sport: String, dayKey: String, planned: Double, actual: Double }

    public static func loadRows(_ plan: [Workout], _ mapping: Mapping) -> [LoadRow] {
        plan.filter { $0.discipline.id != "rest" }.map { w in
            let done = w.logged && !w.missed
            let a = done ? actualsOf(w, mapping) : nil
            return LoadRow(sport: w.discipline.id, dayKey: w.dayKey, planned: Plan.plannedSeconds(w, mapping) ?? 0,
                           actual: (a.map { $0.minutes > 0 ? $0.minutes * 60 : 0 }) ?? 0)
        }
    }

    // MARK: is it working

    public struct Half: Equatable {
        public let sessions: Int, from: String, to: String
        public let speed: Double, hr: Double, paceSeconds: Double, perBeat: Double
    }

    public struct Trend: Identifiable, Equatable {
        public var id: String { sport }
        public let sport: String
        public let enough: Bool
        public let have: Int, need: Int, usable: Int
        public let easyOnly: Bool
        public let sessions: Int
        public let then: Half?, now: Half?
        public let change: Double, speedChange: Double, hrChange: Double
        public let verdict: String
    }

    static let trendSports = ["swim", "bike", "run"]
    static let minPerHalf = 4
    static let easyRpe = 5.0

    static func usable(_ r: Actuals) -> Bool {
        r.minutes.isFinite && r.minutes > 0 && r.km.isFinite && r.km > 0 && r.hr.isFinite && r.hr >= 60 && r.hr <= 220
    }

    static func half(_ rows: [Actuals]) -> Half {
        let speed = rows.isEmpty ? 0 : rows.reduce(0.0) { $0 + $1.km / ($1.minutes / 60) } / Double(rows.count)
        let hr = rows.isEmpty ? 0 : rows.reduce(0.0) { $0 + $1.hr } / Double(rows.count)
        return Half(sessions: rows.count, from: rows.first?.dayKey ?? "", to: rows.last?.dayKey ?? "",
                    speed: speed, hr: hr, paceSeconds: speed > 0 ? 3600 / speed : 0, perBeat: hr > 0 ? speed / hr : 0)
    }

    public static func verdict(_ change: Double) -> String {
        if change >= 0.03 { return "better" }
        if change <= -0.03 { return "down" }
        return "level"
    }

    public static func trends(_ rows: [Actuals]) -> [Trend] {
        var out: [Trend] = []
        for sport in trendSports {
            let mine = rows.filter { $0.sport == sport }
            if mine.isEmpty { continue }
            let all = mine.filter(usable)
            let easy = all.filter { $0.rpe > 0 && $0.rpe <= easyRpe }
            let easyOnly = easy.count >= minPerHalf * 2
            let used = (easyOnly ? easy : all).enumerated()
                .sorted { a, b in a.element.dayKey != b.element.dayKey ? a.element.dayKey < b.element.dayKey : a.offset < b.offset }
                .map(\.element)
            if used.count < minPerHalf * 2 {
                out.append(Trend(sport: sport, enough: false, have: used.count, need: minPerHalf * 2, usable: all.count,
                                 easyOnly: easyOnly, sessions: used.count, then: nil, now: nil, change: 0, speedChange: 0, hrChange: 0, verdict: "level"))
                continue
            }
            // Split by count, not date: a winter gap would otherwise compare a season with a fortnight.
            let middle = used.count / 2
            let then = half(Array(used.prefix(middle)))
            let now = half(Array(used.suffix(middle)))
            let change = then.perBeat > 0 ? (now.perBeat - then.perBeat) / then.perBeat : 0
            out.append(Trend(sport: sport, enough: true, have: used.count, need: minPerHalf * 2, usable: all.count, easyOnly: easyOnly,
                             sessions: used.count, then: then, now: now, change: change,
                             speedChange: then.speed > 0 ? (now.speed - then.speed) / then.speed : 0,
                             hrChange: then.hr > 0 ? (now.hr - then.hr) / then.hr : 0, verdict: verdict(change)))
        }
        return out
    }

    // MARK: where the hours went

    public struct Week: Identifiable, Equatable {
        public var id: String { start }
        public let start: String
        public var planned = 0.0, actual = 0.0
        public var sessions = 0
    }

    public struct SportLoad: Identifiable, Equatable {
        public var id: String { sport }
        public let sport: String
        public var planned = 0.0, actual = 0.0
        public var shareActual = 0.0, sharePlanned = 0.0
    }

    public struct Load: Equatable {
        public let weeks: [Week]
        public let sports: [SportLoad]
        public let planned: Double, actual: Double
    }

    public static func load(_ rows: [LoadRow], weekStarts: [String], endExclusive: String?) -> Load {
        let starts = weekStarts.sorted()
        guard let from = starts.first else { return Load(weeks: [], sports: [], planned: 0, actual: 0) }
        var weeks = starts.map { Week(start: $0) }
        var bySport: [String: SportLoad] = [:]
        var order: [String] = []
        var planned = 0.0, actual = 0.0
        let seconds = { (v: Double) -> Double in v.isFinite && v > 0 ? v : 0 }

        for row in rows {
            if row.dayKey.isEmpty || row.dayKey < from { continue }
            if let until = endExclusive, row.dayKey >= until { continue }
            guard let i = weeks.indices.reversed().first(where: { row.dayKey >= weeks[$0].start }) else { continue }
            let p = seconds(row.planned), a = seconds(row.actual)
            weeks[i].planned += p; weeks[i].actual += a
            if a > 0 { weeks[i].sessions += 1 }
            planned += p; actual += a
            if bySport[row.sport] == nil { bySport[row.sport] = SportLoad(sport: row.sport); order.append(row.sport) }
            bySport[row.sport]!.planned += p
            bySport[row.sport]!.actual += a
        }

        var sports = order.compactMap { bySport[$0] }.filter { $0.planned > 0 || $0.actual > 0 }
        sports = sports.enumerated().sorted { a, b in
            if a.element.actual != b.element.actual { return a.element.actual > b.element.actual }
            if a.element.planned != b.element.planned { return a.element.planned > b.element.planned }
            return a.offset < b.offset
        }.map(\.element)
        for i in sports.indices {
            sports[i].shareActual = actual > 0 ? sports[i].actual / actual : 0
            sports[i].sharePlanned = planned > 0 ? sports[i].planned / planned : 0
        }
        return Load(weeks: weeks, sports: sports, planned: planned, actual: actual)
    }

    /* The Mondays of the last `count` weeks, oldest first, this week last. */
    public static func recentWeekStarts(_ count: Int, today: String) -> [String] {
        let thisWeek = PlanView.weekStart(today)
        return (0..<count).reversed().map { PlanView.addDays(thisWeek, -$0 * 7) }
    }

    // MARK: the road to the race

    public struct Phase: Identifiable, Equatable {
        public var id: String { name + from }
        public let name: String
        public var from: String, to: String
    }

    public struct Road: Equatable {
        public let raceDay: String, raceTitle: String, isRace: Bool
        public let start: String
        public let phases: [Phase]
        public let sessions: Int, done: Int, behind: Int, toCome: Int
        public let plannedAll: Double, plannedSoFar: Double, doneSeconds: Double
        public let daysToGo: Int, weeksToGo: Int
        public let through: Double
        public let started: Bool
    }

    public static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let x = parseDayKey(a), let y = parseDayKey(b) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86400).rounded())
    }

    /* The race the plan names, else the last day of the plan, called what it is. */
    public static func road(_ visible: [Workout], today: String, mapping: Mapping) -> Road? {
        let plan = visible.filter { $0.discipline.id != "rest" }
        guard let first = plan.first, let last = visible.last else { return nil }

        let races = visible.filter { $0.discipline.id == "race" }
        let ahead = races.filter { $0.dayKey >= today }
        let chosen = ahead.first ?? races.last
        let raceDay = chosen?.dayKey ?? last.dayKey
        let raceTitle = chosen.map { $0.title.isEmpty ? "Race day" : $0.title } ?? "The last day of the plan"

        var phases: [Phase] = []
        for w in visible {
            let name = w.phase.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            if let i = phases.indices.last, phases[i].name == name { phases[i].to = w.dayKey; continue }
            phases.append(Phase(name: name, from: w.dayKey, to: w.dayKey))
        }

        let start = first.dayKey
        var plannedAll = 0.0, plannedSoFar = 0.0, doneSeconds = 0.0
        var done = 0, behind = 0, toCome = 0
        for w in plan {
            let seconds = Plan.plannedSeconds(w, mapping) ?? 0
            plannedAll += seconds
            let past = w.dayKey < today
            if past { plannedSoFar += seconds }
            if w.dayKey > today { toCome += 1 }
            if !w.logged { if past { behind += 1 }; continue }
            if w.missed { continue }
            done += 1
            doneSeconds += actualSeconds(w, mapping) ?? seconds
        }
        let totalDays = max(1, daysBetween(start, raceDay))
        let goneDays = min(totalDays, max(0, daysBetween(start, today)))
        let toGo = daysBetween(today, raceDay)
        return Road(raceDay: raceDay, raceTitle: raceTitle, isRace: chosen != nil, start: start, phases: phases,
                    sessions: plan.count, done: done, behind: behind, toCome: toCome,
                    plannedAll: plannedAll, plannedSoFar: plannedSoFar, doneSeconds: doneSeconds,
                    daysToGo: toGo, weeksToGo: Int((Double(toGo) / 7).rounded(.up)),
                    through: Double(goneDays) / Double(totalDays), started: today >= start)
    }
}
