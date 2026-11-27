import Foundation

/*
 * The plan maker (round 30, pick 1): "A new season plan made in the app:
 * race, date, hours a week." The new plan is a DRAFT beside his own plan,
 * which it never touches; he looks it through and switches when he chooses
 * (DraftSwitch.swift).
 *
 * The rules, all here and all tested:
 *
 *   Blocks ......... Base → Build → Peak → Taper → race week → Post-season,
 *                    sized to the weeks there are. Taper: 1 week before race
 *                    week (2 for a full), so about 2 weeks for a half. Peak:
 *                    1 week for a sprint, 2 for an olympic or half, 3 for a
 *                    full (1 when there are fewer than 12 weeks). Of the rest
 *                    about 55 % is Base and 45 % Build, in parts of about two
 *                    easy-week rounds ("Base 1" … "Base 3", "Build 1", "Build 2").
 *   Hours .......... ordinary weeks climb evenly from his low to his high;
 *                    an easy week (every 3rd or 4th week of Base and Build)
 *                    is about a third less than the week before it; taper
 *                    weeks 60 % of the high (two: 70 % then 50 %); post-season
 *                    weeks half the low.
 *   Long sessions .. the long ride and the long run grow at most 10 % a week:
 *                    never more than 10 % above the longest one before them.
 *   Tests .......... about every 8 weeks, in an easy week of Base or Build
 *                    (the first easy week, then the easy week nearest to
 *                    8 weeks on): a swim test, a bike test and a run test.
 *   Strength ....... twice a week in Base and Build (one heavy, 30 min; one
 *                    light, 20 min); one light session in easy weeks, Peak,
 *                    the first taper week and post-season; none in race week.
 *   Mobility ....... 30 min on the days his week shape gives mobility (at most
 *                    three: Mon · Wed · Fri in his own plan).
 *   Days ........... from "My week shape": the rest day, the long ride day
 *                    (a brick run goes on it in Build and Peak), the long run
 *                    day, and the days each sport fits.
 *
 * Every session has a sport, minutes, a zone and a one-line purpose; the
 * purpose comes from the app's own "why this session" rules (SessionPurpose),
 * so the two always agree.
 */

public enum RaceDistance: String, Codable, CaseIterable, Sendable {
    case sprint, olympic, half, full

    public var title: String {
        switch self {
        case .sprint: return "Sprint"
        case .olympic: return "Olympic"
        case .half: return "Half (70.3)"
        case .full: return "Full"
        }
    }

    /* The fewest weeks from the first Monday to race week, race week included. */
    public var fewestWeeks: Int {
        switch self {
        case .sprint: return 6
        case .olympic: return 8
        case .half: return 12
        case .full: return 16
        }
    }

    /* Taper weeks before race week. */
    public var taperWeeks: Int { self == .full ? 2 : 1 }

    public var peakWeeks: Int {
        switch self {
        case .sprint: return 1
        case .olympic, .half: return 2
        case .full: return 3
        }
    }

    public var postWeeks: Int { self == .half || self == .full ? 4 : 2 }

    /* How the endurance minutes are shared: swim, bike, run. */
    var split: (swim: Double, bike: Double, run: Double) {
        switch self {
        case .sprint: return (0.25, 0.40, 0.35)
        case .olympic: return (0.22, 0.45, 0.33)
        case .half: return (0.18, 0.50, 0.32)
        case .full: return (0.16, 0.54, 0.30)
        }
    }

    /* About how long the race takes, for the race day's session. */
    public var raceMinutes: Int {
        switch self {
        case .sprint: return 75
        case .olympic: return 150
        case .half: return 330
        case .full: return 720
        }
    }

    public var longRideCap: Int {
        switch self {
        case .sprint: return 105
        case .olympic: return 150
        case .half: return 225
        case .full: return 330
        }
    }

    public var longRunCap: Int {
        switch self {
        case .sprint: return 70
        case .olympic: return 90
        case .half: return 110
        case .full: return 165
        }
    }
}

public enum PlanBlock: String, Codable, CaseIterable, Sendable {
    case base, build, peak, taper, raceWeek, postSeason

    public var title: String {
        switch self {
        case .base: return "Base"
        case .build: return "Build"
        case .peak: return "Peak"
        case .taper: return "Taper"
        case .raceWeek: return "Race week"
        case .postSeason: return "Post-season"
        }
    }
}

public struct PlanMakerSettings: Codable, Equatable, Sendable {
    public var raceName: String
    public var raceDay: String
    public var distance: RaceDistance
    /* The first day of the new plan: always a Monday. */
    public var start: String
    /* Hours a week: the lowest and the highest. */
    public var hoursLow: Double
    public var hoursHigh: Double
    /* An easy week every 3rd or every 4th week. */
    public var easyEvery: Int
    /* Tests about every this many weeks. */
    public var testEvery: Int

    public init(raceName: String = "", raceDay: String, distance: RaceDistance = .half, start: String,
                hoursLow: Double = 6, hoursHigh: Double = 10, easyEvery: Int = 4, testEvery: Int = 8) {
        self.raceName = raceName; self.raceDay = raceDay; self.distance = distance; self.start = start
        self.hoursLow = hoursLow; self.hoursHigh = hoursHigh; self.easyEvery = easyEvery; self.testEvery = testEvery
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raceName = (try? c.decodeIfPresent(String.self, forKey: .raceName)).flatMap { $0 } ?? ""
        raceDay = (try? c.decodeIfPresent(String.self, forKey: .raceDay)).flatMap { $0 } ?? ""
        distance = (try? c.decodeIfPresent(RaceDistance.self, forKey: .distance)).flatMap { $0 } ?? .half
        start = (try? c.decodeIfPresent(String.self, forKey: .start)).flatMap { $0 } ?? ""
        hoursLow = (try? c.decodeIfPresent(Double.self, forKey: .hoursLow)).flatMap { $0 } ?? 6
        hoursHigh = (try? c.decodeIfPresent(Double.self, forKey: .hoursHigh)).flatMap { $0 } ?? 10
        easyEvery = (try? c.decodeIfPresent(Int.self, forKey: .easyEvery)).flatMap { $0 } ?? 4
        testEvery = (try? c.decodeIfPresent(Int.self, forKey: .testEvery)).flatMap { $0 } ?? 8
    }

    enum CodingKeys: String, CodingKey { case raceName, raceDay, distance, start, hoursLow, hoursHigh, easyEvery, testEvery }

    /* The race's name as the plan writes it: his words, or the distance. */
    public var raceWords: String {
        let name = raceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? distance.title + " race" : name
    }
}

/* One change the rules offer on a draft (Claude may only pick from these). */
public enum PlanTweak: Codable, Equatable, Hashable, Sendable {
    case longRideDay(Int)
    case longRunDay(Int)
    /* 10 % more (true) or less (false) in one block. */
    case volume(PlanBlock, Bool)

    public var words: String {
        switch self {
        case .longRideDay(let d): return "Move the long ride to " + WeekShape.weekdayNames[min(max(d, 0), 6)]
        case .longRunDay(let d): return "Move the long run to " + WeekShape.weekdayNames[min(max(d, 0), 6)]
        case .volume(let b, let up): return "\(b.title): 10 % \(up ? "more" : "less") time each week"
        }
    }

    /* Two tweaks with the same target cannot both be taken. */
    var target: String {
        switch self {
        case .longRideDay: return "ride"
        case .longRunDay: return "run"
        case .volume(let b, _): return "volume-" + b.rawValue
        }
    }
}

public struct MadeSession: Codable, Equatable, Sendable {
    public var day: String
    public var sport: String
    public var title: String
    public var minutes: Int
    public var zone: String
    public var purpose: String
    public var key: Bool

    public init(day: String, sport: String, title: String, minutes: Int, zone: String, purpose: String = "", key: Bool = false) {
        self.day = day; self.sport = sport; self.title = title; self.minutes = minutes
        self.zone = zone; self.purpose = purpose; self.key = key
    }

    /* The session as the plan's own page for a new session holds it. */
    public var draft: SessionDraft {
        SessionDraft(dayKey: day, sport: sport, title: title, minutes: minutes > 0 ? Double(minutes) : nil,
                     intensity: zone, purpose: purpose, isKey: key)
    }
}

public struct MadeWeek: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { number }
    /* 1 … the draft's own week count. */
    public var number: Int
    public var monday: String
    public var block: PlanBlock
    /* As the plan's weeks write it: "Base 1", "Build 2", "Peak", "Taper", "Post-season". */
    public var phase: String
    public var easy: Bool
    public var test: Bool
    public var sessions: [MadeSession]
    /* The draft this week belongs to (PlanDraftMeta.id): weeks of two drafts are never shown mixed. */
    public var draft: String?

    public init(number: Int, monday: String, block: PlanBlock, phase: String, easy: Bool, test: Bool, sessions: [MadeSession]) {
        self.number = number; self.monday = monday; self.block = block; self.phase = phase
        self.easy = easy; self.test = test; self.sessions = sessions
    }

    /* Planned minutes, rest days left out (as every screen counts a week). */
    public var minutes: Int { sessions.filter { $0.sport != "rest" }.reduce(0) { $0 + $1.minutes } }
    public var training: [MadeSession] { sessions.filter { $0.sport != "rest" } }
    public func count(_ sport: String) -> Int { sessions.filter { $0.sport == sport }.count }

    /* The week's heading as the plan's own weeks carry it. */
    public var tag: String {
        if block == .raceWeek { return "RACE WEEK" }
        if test { return "RECOVERY \u{00B7} TEST WEEK" }
        if easy { return "RECOVERY WEEK" }
        return ""
    }
}

/* What the shelf keeps about the draft besides its weeks. */
public struct PlanDraftMeta: Codable, Equatable, Sendable {
    /* Each draft's own mark, written into each of its weeks too. */
    public var id: String
    public var settings: PlanMakerSettings
    public var shape: WeekShape
    public var tweaks: [PlanTweak]
    public var madeAt: Date
    public var weekCount: Int
    public var sessionCount: Int
    /* Claude's three lines, and the tweaks it picked that are not taken yet. */
    public var note: [String]
    public var offered: [PlanTweak]

    public init(id: String = String(UUID().uuidString.prefix(8)).lowercased(), settings: PlanMakerSettings, shape: WeekShape,
                tweaks: [PlanTweak] = [], madeAt: Date, weekCount: Int, sessionCount: Int, note: [String] = [], offered: [PlanTweak] = []) {
        self.id = id; self.settings = settings; self.shape = shape; self.tweaks = tweaks; self.madeAt = madeAt
        self.weekCount = weekCount; self.sessionCount = sessionCount; self.note = note; self.offered = offered
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)).flatMap { $0 } ?? ""
        settings = try c.decode(PlanMakerSettings.self, forKey: .settings)
        shape = (try? c.decodeIfPresent(WeekShape.self, forKey: .shape)).flatMap { $0 } ?? .standard
        tweaks = (try? c.decodeIfPresent([PlanTweak].self, forKey: .tweaks)).flatMap { $0 } ?? []
        madeAt = (try? c.decodeIfPresent(Date.self, forKey: .madeAt)).flatMap { $0 } ?? Date(timeIntervalSince1970: 0)
        weekCount = try c.decode(Int.self, forKey: .weekCount)
        sessionCount = (try? c.decodeIfPresent(Int.self, forKey: .sessionCount)).flatMap { $0 } ?? 0
        note = (try? c.decodeIfPresent([String].self, forKey: .note)).flatMap { $0 } ?? []
        offered = (try? c.decodeIfPresent([PlanTweak].self, forKey: .offered)).flatMap { $0 } ?? []
    }

    enum CodingKeys: String, CodingKey { case id, settings, shape, tweaks, madeAt, weekCount, sessionCount, note, offered }

    /* The weeks read from the shelf, if they are all there and all this draft's own; nil while one is missing. */
    public func complete(_ weeks: [MadeWeek?]) -> [MadeWeek]? {
        let found = weeks.compactMap { $0 }
        guard found.count == weekCount, weekCount > 0 else { return nil }
        if !id.isEmpty, found.contains(where: { $0.draft != id }) { return nil }
        let sorted = found.sorted { $0.number < $1.number }
        guard sorted.map(\.number) == Array(1...weekCount) else { return nil }
        return sorted
    }
}

public enum PlanMaker {
    /* On the shelf: the draft in several keys, so each stays well under 64 KB. */
    public static let draftPrefix = "planmaker/draft/"
    public static let metaKey = "planmaker/draft/meta"
    public static func weekKey(_ n: Int) -> String { "planmaker/draft/week/" + String(n) }
    public static let switchKey = "planmaker/switch"

    public static let mobilityMinutes = 30
    public static let heavyMinutes = 30
    public static let lightMinutes = 20
    public static let easyFactor = 0.67
    public static let longGrowth = 1.10
    public static let mostWeeks = 52

    // MARK: days

    /* The Monday on or after a day. */
    public static func monday(onOrAfter day: String) -> String {
        let m = PlanView.weekStart(day)
        return m == day ? day : PlanView.addDays(m, 7)
    }

    /* The first day a new plan starts on by default: the Monday after the current plan's last session (or after today). */
    public static func defaultStart(lastSession: String?, today: String) -> String {
        let after = max(PlanView.addDays(lastSession ?? today, 1), PlanView.addDays(today, 1))
        return monday(onOrAfter: after)
    }

    /* Weeks from the first Monday to race week, race week included. */
    public static func weekCount(start: String, raceDay: String) -> Int {
        let a = PlanView.weekStart(start), b = PlanView.weekStart(raceDay)
        return RuleBook.daysBetween(a, b) / 7 + 1
    }

    /* What stops a draft from being made, in plain words; empty when it can be made. */
    public static func problems(_ s: PlanMakerSettings, today: String) -> [String] {
        var out: [String] = []
        guard parseDayKey(s.start) != nil else { return ["Choose the first day of the new plan."] }
        guard parseDayKey(s.raceDay) != nil else { return ["Choose the race date."] }
        if s.start <= today { out.append("The first day must be after today.") }
        if s.raceDay <= s.start {
            out.append("The race must come after the first day.")
        } else {
            let n = weekCount(start: s.start, raceDay: s.raceDay)
            if n < s.distance.fewestWeeks {
                out.append("Only \(n) weeks to the race: a \(s.distance.title.lowercased()) plan needs at least \(s.distance.fewestWeeks).")
            }
            if n > mostWeeks { out.append("More than \(mostWeeks) weeks to the race: choose a later first day.") }
        }
        if !(s.hoursLow >= 3) { out.append("At least 3 hours a week.") }
        if !(s.hoursHigh >= s.hoursLow) { out.append("The high must be at least the low.") }
        if !(s.hoursHigh <= 20) { out.append("At most 20 hours a week.") }
        if s.easyEvery != 3 && s.easyEvery != 4 { out.append("An easy week every 3rd or 4th week.") }
        return out
    }

    // MARK: blocks

    /* The weeks up to race week, each with its block and the phase its week writes. */
    public static func blocks(weeks n: Int, distance: RaceDistance, easyEvery: Int) -> [(block: PlanBlock, phase: String)] {
        guard n >= 1 else { return [] }
        var taper = distance.taperWeeks
        var peak = n < 12 ? 1 : distance.peakWeeks
        var rest = n - 1 - taper - peak
        while rest < 2 && peak > 0 { peak -= 1; rest += 1 }
        while rest < 2 && taper > 0 { taper -= 1; rest += 1 }
        rest = max(rest, 0)
        let base = rest <= 1 ? rest : max(1, Int((Double(rest) * 0.55).rounded()))
        let build = rest - base
        let round = max(easyEvery, 3) * 2
        func parts(_ weeks: Int, most: Int, name: String) -> [String] {
            guard weeks > 0 else { return [] }
            let count = min(most, max(1, Int((Double(weeks) / Double(round)).rounded())))
            var out: [String] = []
            for i in 0..<count {
                let size = weeks / count + (i < weeks % count ? 1 : 0)
                out += Array(repeating: count == 1 ? name : "\(name) \(i + 1)", count: size)
            }
            return out
        }
        var out: [(PlanBlock, String)] = []
        out += parts(base, most: 3, name: "Base").map { (.base, $0) }
        out += parts(build, most: 2, name: "Build").map { (.build, $0) }
        out += Array(repeating: (PlanBlock.peak, "Peak"), count: peak)
        out += Array(repeating: (PlanBlock.taper, "Taper"), count: taper)
        // Race week sits in the taper, as the plan's own weeks write it.
        out.append((.raceWeek, "Taper"))
        return out
    }

    /* Which weeks (0-based) are easy: every `every`-th week of Base and Build. */
    static func easyWeeks(_ blocks: [PlanBlock], every: Int) -> Set<Int> {
        var out = Set<Int>()
        for i in blocks.indices where (blocks[i] == .base || blocks[i] == .build) && (i + 1) % max(every, 2) == 0 {
            out.insert(i)
        }
        return out
    }

    /* Test weeks: the first easy week, then the easy week nearest to `every` weeks on (never sooner than two weeks short of it). */
    static func testWeeks(easy: Set<Int>, every: Int) -> Set<Int> {
        let sorted = easy.sorted()
        guard var last = sorted.first else { return [] }
        var out: Set<Int> = [last]
        while true {
            let aim = last + every
            let options = sorted.filter { $0 >= aim - 2 && $0 > last }
            guard let pick = options.min(by: { abs($0 - aim) != abs($1 - aim) ? abs($0 - aim) < abs($1 - aim) : $0 > $1 }) else { break }
            out.insert(pick)
            last = pick
        }
        return out
    }

    // MARK: making the draft

    /* The shape with the tweaks' day changes laid over it. */
    public static func effectiveShape(_ shape: WeekShape, tweaks: [PlanTweak]) -> WeekShape {
        var s = shape.normalised
        for t in tweaks {
            switch t {
            case .longRideDay(let d) where d != s.rest && d != s.longRun: s.longRide = d
            case .longRunDay(let d) where d != s.rest && d != s.longRide: s.longRun = d
            default: break
            }
        }
        return s.normalised
    }

    static func volumeFactor(_ block: PlanBlock, _ tweaks: [PlanTweak]) -> Double {
        tweaks.reduce(1.0) { f, t in
            if case .volume(let b, let up) = t, b == block { return f * (up ? 1.1 : 0.9) }
            return f
        }
    }

    static func round5(_ m: Double) -> Int { max(0, Int((m / 5).rounded()) * 5) }
    static func floor5(_ m: Double) -> Int { max(0, Int((m / 5).rounded(.down)) * 5) }

    /* The week minutes the rules give each week up to race week (race week: 0, it has its own sessions). */
    static func weekMinutes(_ blocks: [PlanBlock], easy: Set<Int>, s: PlanMakerSettings, tweaks: [PlanTweak]) -> [Int] {
        let low = s.hoursLow * 60, high = s.hoursHigh * 60
        let loadWeeks = blocks.indices.filter { [.base, .build, .peak].contains(blocks[$0]) && !easy.contains($0) }
        let taperWeeks = blocks.indices.filter { blocks[$0] == .taper }
        var out = Array(repeating: 0, count: blocks.count)
        var lastLoad = low
        for (i, b) in blocks.enumerated() {
            switch b {
            case .base, .build, .peak:
                if easy.contains(i) {
                    out[i] = round5(lastLoad * easyFactor)
                } else {
                    let k = loadWeeks.firstIndex(of: i) ?? 0
                    let ramp = loadWeeks.count > 1 ? Double(k) / Double(loadWeeks.count - 1) : 1
                    let m = (low + (high - low) * ramp) * volumeFactor(b, tweaks)
                    lastLoad = m
                    out[i] = round5(m)
                }
            case .taper:
                let t = taperWeeks.firstIndex(of: i) ?? 0
                let share = taperWeeks.count == 1 ? 0.6 : (t == 0 ? 0.7 : 0.5)
                out[i] = round5(high * share)
            default:
                out[i] = 0
            }
        }
        return out
    }

    /* The whole draft: the weeks up to race week, then post-season. */
    public static func make(_ s: PlanMakerSettings, shape raw: WeekShape, tweaks: [PlanTweak] = []) -> [MadeWeek] {
        let shape = effectiveShape(raw, tweaks: tweaks)
        let start = monday(onOrAfter: s.start)
        let n = weekCount(start: start, raceDay: s.raceDay)
        guard n >= 1, n <= mostWeeks + 4 else { return [] }
        let plan = blocks(weeks: n, distance: s.distance, easyEvery: s.easyEvery)
        let kinds = plan.map(\.block)
        let easy = easyWeeks(kinds, every: s.easyEvery)
        let tests = testWeeks(easy: easy, every: max(s.testEvery, 4))
        let minutes = weekMinutes(kinds, easy: easy, s: s, tweaks: tweaks)
        let taperFirst = kinds.firstIndex(of: .taper)
        var long = LongSoFar()
        var out: [MadeWeek] = []
        for (i, (block, phase)) in plan.enumerated() {
            let monday = PlanView.addDays(start, 7 * i)
            let sessions: [MadeSession]
            if block == .raceWeek {
                sessions = raceWeek(monday: monday, s: s, shape: shape)
            } else {
                sessions = week(monday: monday, block: block, phase: phase, minutes: minutes[i], easy: easy.contains(i),
                                test: tests.contains(i), firstTaper: i == taperFirst, s: s, shape: shape, long: &long)
            }
            out.append(MadeWeek(number: i + 1, monday: monday, block: block, phase: phase,
                                easy: easy.contains(i), test: tests.contains(i), sessions: sessions))
        }
        let postMinutes = round5(s.hoursLow * 60 * 0.5)
        for j in 0..<s.distance.postWeeks {
            let monday = PlanView.addDays(start, 7 * (n + j))
            out.append(MadeWeek(number: n + j + 1, monday: monday, block: .postSeason, phase: "Post-season", easy: false, test: false,
                                sessions: postSeason(monday: monday, minutes: postMinutes, raceDay: s.raceDay, shape: shape)))
        }
        return out.map { w in
            var w = w
            w.sessions = w.sessions.map { withPurpose($0, phase: w.phase, easy: w.easy, test: w.test, raceWeek: w.block == .raceWeek) }
            return w
        }
    }

    /* The longest long ride and long run so far: the 10 % rule grows from them. */
    struct LongSoFar {
        var ride = 0
        var run = 0
    }

    /* One long session's minutes: its share, held to the distance's cap and to 10 % above the longest so far. */
    static func longMinutes(_ target: Double, least: Double, cap: Int, longest: inout Int) -> Int {
        var m = round5(min(max(target, least), Double(cap)))
        if longest > 0 {
            let limit = Double(longest) * longGrowth
            if Double(m) > limit {
                // Whole fives where a five still fits inside the 10 %; else the whole minutes that do.
                let five = floor5(limit)
                m = five > longest ? five : Int(limit.rounded(.down))
            }
        }
        longest = max(longest, m)
        return m
    }

    // MARK: one week

    /* A day-by-day plate the sessions are laid on, Monday first. */
    struct Plate {
        var days: [[MadeSession]] = Array(repeating: [], count: 7)
        let monday: String
        let shape: WeekShape

        func count(_ d: Int) -> Int { days[d].filter { $0.sport != "rest" }.count }

        /* The day for a sport: one it fits, not excluded, holding none of it yet; the emptiest, earliest first. */
        func day(for sport: String, exclude: Set<Int> = [], avoid: Set<Int> = []) -> Int {
            let fitting = (0..<7).filter { shape.fits(sport, on: $0) && !exclude.contains($0) && !days[$0].contains { $0.sport == sport } }
            let pool = fitting.isEmpty
                ? (0..<7).filter { $0 != shape.rest && !exclude.contains($0) }
                : fitting
            let all = pool.isEmpty ? (0..<7).filter { $0 != shape.rest } : pool
            return all.min {
                let a = avoid.contains($0) ? 1 : 0, b = avoid.contains($1) ? 1 : 0
                if a != b { return a < b }
                if count($0) != count($1) { return count($0) < count($1) }
                return $0 < $1
            } ?? 0
        }

        /* `n` days a sport fits, spread across the week. */
        func spread(_ sport: String, _ n: Int, exclude: Set<Int>) -> [Int] {
            let fitting = (0..<7).filter { shape.fits(sport, on: $0) && !exclude.contains($0) }
            guard n > 0 else { return [] }
            if fitting.count <= n { return fitting }
            return (0..<n).map { fitting[$0 * fitting.count / n] }
        }

        mutating func put(_ d: Int, _ sport: String, _ title: String, _ minutes: Int, _ zone: String, key: Bool = false) {
            days[d].append(MadeSession(day: PlanView.addDays(monday, d), sport: sport, title: title, minutes: minutes, zone: zone, key: key))
        }

        var sessions: [MadeSession] { days.flatMap { $0 } }
    }

    static func mobilityDays(_ shape: WeekShape) -> [Int] {
        let all = (0..<7).filter { shape.days[$0].contains("mobility") }
        guard all.count > 3 else { return all }
        return [all[0], all[all.count / 2], all[all.count - 1]]
    }

    static func week(monday: String, block: PlanBlock, phase: String, minutes total: Int, easy: Bool, test: Bool,
                     firstTaper: Bool, s: PlanMakerSettings, shape: WeekShape, long: inout LongSoFar) -> [MadeSession] {
        var plate = Plate(monday: monday, shape: shape)
        let d = s.distance
        let load = !easy && (block == .base || block == .build || block == .peak)

        plate.put(shape.rest, "rest", "Rest day \u{2014} full day off", 0, "")
        let mobility = mobilityDays(shape)
        for m in mobility { plate.put(m, "mobility", MobilityStrength.mobilityTitle, mobilityMinutes, MobilityStrength.mobilityIntensity) }

        var strength: [(heavy: Bool, minutes: Int)] = []
        switch block {
        case .base, .build: strength = easy ? [(false, lightMinutes)] : [(true, heavyMinutes), (false, lightMinutes)]
        case .peak: strength = [(false, lightMinutes)]
        case .taper: strength = firstTaper ? [(false, lightMinutes)] : []
        default: break
        }

        let fixed = mobility.count * mobilityMinutes + strength.reduce(0) { $0 + $1.minutes }
        let endurance = Double(max(60, total - fixed))
        let swim = endurance * d.split.swim, bike = endurance * d.split.bike, run = endurance * d.split.run
        let short = d == .sprint || d == .olympic

        // How many rides and runs the week has (the long one included): three when the shape gives the days, two in easy and taper weeks.
        let longDays: Set<Int> = [shape.rest, shape.longRide, shape.longRun]
        let bikeDays = (0..<7).filter { shape.fits("bike", on: $0) && !longDays.contains($0) }
        let runDays = (0..<7).filter { shape.fits("run", on: $0) && !longDays.contains($0) }
        let light = easy || block == .taper
        let rides = !light && bikeDays.count >= 2 ? 3 : 2
        let runs = !light && runDays.count >= 2 ? 3 : 2

        // The long ride (and its brick run), the long run: the biggest share of their sport.
        let rideShare = rides == 3 ? (short ? 0.5 : 0.45) : 0.55
        let ride = longMinutes(bike * rideShare, least: 45, cap: d.longRideCap, longest: &long.ride)
        let rideTitle: String
        if block == .taper { rideTitle = "Long ride, shorter: steady with a few race-pace minutes" }
        else if easy { rideTitle = "Long ride, easy week: relaxed" }
        else { rideTitle = "Long ride: steady, flat to rolling" }
        plate.put(shape.longRide, "bike", rideTitle, ride, easy ? "Z1\u{2013}Z2" : (block == .taper ? "Z2\u{2013}Z3" : "Z2"), key: load)
        var brick = 0
        if load && (block == .build || block == .peak) {
            brick = block == .peak ? 20 : 15
            plate.put(shape.longRide, "run", "Brick run off the bike", brick, "Z2\u{2013}Z3", key: true)
        }
        let runShare = runs == 3 ? (short ? 0.45 : 0.4) : 0.5
        let longRun = longMinutes(run * runShare, least: 30, cap: d.longRunCap, longest: &long.run)
        let runTitle: String
        if block == .taper { runTitle = "Long run, shorter: easy" }
        else if easy { runTitle = "Long run, easy week: relaxed" }
        else { runTitle = "Long run: easy and steady" }
        plate.put(shape.longRun, "run", runTitle, longRun, easy ? "Z1\u{2013}Z2" : "Z2", key: load)

        // The other rides: never longer than the long ride (when the 10 % rule holds it back, the week is a little shorter).
        let bikeLeft = bike - Double(ride)
        var qualityBikeDay: Int?
        let twoRides = rides == 3 && bikeLeft >= 90
        let quality = min(twoRides ? bikeLeft * 0.55 : bikeLeft, Double(ride))
        if quality >= 20 || test {
            let day = plate.day(for: "bike", exclude: longDays)
            qualityBikeDay = day
            if test {
                plate.put(day, "bike", "Test \u{2014} bike: 20 min time trial (FTP)", 60, "Test", key: true)
            } else {
                switch (block, easy) {
                case (_, true): plate.put(day, "bike", "Easy ride, easy week", max(30, round5(quality)), "Z1\u{2013}Z2")
                case (.base, _): plate.put(day, "bike", "Steady ride with cadence drills", max(30, round5(quality)), "Z2")
                case (.build, _): plate.put(day, "bike", "Sweet spot ride: 3\u{00D7}12 min", max(40, round5(quality)), "Z3\u{2013}Z4", key: true)
                case (.peak, _): plate.put(day, "bike", "Race-pace ride: 3\u{00D7}15 min at race effort", max(45, round5(quality)), "Z3", key: true)
                default: plate.put(day, "bike", "Short ride with race-pace openers", max(30, round5(quality)), "Z2\u{2013}Z4")
                }
            }
        }
        if twoRides {
            let day = plate.day(for: "bike", exclude: longDays.union(qualityBikeDay.map { [$0] } ?? []))
            plate.put(day, "bike", "Easy spin, cadence 90+", max(30, round5(min(bikeLeft * 0.45, Double(ride)))), "Z1")
        }

        // The other runs.
        let runLeft = run - Double(longRun) - Double(brick)
        let twoRuns = runs == 3 && runLeft >= 50
        let qualityRun = min(twoRuns ? runLeft * 0.55 : runLeft, Double(longRun))
        var qualityRunDay: Int?
        let beforeLongRun = (shape.longRun + 6) % 7
        if qualityRun >= 15 || test {
            let day = plate.day(for: "run", exclude: longDays.union(qualityBikeDay.map { [$0] } ?? []), avoid: [beforeLongRun])
            qualityRunDay = day
            if test {
                plate.put(day, "run", "Test \u{2014} run: 30 min time trial (threshold pulse)", 50, "Test", key: true)
            } else {
                switch (block, easy) {
                case (_, true): plate.put(day, "run", "Easy aerobic run", max(20, round5(qualityRun)), "Z2")
                case (.base, _): plate.put(day, "run", "Easy run + 6\u{00D7}20 s strides", max(25, round5(qualityRun)), "Z2")
                case (.build, _): plate.put(day, "run", "Run with 4\u{00D7}5 min at threshold", max(35, round5(qualityRun)), "Z2\u{2013}Z4", key: true)
                case (.peak, _): plate.put(day, "run", "Race-pace run: 3\u{00D7}10 min", max(40, round5(qualityRun)), "Z3", key: true)
                default: plate.put(day, "run", "Easy run with 4 strides", max(20, round5(qualityRun)), "Z2")
                }
            }
        }
        if twoRuns {
            let day = plate.day(for: "run", exclude: longDays.union(qualityRunDay.map { [$0] } ?? []), avoid: [beforeLongRun])
            plate.put(day, "run", "Easy aerobic run", max(20, round5(min(runLeft * 0.45, Double(longRun)))), "Z2")
        }

        // Swims.
        let swims = easy || block == .taper ? 2 : (swim >= 120 ? 3 : 2)
        let each = max(20, round5(swim / Double(swims)))
        let swimDays = plate.spread("swim", swims, exclude: [shape.rest])
        for (k, day) in (swimDays.isEmpty ? [plate.day(for: "swim", exclude: [shape.rest])] : swimDays).enumerated() {
            if test && k == 0 {
                plate.put(day, "swim", "Test \u{2014} swim: 400 m and 200 m timed (CSS)", 40, "Test", key: true)
                continue
            }
            switch k % 3 {
            case 0: plate.put(day, "swim", "Technique swim: drills and easy 50s", each, "Z1\u{2013}Z2")
            case 1:
                if load && (block == .build || block == .peak) {
                    plate.put(day, "swim", "Threshold swim: 100s at CSS pace", each, "Z3\u{2013}Z4")
                } else {
                    plate.put(day, "swim", "Aerobic swim: steady 200s", each, "Z2")
                }
            default: plate.put(day, "swim", "Aerobic swim: steady 200s", each, "Z2")
            }
        }

        // Strength.
        var used: Set<Int> = [shape.rest]
        let hardDays = Set([qualityBikeDay, qualityRunDay].compactMap { $0 })
        for st in strength {
            let day = plate.day(for: "strength", exclude: used, avoid: st.heavy ? hardDays.union([shape.longRide, shape.longRun]) : [])
            used.insert(day)
            if st.heavy {
                plate.put(day, "strength", "Strength A: squat, hinge, press, row", st.minutes, "RPE 7\u{2013}8")
            } else {
                plate.put(day, "strength", "Strength B: light circuit and core", st.minutes, "RPE 5")
            }
        }
        return plate.sessions
    }

    /* Race week: short and sharp, counted back from the race day; nothing hard. */
    static func raceWeek(monday: String, s: PlanMakerSettings, shape: WeekShape) -> [MadeSession] {
        let race = s.raceDay
        var out: [MadeSession] = []
        func add(_ back: Int, _ sport: String, _ title: String, _ minutes: Int, _ zone: String, key: Bool = false) {
            let day = PlanView.addDays(race, back)
            guard day >= monday, day <= PlanView.addDays(monday, 6) else { return }
            out.append(MadeSession(day: day, sport: sport, title: title, minutes: minutes, zone: zone, key: key))
        }
        add(-6, "mobility", MobilityStrength.mobilityTitle, mobilityMinutes, MobilityStrength.mobilityIntensity)
        add(-5, "swim", "Easy swim with 4\u{00D7}50 m at race pace", 25, "Z2\u{2013}Z3")
        add(-4, "bike", "Short ride with 3\u{00D7}2 min at race effort", 40, "Z2\u{2013}Z3")
        add(-3, "run", "Easy run with 4 strides", 20, "Z2")
        add(-2, "rest", "Rest day \u{2014} full day off", 0, "")
        add(-1, "bike", "Shake-out: 15 min easy spin and a 10 min jog", 25, "Z1\u{2013}Z2")
        add(0, "race", "Race \u{2014} " + s.raceWords, s.distance.raceMinutes, "Race day", key: true)
        add(1, "rest", "Rest day \u{2014} recover from the race", 0, "")
        return out.sorted { $0.day < $1.day }
    }

    /* After the race: easy, for fun, no numbers. */
    static func postSeason(monday: String, minutes: Int, raceDay: String, shape: WeekShape) -> [MadeSession] {
        var plate = Plate(monday: monday, shape: shape)
        plate.put(shape.rest, "rest", "Rest day \u{2014} full day off", 0, "")
        for m in mobilityDays(shape) { plate.put(m, "mobility", MobilityStrength.mobilityTitle, mobilityMinutes, MobilityStrength.mobilityIntensity) }
        let longDays: Set<Int> = [shape.rest, shape.longRide, shape.longRun]
        plate.put(shape.longRide, "bike", "Easy ride for fun", max(45, round5(Double(minutes) * 0.4)), "Z1\u{2013}Z2")
        plate.put(shape.longRun, "run", "Easy run, no watch", max(25, round5(Double(minutes) * 0.2)), "Z1\u{2013}Z2")
        plate.put(plate.day(for: "swim", exclude: longDays), "swim", "Easy swim, no watch", max(20, round5(Double(minutes) * 0.2)), "Z1\u{2013}Z2")
        plate.put(plate.day(for: "strength", exclude: [shape.rest]), "strength", "Strength B: light circuit and core", lightMinutes, "RPE 5")
        return plate.sessions
    }

    // MARK: the one-line purpose

    /* The session's purpose, from the app's own "why this session" rules; rest days have their own words. */
    static func withPurpose(_ m: MadeSession, phase: String, easy: Bool, test: Bool, raceWeek: Bool) -> MadeSession {
        var m = m
        if m.sport == "rest" {
            m.purpose = m.title.contains("race") ? "Recovery after the race" : "Your body adapts while you rest"
            return m
        }
        let tag: RBWeekTag? = raceWeek ? .race : (test ? .test : (easy ? .easy : nil))
        let input = PurposeInput(sport: m.sport, title: m.title, intensity: m.zone, plannedMin: m.minutes,
                                 phase: phase, isKey: m.key, typicalMin: nil, weekTag: tag)
        m.purpose = SessionPurpose.kind(input).map(purposeWords) ?? "Keeps you moving"
        return m
    }

    /* A short purpose in the plan's own style ("Aerobic base", "Time in the saddle"). */
    public static func purposeWords(_ kind: PurposeKind) -> String {
        switch kind {
        case .race: return "Race day"
        case .test: return "Fresh numbers for your zones"
        case .rehearsal: return "Race rehearsal"
        case .postSeason: return "Moving for fun, no numbers"
        case .taperSharpener: return "Keeps you sharp"
        case .taperEasy: return "Fresh for race day"
        case .brick: return "Running on tired legs"
        case .easyWeek: return "Easy week: soak up the work"
        case .strengthHeavy: return "Strength and sturdiness"
        case .strengthLight: return "Keeps you sturdy"
        case .mobility: return "Supple joints, easier recovery"
        case .swimTechnique: return "Stroke before volume"
        case .swimThreshold: return "Holding a fast pace for longer"
        case .swimAerobic: return "Aerobic base in the water"
        case .longEndurance: return "Long and easy: aerobic base"
        case .vo2: return "Top-end effort"
        case .peakQuality: return "Sharpens your race effort"
        case .tempo: return "Steady, comfortably hard"
        case .threshold: return "Raises your threshold"
        case .recovery: return "Legs turning, nothing more"
        case .easyAerobic: return "Aerobic base"
        }
    }

    // MARK: what the rules offer to change

    /*
     * The tweaks the rules allow on a draft: the long ride or the long run to
     * another day (not the rest day, not the other long day), and 10 % more or
     * less in Base, Build or Peak (one of each block at most).
     */
    public static func menu(settings: PlanMakerSettings, shape: WeekShape, tweaks: [PlanTweak], weeks: [MadeWeek]) -> [PlanTweak] {
        let s = effectiveShape(shape, tweaks: tweaks)
        var out: [PlanTweak] = []
        for d in 0..<7 where d != s.longRide && d != s.rest && d != s.longRun { out.append(.longRideDay(d)) }
        for d in 0..<7 where d != s.longRun && d != s.rest && d != s.longRide { out.append(.longRunDay(d)) }
        let present = Set(weeks.map(\.block))
        for b in [PlanBlock.base, .build, .peak] where present.contains(b) {
            guard !tweaks.contains(where: { $0.target == "volume-" + b.rawValue }) else { continue }
            out.append(.volume(b, true))
            out.append(.volume(b, false))
        }
        return out
    }

    /* A tweak taken: the long-day moves replace an earlier one of the same kind; a block's volume only once. */
    public static func adding(_ t: PlanTweak, to tweaks: [PlanTweak]) -> [PlanTweak] {
        switch t {
        case .longRideDay, .longRunDay: return tweaks.filter { $0.target != t.target } + [t]
        case .volume: return tweaks.contains { $0.target == t.target } ? tweaks : tweaks + [t]
        }
    }

    // MARK: the season, in short

    public struct BlockSpan: Equatable, Sendable {
        public let block: PlanBlock
        public let weeks: Int
        public let first: String
        public let minLow: Int
        public let minHigh: Int
    }

    /* The blocks in order with their weeks and the lowest and highest week (race week by itself). */
    public static func spans(_ weeks: [MadeWeek]) -> [BlockSpan] {
        var out: [BlockSpan] = []
        for w in weeks {
            if let last = out.last, last.block == w.block {
                out[out.count - 1] = BlockSpan(block: last.block, weeks: last.weeks + 1, first: last.first,
                                               minLow: min(last.minLow, w.minutes), minHigh: max(last.minHigh, w.minutes))
            } else {
                out.append(BlockSpan(block: w.block, weeks: 1, first: w.monday, minLow: w.minutes, minHigh: w.minutes))
            }
        }
        return out
    }
}
