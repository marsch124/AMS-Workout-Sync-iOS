import Foundation

/*
 * "My week shape" (round 30, pick 5): he says once which sports fit which
 * weekday, the long ride day, the long run day and the rest day — and every
 * future week can be laid out that way, and the plan maker uses it.
 *
 * Kept on the shelf under "weekshape". Weekdays are 0 (Monday) … 6 (Sunday).
 *
 * The lay-out rule (`LayOut`) only says what would move, so a page can show
 * it first; `apply` writes the moves as ordinary changes with one reason line
 * (" #<batch>" after it) and `undo` takes the whole lot back in one go.
 */
public struct WeekShape: Codable, Equatable, Sendable {
    /* The sports a weekday can hold, in this order on every page. */
    public static let sports = ["swim", "bike", "run", "strength", "mobility"]

    /* Monday first: the sports that fit each weekday. */
    public var days: [[String]]
    public var longRide: Int
    public var longRun: Int
    public var rest: Int

    public init(days: [[String]], longRide: Int, longRun: Int, rest: Int) {
        self.days = days; self.longRide = longRide; self.longRun = longRun; self.rest = rest
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? c.decodeIfPresent([[String]].self, forKey: .days)).flatMap { $0 } ?? WeekShape.standard.days
        longRide = (try? c.decodeIfPresent(Int.self, forKey: .longRide)).flatMap { $0 } ?? WeekShape.standard.longRide
        longRun = (try? c.decodeIfPresent(Int.self, forKey: .longRun)).flatMap { $0 } ?? WeekShape.standard.longRun
        rest = (try? c.decodeIfPresent(Int.self, forKey: .rest)).flatMap { $0 } ?? WeekShape.standard.rest
        self = normalised
    }

    enum CodingKeys: String, CodingKey { case days, longRide, longRun, rest }

    /* An invented, ordinary triathlon week: the start when there is no plan to learn from. */
    public static let standard = WeekShape(days: [
        ["swim", "mobility"],            // Mon
        ["bike", "strength"],            // Tue
        ["run", "mobility"],             // Wed
        ["swim", "run", "strength"],     // Thu
        ["mobility"],                    // Fri: the rest day
        ["bike", "run"],                 // Sat: the long ride
        ["swim", "run"],                 // Sun: the long run
    ], longRide: 5, longRun: 6, rest: 4)

    public static let shelfKey = "weekshape"

    /*
     * Always seven days, only known sports, the days in range; the long ride
     * day holds a ride, the long run day a run, and the rest day nothing but
     * mobility.
     */
    public var normalised: WeekShape {
        var d = Array(days.prefix(7))
        while d.count < 7 { d.append([]) }
        d = d.map { list in WeekShape.sports.filter { list.contains($0) } }
        func day(_ i: Int, _ fallback: Int) -> Int { (0...6).contains(i) ? i : fallback }
        let ride = day(longRide, WeekShape.standard.longRide)
        let run = day(longRun, WeekShape.standard.longRun)
        let off = day(rest, WeekShape.standard.rest)
        if off != ride, !d[ride].contains("bike") { d[ride] = WeekShape.sports.filter { d[ride].contains($0) || $0 == "bike" } }
        if off != run, !d[run].contains("run") { d[run] = WeekShape.sports.filter { d[run].contains($0) || $0 == "run" } }
        d[off] = d[off].filter { $0 == "mobility" }
        return WeekShape(days: d, longRide: ride, longRun: run, rest: off)
    }

    /* Whether a sport fits a weekday. A brick is a ride first; anything else fits any day but the rest day. */
    public func fits(_ sport: String, on weekday: Int) -> Bool {
        guard (0...6).contains(weekday) else { return false }
        switch sport {
        case "rest": return weekday == rest
        case "brick": return weekday != rest && days[weekday].contains("bike")
        case "swim", "bike", "run", "strength", "mobility": return days[weekday].contains(sport)
        default: return weekday != rest
        }
    }

    /* What stops the shape from being saved, in plain words; empty when it can be saved. */
    public var problems: [String] {
        var out: [String] = []
        if longRide == longRun { out.append("The long ride and the long run are on the same day.") }
        if rest == longRide { out.append("The rest day is the long ride day.") }
        if rest == longRun { out.append("The rest day is the long run day.") }
        for sport in ["swim", "bike", "run"] where !(0...6).contains(where: { days[$0].contains(sport) && $0 != rest }) {
            out.append("No day for a \(WeekShape.word(sport)).")
        }
        return out
    }

    public static func word(_ sport: String) -> String {
        switch sport {
        case "swim": return "swim"
        case "bike": return "ride"
        case "run": return "run"
        case "strength": return "strength session"
        case "mobility": return "mobility session"
        case "brick": return "brick"
        case "rest": return "rest day"
        case "race": return "race"
        default: return "session"
        }
    }

    public static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    public static let weekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /* Monday 0 … Sunday 6. */
    public static func weekday(_ day: String) -> Int { RuleBook.weekday(day) }

    // MARK: learned from the plan

    /*
     * The shape his plan already has, as the page's starting point: a sport
     * fits a weekday when it falls there in at least two weeks out of five;
     * the long ride and long run days are where each week's longest ride and
     * run fall most often; the rest day is where the plan's rest days fall
     * most often (else the day with the fewest sessions).
     */
    public static func learned(from sessions: [Workout], mapping: Mapping) -> WeekShape {
        let byWeek = Dictionary(grouping: sessions, by: { PlanView.weekStart($0.dayKey) })
        guard byWeek.count >= 2 else { return standard }
        let weeks = Double(byWeek.count)
        var counts = Array(repeating: [String: Int](), count: 7)
        var rideDays = Array(repeating: 0, count: 7), runDays = Array(repeating: 0, count: 7)
        var restDays = Array(repeating: 0, count: 7), busy = Array(repeating: 0, count: 7)
        func minutes(_ w: Workout) -> Double { (Plan.plannedSeconds(w, mapping) ?? 0) / 60 }
        for (_, list) in byWeek {
            var seen = Array(repeating: Set<String>(), count: 7)
            for w in list {
                let d = weekday(w.dayKey)
                let sport = w.discipline.id == "brick" ? "bike" : w.discipline.id
                if sport == "rest" { restDays[d] += 1; continue }
                busy[d] += 1
                if sports.contains(sport) { seen[d].insert(sport) }
            }
            for d in 0..<7 { for s in seen[d] { counts[d][s, default: 0] += 1 } }
            if let ride = list.filter({ $0.discipline.id == "bike" }).max(by: { minutes($0) < minutes($1) }), minutes(ride) > 0 {
                rideDays[weekday(ride.dayKey)] += 1
            }
            if let run = list.filter({ $0.discipline.id == "run" }).max(by: { minutes($0) < minutes($1) }), minutes(run) > 0 {
                runDays[weekday(run.dayKey)] += 1
            }
        }
        let days = (0..<7).map { d in sports.filter { Double(counts[d][$0] ?? 0) >= weeks * 0.4 } }
        func most(_ list: [Int], fallback: Int) -> Int {
            guard let top = list.max(), top > 0 else { return fallback }
            return list.firstIndex(of: top) ?? fallback
        }
        let restDay = (restDays.max() ?? 0) > 0 ? most(restDays, fallback: standard.rest)
            : (busy.firstIndex(of: busy.min() ?? 0) ?? standard.rest)
        var ride = most(rideDays, fallback: standard.longRide)
        var run = most(runDays, fallback: standard.longRun)
        if run == ride { run = (0..<7).filter { $0 != ride && $0 != restDay }.max { runDays[$0] < runDays[$1] } ?? standard.longRun }
        if ride == restDay { ride = (0..<7).first { $0 != restDay && $0 != run } ?? standard.longRide }
        var shape = WeekShape(days: days, longRide: ride, longRun: run, rest: restDay).normalised
        if !shape.problems.isEmpty { shape = standard }
        return shape
    }
}

// MARK: - laying the coming weeks out

/*
 * "Lay out my coming weeks this way": each coming week's sessions go to the
 * days the shape gives them, inside their own week.
 *
 *   Moved ........ a session after today, not logged, missed or waiting, in an
 *                  ordinary week (not an easy, test or race week), not in the
 *                  away period. Never a test, a race or a race rehearsal.
 *   Where ........ the rest day to the rest day, the week's long ride to the
 *                  long ride day (a brick run on its day goes with it), the
 *                  long run to the long run day, every other session to the
 *                  nearest day that fits its sport and holds no other session
 *                  of that sport. A session whose day already fits stays.
 *   Never ........ onto today or a day before it, onto a day in the away
 *                  period, out of its own week. No fitting day: it stays.
 */
public enum LayOut {
    public static let why = "Laid out to my week shape"
    public static func why(batch: String = String(UUID().uuidString.prefix(8))) -> String { why + " #" + batch }
    public static func isOurs(_ why: String) -> Bool { why.hasPrefix(Self.why + " #") }
    public static func batch(of why: String) -> String? {
        guard isOurs(why), let r = why.range(of: " #", options: .backwards) else { return nil }
        return String(why[r.upperBound...])
    }

    public struct Move: Equatable, Sendable {
        public let key: String
        public let sport: String
        public let from: String
        public let to: String
        public init(key: String, sport: String, from: String, to: String) {
            self.key = key; self.sport = sport; self.from = from; self.to = to
        }
        /* "Tue swim → Mon". */
        public var words: String {
            WeekShape.weekdayShort[WeekShape.weekday(from)] + " " + WeekShape.word(sport) + " \u{2192} "
                + WeekShape.weekdayShort[WeekShape.weekday(to)]
        }
    }

    public struct Week: Equatable, Sendable {
        public let monday: String
        public let moves: [Move]
    }

    public struct Change: Equatable, Sendable {
        public var weeks: [Week] = []
        public init() {}
        public var moves: [Move] { weeks.flatMap(\.moves) }
        public var isEmpty: Bool { weeks.isEmpty }
    }

    static func untouchable(_ s: Workout) -> Bool { MobilityStrength.untouchable(s) }

    /* Tests, races and race rehearsals keep their day, always. */
    public static func isProtected(_ s: Workout) -> Bool {
        if untouchable(s) { return true }
        let rb = RBSession(id: s.key, day: s.dayKey, sport: RBSport(disciplineID: s.discipline.id), title: s.title,
                           plannedMin: 0, intensity: s.planned.intensity, star: s.isKey, phase: s.phase, originalWeek: 0)
        return RuleBook.labels(rb).protectedKind
    }

    static func minutes(_ s: Workout, _ mapping: Mapping) -> Double { (Plan.plannedSeconds(s, mapping) ?? 0) / 60 }

    static func isLong(_ s: Workout, sport: String) -> Bool {
        let t = s.title.trimmingCharacters(in: .whitespaces).lowercased()
        let words = sport == "bike" ? ["long ride", "reduced long ride"] : ["long run", "reduced long run"]
        return words.contains { t.hasPrefix($0) }
    }

    /* The week's long session of a sport: one its title calls long, else its longest when clearly the longest. */
    static func longOne(_ list: [Workout], sport: String, mapping: Mapping) -> Workout? {
        let mine = list.filter { $0.discipline.id == sport }
        if let named = mine.first(where: { isLong($0, sport: sport) }) { return named }
        let sorted = mine.sorted { minutes($0, mapping) > minutes($1, mapping) }
        guard let top = sorted.first else { return nil }
        let floor: Double = sport == "bike" ? 75 : 60
        let m = minutes(top, mapping)
        guard m >= floor else { return nil }
        if sorted.count > 1, m < minutes(sorted[1], mapping) * 1.25 { return nil }
        return top
    }

    static func isSpecialWeek(_ w: PlanWeek?) -> Bool {
        guard let w else { return false }
        return w.isEasy || w.isTest || normalise(w.tag).contains("race")
    }

    public static func plan(sessions: [Workout], weeks: [PlanWeek], shape raw: WeekShape, mapping: Mapping,
                            today: String, away: AwayPeriod? = nil) -> Change {
        let shape = raw.normalised
        var out = Change()
        let future = sessions.filter { $0.dayKey > today }
        let mondays = Set(future.map { PlanView.weekStart($0.dayKey) }).sorted()
        let weekOf = Dictionary(weeks.map { (PlanView.weekStart($0.monday), $0) }, uniquingKeysWith: { a, _ in a })
        for monday in mondays {
            if isSpecialWeek(weekOf[monday]) { continue }
            let days = (0..<7).map { PlanView.addDays(monday, $0) }
            let inWeek = sessions.filter { days.contains($0.dayKey) }
            // A race anywhere in the week keeps the whole week as it is.
            if inWeek.contains(where: { $0.discipline.id == "race" }) { continue }
            func open(_ day: String) -> Bool { day > today && !(away?.contains(day) ?? false) }
            let movable = inWeek.filter { open($0.dayKey) && !isProtected($0) }
            guard !movable.isEmpty else { continue }
            let movableKeys = Set(movable.map(\.key))

            // What the days already hold for good.
            var holds = Array(repeating: [String](), count: 7)
            var count = Array(repeating: 0, count: 7)
            for s in inWeek where !movableKeys.contains(s.key) {
                let d = WeekShape.weekday(s.dayKey)
                holds[d].append(s.discipline.id)
                if s.discipline.id != "rest" { count[d] += 1 }
            }

            let ride = longOne(movable, sport: "bike", mapping: mapping)
            let run = longOne(movable, sport: "run", mapping: mapping)
            let rideDay = ride.map(\.dayKey)
            // A brick run on the long ride's own day goes with it.
            let brick = movable.first { s in
                s.key != run?.key && s.dayKey == rideDay
                    && (s.discipline.id == "brick" || s.title.lowercased().hasPrefix("brick run"))
            }
            func priority(_ s: Workout) -> Int {
                if s.discipline.id == "rest" { return 0 }
                if s.key == ride?.key { return 1 }
                if s.key == brick?.key { return 2 }
                if s.key == run?.key { return 3 }
                return 4 + (["bike": 0, "run": 1, "swim": 2, "brick": 3, "strength": 4, "mobility": 5][s.discipline.id] ?? 6)
            }
            let ordered = movable.sorted {
                let a = priority($0), b = priority($1)
                if a != b { return a < b }
                let x = minutes($0, mapping), y = minutes($1, mapping)
                if x != y { return x > y }
                return $0.key < $1.key
            }

            var moves: [Move] = []
            var rideTarget: Int?
            for s in ordered {
                let sport = s.discipline.id
                let here = WeekShape.weekday(s.dayKey)
                func fits(_ d: Int) -> Bool {
                    guard open(days[d]) else { return false }
                    if s.key == ride?.key { return d == shape.longRide }
                    if s.key == run?.key { return d == shape.longRun }
                    if s.key == brick?.key { return d == (rideTarget ?? here) }
                    if sport == "rest" { return d == shape.rest }
                    guard shape.fits(sport, on: d) else { return false }
                    // One session of a sport a day; the long days keep their own sport to themselves.
                    if holds[d].contains(sport) { return false }
                    if (sport == "bike" || sport == "brick"), d == shape.longRide, ride != nil { return false }
                    if sport == "run", d == shape.longRun, run != nil { return false }
                    return true
                }
                var target = here
                if !fits(here) {
                    let candidates = (0..<7).filter(fits)
                    if let best = candidates.min(by: {
                        let a = abs($0 - here), b = abs($1 - here)
                        if a != b { return a < b }
                        if count[$0] != count[$1] { return count[$0] < count[$1] }
                        return $0 < $1
                    }) { target = best }
                }
                if s.key == ride?.key { rideTarget = target }
                holds[target].append(sport)
                if sport != "rest" { count[target] += 1 }
                if target != here { moves.append(Move(key: s.key, sport: sport, from: s.dayKey, to: days[target])) }
            }
            if !moves.isEmpty {
                out.weeks.append(Week(monday: monday, moves: moves.sorted { ($0.from, $0.key) < ($1.from, $1.key) }))
            }
        }
        return out
    }

    /* Writes the moves into the book, all of them or none: each the same change the week board's drag makes. Returns the changes' ids. */
    @discardableResult
    public static func apply(_ c: Change, to book: inout PlanBook, why: String = LayOut.why(), now: Date = Date()) throws -> [String] {
        var copy = book
        var ids: [String] = []
        for m in c.moves {
            guard let was = copy.session(m.key), var d = copy.draft(of: m.key) else { throw BookError.noSession(m.key) }
            guard !untouchable(was) else { continue }
            d.dayKey = m.to
            if let change = try copy.change(m.key, to: d, why: why, now: now) {
                ids.append(change.id)
                let from = copy.moves[was.key]?.from ?? was.dayKey
                copy.moves[was.key] = MoveRecord(from: from, to: m.to, disciplineId: was.discipline.id, at: now)
            }
        }
        book = copy
        return ids
    }

    /* The changes one Undo takes back: not undone, still the newest change to their session, nothing logged on it since. */
    public static func undoable(_ changes: [PlanChange], book: PlanBook) -> [PlanChange] {
        changes.filter { c in
            guard isOurs(c.why), !c.undone, book.canUndo(c.id), let s = book.session(c.key) else { return false }
            return !untouchable(s)
        }
    }

    /* The newest lay-out still standing in the book, if any: its batch and its changes. */
    public static func latest(in book: PlanBook) -> (batch: String, changes: [PlanChange])? {
        guard let last = book.changes.last(where: { isOurs($0.why) && !$0.undone }), let batch = batch(of: last.why) else { return nil }
        return (batch, book.changes.filter { self.batch(of: $0.why) == batch })
    }

    /* Undo a whole lay-out, newest first, all or none. Returns how many were taken back. */
    @discardableResult
    public static func undo(batch: String, in book: inout PlanBook, now: Date = Date()) throws -> Int {
        let list = undoable(book.changes.filter { self.batch(of: $0.why) == batch }, book: book)
        var copy = book
        for c in list.reversed() { try copy.undo(c.id, now: now) }
        book = copy
        return list.count
    }
}
