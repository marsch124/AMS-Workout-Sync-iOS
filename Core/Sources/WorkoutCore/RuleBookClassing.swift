import Foundation

/*
 * What "hard", "key" and "easy" mean, read from the plan's own words
 * (spec section 3), and the small sums every trigger and limit shares.
 */

public enum RBClass: String, Codable, Equatable, Sendable {
    case hard, moderate, heavyStrength, easy, other
}

public struct RBLabels: Equatable, Sendable {
    public var test = false, sim = false, race = false, long = false, brick = false, key = false
    /* Tests, sims, race and every race-week session: the engine never touches them (L6). */
    public var protectedKind: Bool { test || sim || race }
}

public struct RBZones: Equatable, Sendable {
    public var zones: [Int]
    public var low: Int? { zones.min() }
    public var top: Int? { zones.max() }
    public var rpeTop: Int?
    public var saysLow: Bool
}

extension RuleBook {

    // MARK: 3.1 the intensity text

    public static func zones(_ text: String) -> RBZones {
        var zones: [Int] = []
        let chars = Array(text.uppercased())
        for (i, c) in chars.enumerated() where c == "Z" && i + 1 < chars.count {
            if let n = chars[i + 1].wholeNumberValue { zones.append(n) }
        }
        var rpeTop: Int?
        if let r = text.uppercased().range(of: "RPE") {
            let numbers = text[r.upperBound...].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            rpeTop = numbers.prefix(2).max()
        }
        return RBZones(zones: zones, rpeTop: rpeTop, saysLow: normalise(text).contains("low"))
    }

    // MARK: 3.2 labels

    public static func labels(_ s: RBSession) -> RBLabels {
        let t = s.title.trimmingCharacters(in: .whitespaces).lowercased()
        var l = RBLabels()
        l.test = t.hasPrefix("test —") || t.hasPrefix("test -") || t.hasPrefix("test:")
        l.sim = t.hasPrefix("race sim")
        l.race = s.sport == .race || normalise(s.intensity) == "race day"
        l.long = ["long run", "long ride", "reduced long run", "reduced long ride"].contains { t.hasPrefix($0) }
        l.brick = t.hasPrefix("brick run") || s.sport == .brick
        l.key = s.star || l.test || l.sim || l.race
        return l
    }

    // MARK: 3.3 classes

    public static func sessionClass(_ s: RBSession) -> RBClass {
        let l = labels(s)
        if l.test || l.sim || l.race { return .hard }
        let z = zones(s.intensity)
        if s.sport == .strength {
            guard let r = z.rpeTop else { return .other }
            if r >= 7 { return .heavyStrength }
            if r == 6 { return .moderate }
            return l.key ? .other : .easy
        }
        guard let top = z.top, let low = z.low else { return .other }
        if top >= 4 || (top == 3 && low == 3) { return .hard }
        if top == 3 { return .moderate }
        if top <= 2 && !l.long && !l.brick && !l.key { return .easy }
        return .other
    }

    /* A day holding a HARD bike, run, brick, test or sim (swims and strength left out) — L2. */
    static func isHardLeg(_ s: RBSession) -> Bool {
        guard s.counts, s.sport != .swim, s.sport != .strength else { return false }
        return sessionClass(s) == .hard
    }

    // MARK: 3.5 felt harder than planned

    public static func expectedEffort(_ s: RBSession) -> Int? {
        let l = labels(s)
        var e: Int?
        if l.test { e = 9 } else if l.sim { e = 7 }
        else if s.sport == .strength { e = zones(s.intensity).rpeTop }
        else {
            let z = zones(s.intensity)
            if let low = z.low, let top = z.top {
                switch (low, top) {
                case (1, 1): e = 2
                case (1, 2): e = 3
                case (2, 2): e = 4
                case (1, 3), (2, 3): e = 5
                case (3, 3): e = 6
                case (3, 4): e = 7
                case (4, 4): e = z.saysLow ? 7 : 8
                case (4, 5), (5, 5): e = 9
                default: e = nil
                }
            }
        }
        guard var out = e else { return nil }
        if l.long { out = min(10, out + 1) }
        return out
    }

    /* Done, dated today or earlier, and his "how hard" answer ≥ expected + margin. Ticks dated later are ignored. */
    public static func feltHarder(_ s: RBSession, today: String, margin: Int) -> Bool {
        guard s.status == .done, s.day <= today, let rpe = s.rpe, let e = expectedEffort(s) else { return false }
        return rpe >= e + margin
    }

    // MARK: weeks

    public static func planWeek(_ day: String, start: String) -> Int {
        guard let a = parseDayKey(start), let b = parseDayKey(day) else { return 0 }
        let days = Int((b.timeIntervalSince(a) / 86400).rounded(.down))
        return 1 + Int((Double(days) / 7).rounded(.down))
    }

    static func weekday(_ day: String) -> Int {   // Monday 0 … Sunday 6
        guard let d = parseDayKey(day) else { return 0 }
        return (utc.component(.weekday, from: d) + 5) % 7
    }

    public static func isFriday(_ day: String) -> Bool { weekday(day) == 4 }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let x = parseDayKey(a), let y = parseDayKey(b) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86400).rounded())
    }
}

extension RuleBookInput {
    func week(of day: String) -> Int { RuleBook.planWeek(day, start: planStart) }
    func weekInfo(_ number: Int) -> RBWeek? { weeks.first { $0.number == number } }
    func tag(_ number: Int) -> RBWeekTag {
        if number == settings.raceWeek { return .race }
        return weekInfo(number)?.tag ?? .load
    }
    func isTaper(_ number: Int) -> Bool { weekInfo(number)?.isTaper ?? false }
    func monday(of number: Int) -> String { PlanView.addDays(planStart, 7 * (number - 1)) }
    func session(_ id: String) -> RBSession? { sessions.first { $0.id == id } }
    var todayWeek: Int { week(of: today) }

    /* Days whose logs the engine may know: before today in the morning, up to today later on. */
    func known(_ day: String) -> Bool { moment == .morning ? day < today : day <= today }

    // MARK: 3.7 counted minutes

    func countedMinutes(on day: String) -> Int {
        var total = 0
        for s in sessions where s.day == day && s.status == .done && !s.isRest && !s.dropped && known(s.day) {
            total += s.actualMin ?? s.plannedMin
        }
        for x in extras where x.day == day && known(x.day) && countsExtra(x) { total += x.minutes }
        return total
    }

    func countsExtra(_ x: RBExtra) -> Bool {
        if ["breathing", "meditation"].contains(x.activity) { return false }
        // OPEN: "extras that count, hikes included" — read as: a hike counts even when not marked as training.
        return x.countsAsTraining || (settings.hikesAlwaysCount && x.activity == "hike")
    }

    func countedMinutes(week number: Int) -> Int {
        let monday = monday(of: number)
        return (0..<7).reduce(0) { $0 + countedMinutes(on: PlanView.addDays(monday, $1)) }
    }

    /* Mean counted minutes of the `count` plan weeks before `number` (weeks before week 1 left out). */
    func meanCounted(before number: Int, count: Int) -> Double? {
        let weeks = (max(1, number - count)..<number).map { $0 }
        guard !weeks.isEmpty else { return nil }
        return Double(weeks.reduce(0) { $0 + countedMinutes(week: $1) }) / Double(weeks.count)
    }

    /* Planned minutes of week w as the sessions now stand (by date). */
    func plannedMinutes(week number: Int, in list: [RBSession]) -> Int {
        list.filter { $0.counts && week(of: $0.day) == number }.reduce(0) { $0 + $1.plannedMin }
    }

    // MARK: 3.6 bad-signal days

    var hrvActive: Bool { today >= settings.hrvStartDay && hrvNights >= settings.hrvNightsNeeded }

    func isBadSignalDay(_ day: String) -> Bool {
        guard day <= today else { return false }
        let answer = feel.answer(on: day)?.rawValue
        if let a = answer, a <= 2, !(moment == .morning && day > today) { return true }
        if sessions.contains(where: { $0.day == day && known(day) && RuleBook.feltHarder($0, today: today, margin: settings.feltHarderMargin) }) {
            return true
        }
        // HRV stays dormant (8.3) until its day and its nights; then only with an answer of 3 or less.
        if hrvActive, hrvLowDays.contains(day), let a = answer, a <= 3 { return true }
        // Q5: resting pulse counts only if he chose so, and only with an answer of 3 or less.
        if !settings.restingPulseShownOnly, highPulseDays.contains(day), let a = answer, a <= 3 { return true }
        return false
    }

    func isTiredWeek(_ number: Int) -> Bool {
        let monday = monday(of: number)
        return (0..<7).filter { isBadSignalDay(PlanView.addDays(monday, $0)) }.count >= 2
    }

    // MARK: L5's reference

    /* Longest done LONG session of this sport in the window before `day`; failing that the longest done session of it. */
    func longReference(sport: RBSport, before day: String) -> Int? {
        let from = PlanView.addDays(day, -settings.lookBackDays)
        // OPEN: a window reaching back before the plan began knows nothing of what was done then: no check.
        if from < planStart { return nil }
        let done = sessions.filter { $0.sport == sport && $0.status == .done && $0.day >= from && $0.day < day && known($0.day) }
        let minutes = { (s: RBSession) in s.actualMin ?? s.plannedMin }
        if let best = done.filter({ RuleBook.labels($0).long }).map(minutes).max() { return best }
        return done.map(minutes).max()
    }

    func longStep(sport: RBSport, ref: Int) -> Int {
        let tenth = RuleBook.roundTo5(Double(ref) * settings.longStepFraction)
        return max(sport == .bike ? settings.longStepMinRide : settings.longStepMinRun, tenth)
    }
}

extension RuleBook {
    /* To the nearest 5 (7 → 5, 8 → 10). */
    public static func roundTo5(_ x: Double) -> Int { Int((x / 5).rounded()) * 5 }
}
