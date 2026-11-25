import Foundation

/*
 * Load: minutes times how hard it was, 1 to 10.
 *
 * The fitness card weighs a session by heart rate against a threshold pulse,
 * which needs a test number and knows nothing of a day in the hills. This is
 * the plain measure beside it: his own answer to "How hard was it?", times
 * the minutes — for every activity, the plan's sessions, the extras and the
 * workouts the watch sent to Health that are in neither.
 *
 * It shows; it never advises. Nothing here suggests anything.
 */
public enum Load {

    /* Counted when nobody said how hard it was and the plan gives no zone: easy. */
    public static let guess = 3.0
    /* A workout from Health shorter than this is not counted (ten minutes). */
    public static let shortestSeconds = 600.0
    /* Two lengths this close, in minutes, can be the same activity. */
    public static let sameLengthMinutes = 5.0

    public enum Source: String, Equatable { case answered, planned, guessed }

    public struct Score: Equatable {
        public let value: Double
        public let source: Source
        public init(value: Double, source: Source) { self.value = value; self.source = source }
    }

    /* The whole rule. A score outside 1 to 10 is no score, and counts nothing. */
    public static func points(minutes: Double, score: Double) -> Double {
        guard minutes > 0, score >= 1, score <= 10 else { return 0 }
        return minutes * score
    }

    /*
     * The plan's own word for how hard a session is meant to be, as a 1-to-10
     * figure: Z1 2, Z2 3, Z3 5, Z4 7, Z5 9, the middle of a range; "RPE 6–7"
     * is already on the scale. Nil when the plan says nothing usable.
     */
    public static func fromZone(_ intensity: String) -> Double? {
        let text = intensity.uppercased()
        let table: [Int: Double] = [1: 2, 2: 3, 3: 5, 4: 7, 5: 9]
        let zones = text.split(separator: "Z").dropFirst(text.hasPrefix("Z") ? 0 : 1).compactMap { part -> Double? in
            guard let first = part.first, let n = Int(String(first)) else { return nil }
            return table[n]
        }
        if !zones.isEmpty { return zones.reduce(0, +) / Double(zones.count) }
        if let at = text.range(of: "RPE") {
            var numbers: [Double] = []
            var digits = ""
            for ch in text[at.upperBound...] + " " {
                if ch.isNumber { digits.append(ch) } else {
                    if let n = Double(digits), n >= 1, n <= 10 { numbers.append(n) }
                    digits = ""
                }
            }
            if !numbers.isEmpty { return numbers.reduce(0, +) / Double(numbers.count) }
        }
        return nil
    }

    /* His answer first; failing that the plan's zone; failing that, easy — and it says which. */
    public static func score(answered: Double, planned: String) -> Score {
        if answered >= 1, answered <= 10 { return Score(value: answered, source: .answered) }
        if let z = fromZone(planned) { return Score(value: z, source: .planned) }
        return Score(value: guess, source: .guessed)
    }

    // MARK: what Health holds that nothing else does

    /* Something already written down for a day: a done session, or an extra. */
    public struct Recorded: Equatable {
        public let dayKey: String
        public let sport: String
        public let minutes: Double
        public init(dayKey: String, sport: String, minutes: Double) {
            self.dayKey = dayKey; self.sport = sport; self.minutes = minutes
        }
    }

    /* A workout as Health hands it over. */
    public struct Found: Identifiable, Equatable, Codable {
        public let id: String
        public let dayKey: String
        public let sport: String
        public let name: String
        public let minutes: Double
        public init(id: String, dayKey: String, sport: String, name: String, minutes: Double) {
            self.id = id; self.dayKey = dayKey; self.sport = sport; self.name = name; self.minutes = minutes
        }
    }

    /* One word for sports that are the same thing under two names. */
    static func family(_ id: String) -> String {
        switch id {
        case "yoga", "mobility": return "mobility"
        case "hike", "walk": return "walk"
        default: return id
        }
    }

    /* 0 the same sport, 1 near enough (a run recorded as a walk, a brick's two halves), nil not at all. */
    static func kinship(recorded: String, found: String) -> Int? {
        let a = family(recorded), b = family(found)
        if a == b { return 0 }
        if a == "brick", b == "bike" || b == "run" { return 0 }
        if (a == "run" && b == "walk") || (a == "walk" && b == "run") { return 1 }
        if a == "race", ["swim", "bike", "run"].contains(b) { return 1 }
        return nil
    }

    /*
     * The workouts in Health that are not already in the plan or the extras.
     *
     * A workout is taken as already written down when something recorded that
     * day can be it: the same sport, or — where the sports have different
     * names — nearly the same length. Each recorded thing accounts for one
     * workout at most, so a morning run and an evening run are two.
     * Breathing and meditation are not load, and nor is anything under ten
     * minutes.
     */
    public static func outside(_ found: [Found], recorded: [Recorded]) -> [Found] {
        var left = found.filter { $0.minutes * 60 >= shortestSeconds && $0.sport != "mind" }
        var unmatched: [Recorded] = []
        for r in recorded {
            let candidates = left.enumerated().compactMap { pair -> (Int, Int, Double)? in
                guard pair.element.dayKey == r.dayKey,
                      let kin = kinship(recorded: r.sport, found: pair.element.sport) else { return nil }
                return (pair.offset, kin, abs(pair.element.minutes - r.minutes))
            }
            if let best = candidates.min(by: { ($0.1, $0.2) < ($1.1, $1.2) }) {
                left.remove(at: best.0)
            } else {
                unmatched.append(r)
            }
        }
        for r in unmatched where r.minutes > 0 {
            let candidates = left.enumerated().filter {
                $0.element.dayKey == r.dayKey && abs($0.element.minutes - r.minutes) <= sameLengthMinutes
            }
            if let best = candidates.min(by: { abs($0.element.minutes - r.minutes) < abs($1.element.minutes - r.minutes) }) {
                left.remove(at: best.offset)
            }
        }
        return left
    }

    // MARK: adding it up

    public struct Item: Equatable {
        public let dayKey: String
        public let minutes: Double
        public let score: Score
        public let inPlan: Bool
        public var points: Double { Load.points(minutes: minutes, score: score.value) }
        public init(dayKey: String, minutes: Double, score: Score, inPlan: Bool) {
            self.dayKey = dayKey; self.minutes = minutes; self.score = score; self.inPlan = inPlan
        }
    }

    /* What the plan's done sessions and the extras are, to the matching above. */
    public static func recorded(_ plan: [Workout], extras: [ExtraSummary], mapping: Mapping) -> [Recorded] {
        var out: [Recorded] = []
        for w in plan where w.logged && !w.missed && w.discipline.id != "rest" {
            out.append(Recorded(dayKey: w.dayKey, sport: w.discipline.id, minutes: minutes(of: w, mapping)))
        }
        for x in extras { out.append(Recorded(dayKey: x.dayKey, sport: x.activity, minutes: x.minutes ?? 0)) }
        return out
    }

    static func minutes(of w: Workout, _ mapping: Mapping) -> Double {
        let a = Stats.actualsOf(w, mapping)
        return a.minutes > 0 ? a.minutes : (Plan.plannedSeconds(w, mapping) ?? 0) / 60
    }

    /*
     * Everything that counts, one item each:
     *   - a session of the plan that is done (not missed, not a rest day),
     *   - every extra except breathing and meditation — whatever its "counts
     *     as training" switch says, because a hike is load either way,
     *   - a workout from Health that is in neither.
     * `answers` holds how hard he said a Health workout was, by its id.
     */
    public static func items(_ plan: [Workout], extras: [ExtraSummary], mapping: Mapping,
                             outside: [Found], answers: [String: Double]) -> [Item] {
        var out: [Item] = []
        for w in plan where w.logged && !w.missed && w.discipline.id != "rest" {
            let rpe = Stats.actualsOf(w, mapping).rpe
            out.append(Item(dayKey: w.dayKey, minutes: minutes(of: w, mapping),
                            score: score(answered: rpe, planned: w.planned.intensity), inPlan: true))
        }
        for x in extras where x.activity != "breathing" && x.activity != "meditation" {
            let effort = jsParseFloat(firstCommaToDot(x.effort))
            out.append(Item(dayKey: x.dayKey, minutes: x.minutes ?? 0,
                            score: score(answered: effort.isNaN ? 0 : effort, planned: ""), inPlan: false))
        }
        for f in outside {
            out.append(Item(dayKey: f.dayKey, minutes: f.minutes,
                            score: score(answered: answers[f.id] ?? 0, planned: ""), inPlan: false))
        }
        return out.filter { $0.minutes > 0 }
    }

    public struct Week: Identifiable, Equatable {
        public var id: String { start }
        public let start: String
        public var inPlan: Double
        public var outside: Double
        public var total: Double { inPlan + outside }
        public init(start: String, inPlan: Double = 0, outside: Double = 0) {
            self.start = start; self.inPlan = inPlan; self.outside = outside
        }
    }

    /* The given weeks (their Mondays, oldest first), each with what fell in it. */
    public static func weeks(_ items: [Item], starts: [String]) -> [Week] {
        var byStart: [String: Week] = [:]
        for s in starts { byStart[s] = Week(start: s) }
        for item in items {
            let s = PlanView.weekStart(item.dayKey)
            guard var week = byStart[s] else { continue }
            if item.inPlan { week.inPlan += item.points } else { week.outside += item.points }
            byStart[s] = week
        }
        return starts.compactMap { byStart[$0] }
    }

    /*
     * A usual week: the average of the four finished weeks before the last
     * one in the list (the last is the week still being lived). Weeks before
     * anything was ever recorded are left out, so the first month is not
     * averaged with nothing. Nil when there is no finished week to go by.
     */
    public static func usual(_ weeks: [Week], firstDay: String?) -> Double? {
        guard weeks.count > 1 else { return nil }
        let firstWeek = firstDay.map(PlanView.weekStart) ?? ""
        let before = weeks.dropLast().suffix(4).filter { $0.start >= firstWeek }
        guard !before.isEmpty else { return nil }
        return before.reduce(0) { $0 + $1.total } / Double(before.count)
    }
}

/*
 * "How do you feel?" — asked once a morning, answered with one tap.
 *
 * Kept on the phone and nowhere else: it is not a figure of the plan, and the
 * workbook has no column for it. One answer a day; a second tap the same day
 * replaces the first rather than adding to it.
 */
public enum Feel: Int, CaseIterable, Codable, Identifiable, Sendable {
    case bad = 1, tired, ok, good, great
    public var id: Int { rawValue }
    public var word: String {
        switch self {
        case .bad: return "Bad"
        case .tired: return "Tired"
        case .ok: return "OK"
        case .good: return "Good"
        case .great: return "Great"
        }
    }
}

public struct FeelLog: Codable, Equatable {
    public private(set) var days: [String: Int] = [:]
    public init() {}
    /* The answers as they travel between devices (DiaryDoc). */
    public init(days: [String: Int]) { self.days = days }

    public func answer(on day: String) -> Feel? { days[day].flatMap(Feel.init(rawValue:)) }
    /* The question is put only while the day has no answer. */
    public func asks(on day: String) -> Bool { answer(on: day) == nil }
    public mutating func set(_ feel: Feel, on day: String) { days[day] = feel.rawValue }

    /* The last `count` days ending on `day`, oldest first; nil where nothing was answered. */
    public func last(_ count: Int, endingOn day: String) -> [Feel?] {
        (0..<max(0, count)).reversed().map { answer(on: PlanView.addDays(day, -$0)) }
    }
}
