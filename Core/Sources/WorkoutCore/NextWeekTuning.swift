import Foundation

/*
 * Next week, tuned (round 30, his pick 2): "Every Sunday, next week's minutes
 * adjusted from how this week went. One card, you tap Take it."
 *
 * On Sunday (and on Monday until he answers) the rule book reads the week
 * that is ending — sessions done and missed, how hard each felt (1–10), the
 * morning "How do you feel?" (1–5) and Garmin's load (7 days against 28) —
 * and offers at most three changes to next week, each one line. Never sleep:
 * sleep is shown only.
 *
 * The only moves: shorten a session by 10–20 % (M3), make an interval
 * session easy (M4), and lengthen by at most 10 % — only when every session
 * was done, the efforts were moderate, the mornings were fine and the load
 * is not "Overreaching". Never a test, a race simulation, the race, race week
 * or a done session; never a moved day; never more than +10 % for the whole
 * week; a missed session is not made up. Each choice goes through the rule
 * book's own limits (L1, L2, L4, L5, L6, L8, L10) as well.
 *
 * Built-in Claude may only pick one of these choices and word the reason,
 * exactly like the daily suggestion card. Pure: no clock, no files, no network.
 */
public enum NextWeekTune {

    // MARK: the numbers (judgement, may be tuned)

    /* The gentle cut and the firmer one, in percent of the session. Every cut stays within 10–20 %. */
    public static let mildPercent = 10
    public static let firmPercent = 20
    /* The most a session, and the whole week, may grow. */
    public static let growPercent = 10
    public static let weekGrowth = 0.10
    /* At most this many changes on the card. */
    public static let maxChanges = 3
    /* Sessions that felt hard, poor mornings and missed sessions that count as a sign. */
    public static let hardSessions = 2
    public static let poorMornings = 2
    public static let missedSessions = 3
    /* Lengthening needs at least this many effort answers and morning answers in the week. */
    public static let ratedNeeded = 2
    public static let morningsNeeded = 3
    /* Sunday: the card shows once Sunday's sessions are all logged or marked missed, or from this hour. */
    public static let sundayHour = 17

    public static let title = "Next week, tuned"
    public static let staysLine = "Next week stays as planned"
    public static let whyPrefixForPlan = "Suggestion: next week, tuned: "

    // MARK: what the week said

    public struct Signals: Equatable, Sendable {
        /* Done sessions that felt harder than planned (spec 3.5). */
        public var feltHard = 0
        /* Mornings answered 1 or 2. */
        public var poorMornings = 0
        public var answeredMornings = 0
        /* Garmin's 7 days against 28 says "Overreaching". */
        public var overreaching = false
        /* Marked missed, or still not logged on a day already past. */
        public var missed = 0
        /* Still open (not logged), today's included. */
        public var open = 0
        public var done = 0
        /* Done sessions with a "how hard" answer, and whether every one was moderate (at most 1 above the plan's own effort). */
        public var rated = 0
        public var moderate = true
        public init() {}

        /* The signs of a hard week, each counted once. */
        public var tiredSigns: Int {
            (feltHard >= NextWeekTune.hardSessions ? 1 : 0) + (poorMornings >= NextWeekTune.poorMornings ? 1 : 0) + (overreaching ? 1 : 0)
        }
    }

    public enum Kind: String, Codable, Equatable, Sendable {
        /* One sign of a hard week: shorter. */ case ease
        /* Two or more (or three hard sessions): an interval session easy and shorter. */ case easeMore
        /* Three or more sessions missed: next week eases back in. */ case missed
        /* Everything done, moderate and fine: a little longer. */ case lengthen
        /* Nothing needs changing. */ case stays
    }

    /* One way to tune the week: its moves and one line for each. */
    public struct Choice: Codable, Equatable, Sendable {
        public let moves: [Move]
        public let lines: [String]
        public init(moves: [Move], lines: [String]) { self.moves = moves; self.lines = lines }
    }

    public struct Card: Codable, Equatable, Sendable {
        /* The Monday of the week it changes. */
        public let monday: String
        public let kind: Kind
        /* The card's own choice first; the others only for Claude's menu. Empty: "Next week stays as planned". */
        public let choices: [Choice]
        /* "Why: three sessions felt hard this week." */
        public let why: String
        /* The sessions the choices touch, exactly as they were when the card was made. */
        public let before: [RBSession]
        public let claudePicked: Bool

        public init(monday: String, kind: Kind, choices: [Choice], why: String, before: [RBSession], claudePicked: Bool = false) {
            self.monday = monday; self.kind = kind; self.choices = choices; self.why = why; self.before = before
            self.claudePicked = claudePicked
        }

        public var stays: Bool { choices.isEmpty }
        public var lines: [String] { choices.first?.lines ?? [] }
        public var moves: [Move] { choices.first?.moves ?? [] }
        /* The menu as Claude was shown it: each choice's lines. */
        public var menu: [[String]] { choices.map(\.lines) }
    }

    // MARK: when it shows

    /*
     * Next week's Monday while the card may show, else nil: on Sunday once its
     * sessions are all logged or marked missed (`sundaySettled`), or from 17:00;
     * all of Monday (for the week that has just begun).
     */
    public static func anchor(today: String, hour: Int, sundaySettled: Bool) -> String? {
        switch RuleBook.weekday(today) {
        case 6: return sundaySettled || hour >= sundayHour ? PlanView.addDays(today, 1) : nil
        case 0: return today
        default: return nil
        }
    }

    // MARK: reading the week

    /* The week that ends the day before `monday`, as far as it is known on `input.today`. */
    public static func signals(_ input: RuleBookInput, monday: String, loadRatio: Double?) -> Signals {
        let first = PlanView.addDays(monday, -7), last = PlanView.addDays(monday, -1)
        let week = input.sessions.filter { $0.day >= first && $0.day <= last && $0.counts && $0.day <= input.today }
        var s = Signals()
        s.feltHard = week.filter { RuleBook.feltHarder($0, today: input.today, margin: input.settings.feltHarderMargin) }.count
        let days = (0..<7).map { PlanView.addDays(first, $0) }.filter { $0 <= input.today }
        let answers = days.compactMap { input.feel.answer(on: $0) }
        s.answeredMornings = answers.count
        s.poorMornings = answers.filter { $0.rawValue <= 2 }.count
        s.overreaching = BodyLoad.isDanger(loadRatio)
        s.missed = week.filter { $0.status == .missed || ($0.status == .open && $0.day < input.today) }.count
        s.open = week.filter { $0.status == .open }.count
        s.done = week.filter { $0.status == .done }.count
        let rated = week.filter { $0.status == .done }.compactMap { x -> (Int, Int)? in
            guard let r = x.rpe, let e = RuleBook.expectedEffort(x) else { return nil }
            return (r, e)
        }
        s.rated = rated.count
        s.moderate = rated.allSatisfy { $0.0 <= $0.1 + 1 }
        return s
    }

    /* May next week grow a little? Every session done, efforts moderate, mornings fine, load not "Overreaching". */
    public static func mayLengthen(_ s: Signals) -> Bool {
        s.tiredSigns == 0 && s.missed == 0 && s.open == 0 && s.done > 0
            && s.rated >= ratedNeeded && s.moderate
            && s.answeredMornings >= morningsNeeded && s.poorMornings == 0 && !s.overreaching
    }

    // MARK: the card

    /*
     * The card for the week starting `monday`, or nil when there is nothing to
     * say at all (a pause or the illness steps are on, race week, no plan for
     * that week). A card with no choices says "Next week stays as planned".
     */
    public static func card(_ input: RuleBookInput, monday: String, loadRatio: Double?) -> Card? {
        guard RuleBook.weekday(monday) == 0, RuleBook.ladderStep(input).step == .none else { return nil }
        let week = input.week(of: monday)
        guard week != input.settings.raceWeek, input.tag(week) != .race else { return nil }
        let days = Set((0..<7).map { PlanView.addDays(monday, $0) })
        guard input.sessions.contains(where: { days.contains($0.day) && $0.counts }) else { return nil }

        let s = signals(input, monday: monday, loadRatio: loadRatio)
        let pool = candidates(input, days: days)
        var wanted: [Choice] = []
        var kind = Kind.stays
        if s.tiredSigns >= 2 || s.feltHard >= 3 {
            kind = .easeMore
            let interval = intervalSession(pool)
            if let interval {
                let first = easier(interval)
                wanted.append(join(first, shortened(pool, percent: firmPercent, count: maxChanges - 1, without: [interval.id])))
            }
            wanted.append(shortened(pool, percent: firmPercent, count: maxChanges, without: []))
            wanted.append(shortened(pool, percent: mildPercent, count: 2, without: []))
        } else if s.tiredSigns == 1 {
            kind = .ease
            wanted.append(shortened(pool, percent: mildPercent, count: 2, without: []))
            if let interval = intervalSession(pool) { wanted.append(easier(interval)) }
            wanted.append(shortened(pool, percent: firmPercent, count: 2, without: []))
        } else if s.missed >= missedSessions {
            kind = .missed
            wanted.append(shortened(pool, percent: mildPercent, count: 2, without: []))
            wanted.append(shortened(pool, percent: mildPercent, count: 1, without: []))
        } else if mayLengthen(s), input.tag(week) == .load, !input.isTaper(week) {
            kind = .lengthen
            let longs = [RBSlot.longRide, .longRun].compactMap { slot in pool.first { $0.slot == slot } }
            let each = longs.compactMap(longer)
            if each.count == 2 { wanted.append(join(each[0], each[1])) }
            wanted.append(contentsOf: each)
        }

        var passed: [Choice] = []
        for c in wanted where !c.moves.isEmpty && c.moves.count <= maxChanges && !passed.contains(where: { $0.moves == c.moves }) {
            if failures(c.moves, input: input, monday: monday).isEmpty { passed.append(c) }
            if passed.count == 3 { break }
        }
        guard !passed.isEmpty else {
            return Card(monday: monday, kind: .stays, choices: [], why: "", before: [])
        }
        let why = whyLine(kind, s)
        guard RuleBook.l13Words(passed.flatMap(\.lines) + [why]) == nil else {
            return Card(monday: monday, kind: .stays, choices: [], why: "", before: [])
        }
        let ids = Set(passed.flatMap { $0.moves.flatMap(\.sessionIDs) })
        let before = input.sessions.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
        return Card(monday: monday, kind: kind, choices: passed, why: why, before: before)
    }

    /*
     * Next week's sessions a tuning may touch, in his guide's drop order (B8),
     * then by day: open, swim / bike / run only, never a test, a simulation, the
     * race or race week, never on an easy stretch after illness or a pause,
     * never one a taken suggestion changed in the last 7 days (L11).
     */
    static func candidates(_ input: RuleBookInput, days: Set<String>) -> [RBSession] {
        let since = PlanView.addDays(input.today, -input.settings.untouchedAfterTakenDays)
        let recent = Set(input.log.filter { $0.wasTaken && $0.closedOn > since }.flatMap(\.sessions))
        let sports: Set<RBSport> = [.swim, .bike, .run]
        let list = input.sessions.filter {
            days.contains($0.day) && $0.day >= input.today && sports.contains($0.sport) && RuleBook.touchable($0, input)
                && !input.easyStretch($0.day) && !recent.contains($0.id) && !$0.addedByMove
        }
        func rank(_ s: RBSession) -> Int { RuleBook.dropOrder.firstIndex(of: s.slot) ?? RuleBook.dropOrder.count }
        return list.sorted { (rank($0), $0.day, $0.row) < (rank($1), $1.day, $1.row) }
    }

    /* The interval session to make easy: run quality first, then bike quality, a session without ★ before one with it. */
    static func intervalSession(_ pool: [RBSession]) -> RBSession? {
        let fit = pool.filter { s in
            let l = RuleBook.labels(s), c = RuleBook.sessionClass(s)
            return (c == .hard || c == .moderate) && !l.long && !l.brick && !RuleBook.alreadyEasy(s)
        }
        func rank(_ s: RBSession) -> Int { s.slot == .runQuality ? 0 : (s.slot == .bikeQuality ? 1 : 2) }
        return fit.sorted { (($0.star ? 1 : 0), rank($0), $0.day) < (($1.star ? 1 : 0), rank($1), $1.day) }.first
    }

    /*
     * The new length after a cut of `percent`, rounded to 5 minutes, or nil
     * when no 5-minute step lies within 10–20 % of the session (too short).
     * The gentle cut rounds up, the firmer one down, so each stays in the band.
     */
    public static func cut(_ minutes: Int, percent: Int) -> Int? {
        guard minutes > 0 else { return nil }
        let raw = Double(minutes) * Double(percent) / 100
        var c = (percent <= mildPercent ? (raw / 5).rounded(.up) : (raw / 5).rounded(.down)) * 5
        if c < 5 { c = 5 }
        let share = c / Double(minutes)
        guard share >= 0.10 - 1e-9, share <= 0.20 + 1e-9 else { return nil }
        return minutes - Int(c)
    }

    /* The new length after growing by at most 10 %, rounded down to 5 minutes; nil when that is less than 5. */
    public static func grow(_ minutes: Int) -> Int? {
        let add = Int((Double(minutes) * Double(growPercent) / 100 / 5).rounded(.down)) * 5
        return add >= 5 ? minutes + add : nil
    }

    static func shortened(_ pool: [RBSession], percent: Int, count: Int, without: Set<String>) -> Choice {
        var moves: [Move] = [], lines: [String] = []
        for s in pool where !without.contains(s.id) {
            guard moves.count < count, let to = cut(s.plannedMin, percent: percent) else { continue }
            moves.append(.shorten(session: s.id, minutes: to))
            lines.append(RuleBookWords.easierLine(s, minutes: to, easier: false))
        }
        return Choice(moves: moves, lines: lines)
    }

    static func easier(_ s: RBSession) -> Choice {
        Choice(moves: [.makeEasier(session: s.id, instead: nil)], lines: [RuleBookWords.easierLine(s, minutes: nil, easier: true)])
    }

    static func longer(_ s: RBSession) -> Choice? {
        guard let to = grow(s.plannedMin) else { return nil }
        return Choice(moves: [.shorten(session: s.id, minutes: to)], lines: [RuleBookWords.easierLine(s, minutes: to, easier: false)])
    }

    static func join(_ a: Choice, _ b: Choice) -> Choice { Choice(moves: a.moves + b.moves, lines: a.lines + b.lines) }

    // MARK: the limits

    /*
     * Empty when a tuning may be offered and taken: only sessions of next week,
     * open, on their own day; each between −20 % and +10 % of what it was and
     * never harder; the whole week at most +10 %; and the rule book's own
     * limits L1, L2, L4, L5, L6, L8 and L10 (L3 and L7 make way for his
     * "up to +10 %", L11's calm is kept by leaving recently changed sessions out).
     */
    public static func failures(_ moves: [Move], input: RuleBookInput, monday: String) -> [String] {
        guard !moves.isEmpty, moves.allSatisfy({ m in
            if case .shorten = m { return true }
            if case .makeEasier(_, nil) = m { return true }
            return false
        }) else { return ["Only shorter, easier or a little longer."] }
        guard let after = try? RuleBook.apply(moves, to: input.sessions, input: input) else { return ["That does not fit the plan."] }
        let days = Set((0..<7).map { PlanView.addDays(monday, $0) })
        let old = Dictionary(input.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String] = []
        func top(_ x: RBSession) -> Int {
            x.sport == .strength ? (RuleBook.zones(x.intensity).rpeTop ?? 0) : (RuleBook.zones(x.intensity).top ?? 0)
        }
        for a in after {
            guard let b = old[a.id] else { out.append("No session is ever added."); continue }
            if a == b { continue }
            if !days.contains(b.day) || a.day != b.day { out.append("Only next week, each on its own day.") }
            if b.status != .open || b.day < input.today { out.append("Done, missed and past sessions stay as they are.") }
            if RuleBook.labels(b).protectedKind { out.append("Tests, simulations and the race stay as they are.") }
            let share = Double(a.plannedMin) / Double(max(1, b.plannedMin))
            if share > 1 + weekGrowth + 1e-9 || share < 0.80 - 1e-9 { out.append("A session changes by at most 20 % shorter or 10 % longer.") }
            if top(a) > top(b) { out.append("Nothing gets harder.") }
        }
        let before = input.sessions.filter { days.contains($0.day) && $0.counts }.reduce(0) { $0 + $1.plannedMin }
        let now = after.filter { days.contains($0.day) && $0.counts }.reduce(0) { $0 + $1.plannedMin }
        if Double(now) > Double(before) * (1 + weekGrowth) + 1e-9 { out.append("The week grows by at most 10 %.") }
        out += RuleBook.limitFailures(moves, trigger: .t5, input: input, only: [.l1, .l2, .l4, .l5, .l6, .l8, .l10]).map(\.reason)
        return out
    }

    /*
     * Round 30 safety: a tuning of that week already in the plan (taken on this device or on another
     * whose answer has not reached this one's shelf yet) — the card is never offered twice.
     */
    public static func takenInPlan(_ changes: [PlanChange], monday: String) -> Bool {
        let days = Set((0..<7).map { PlanView.addDays(monday, $0) })
        return changes.contains { $0.why.hasPrefix(whyPrefixForPlan) && !$0.undone && days.contains($0.afterDay ?? "") }
    }

    /* Whether the card's own choice may be written into the plan as it is now: its sessions exactly as they were, and every limit still met. */
    public static func stillFits(_ card: Card, input: RuleBookInput) -> Bool {
        guard let choice = card.choices.first, !choice.moves.isEmpty else { return false }
        for id in Set(choice.moves.flatMap(\.sessionIDs)) {
            guard let now = input.session(id), let was = card.before.first(where: { $0.id == id }), now == was else { return false }
        }
        return failures(choice.moves, input: input, monday: card.monday).isEmpty
    }

    // MARK: words

    static func count(_ n: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return words.indices.contains(n) ? words[n] : String(n)
    }

    /* The reason line, from the signs that were met, in plain words. Never sleep. */
    public static func whyLine(_ kind: Kind, _ s: Signals) -> String {
        switch kind {
        case .ease, .easeMore:
            var parts: [String] = []
            if s.feltHard >= hardSessions { parts.append("\(count(s.feltHard)) sessions felt hard this week") }
            if s.poorMornings >= poorMornings { parts.append("you felt tired on \(count(s.poorMornings)) mornings") }
            if s.overreaching { parts.append("your training load is well above your usual") }
            if parts.isEmpty { parts.append("\(count(s.feltHard)) sessions felt hard this week") }
            return "Why: " + parts.prefix(2).joined(separator: " and ") + "."
        case .missed:
            return "Why: \(count(s.missed)) sessions were missed or not logged this week; next week eases back in."
        case .lengthen:
            return "Why: every session done, efforts moderate and your mornings good."
        case .stays:
            return ""
        }
    }

    // MARK: Claude may pick

    /* The card with Claude's pick as its own choice and Claude's reason, or nil when the answer may not be used. */
    public static func picked(_ card: Card, by answer: ClaudeAnswer) -> Card? {
        let n = card.choices.count
        guard n > 0, answer.pick >= 1, answer.pick <= n, ClaudePick.accepts(answer, menuCount: n) else { return nil }
        var order = Array(card.choices.indices)
        order.remove(at: answer.pick - 1)
        order.insert(answer.pick - 1, at: 0)
        return Card(monday: card.monday, kind: card.kind, choices: order.map { card.choices[$0] }, why: answer.why,
                    before: card.before, claudePicked: true)
    }

    /* What Claude is asked: the same rules as the daily card (ClaudePick.system), this card's numbered menu, the last 14 days and next week. */
    public static func claudeRequest(_ card: Card, input: RuleBookInput) -> (system: String, user: String) {
        var lines: [String] = ["The menu. Choose one number. Each item changes next week, which starts on \(card.monday)."]
        lines.append("0 = keep my plan as it is")
        for (i, c) in card.choices.enumerated() {
            var line = "\(i + 1) = " + c.lines.joined(separator: "; ")
            if i == 0 { line += " (the rule book's own pick; its reason: \(card.why))" }
            lines.append(line)
        }
        let context = ClaudeContext.make(from: input)
        lines.append("")
        lines.append("Situation. Today is \(context.today).")
        lines.append("The last \(context.past.count) days, one line each (minutes planned and done; morning 1 to 5 is how he felt):")
        for d in context.past {
            var line = "\(d.day): planned \(d.plannedMinutes), done \(d.doneMinutes)"
            if let h = d.hard, !h.isEmpty { line += ", hard \(h)" }
            if let m = d.morning { line += ", morning \(m)" }
            if let e = d.extras, !e.isEmpty { line += ", extra \(e)" }
            lines.append(line)
        }
        lines.append("Next week as planned:")
        for fwd in 0..<7 {
            let day = PlanView.addDays(card.monday, fwd)
            let of = input.sessions.filter { $0.day == day && $0.sport != .rest && !$0.dropped && $0.status != .missed }
            let words = of.isEmpty ? "rest" : of.map { "\($0.sport.rawValue) \($0.plannedMin) min\($0.intensity.isEmpty ? "" : " " + $0.intensity)" }.joined(separator: "; ")
            lines.append("\(day): \(words)")
        }
        return (ClaudePick.system, lines.joined(separator: "\n"))
    }
}

/* What he answered, kept on the shelf ("tuning/week/<monday>") so it follows him to every device. */
public struct TuneAnswer: Codable, Equatable, Sendable {
    /* True: "Take it"; false: "Keep my plan". */
    public var took: Bool
    public var on: String
    public var lines: [String]
    /* The plan changes it made, for its one Undo. */
    public var changeIDs: [String]

    public init(took: Bool, on: String, lines: [String] = [], changeIDs: [String] = []) {
        self.took = took; self.on = on; self.lines = lines; self.changeIDs = changeIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        took = try c.decodeIfPresent(Bool.self, forKey: .took) ?? false
        on = try c.decodeIfPresent(String.self, forKey: .on) ?? ""
        lines = try c.decodeIfPresent([String].self, forKey: .lines) ?? []
        changeIDs = try c.decodeIfPresent([String].self, forKey: .changeIDs) ?? []
    }

    enum CodingKeys: String, CodingKey { case took, on, lines, changeIDs }
}

/* Claude's pick for one week's card ("tuning/week/<monday>/claude"): asked once; used only while the menu is the same. */
public struct TuneClaude: Codable, Equatable, Sendable {
    public var menu: [[String]]
    public var pick: Int?
    public var why: String?

    public init(menu: [[String]], pick: Int? = nil, why: String? = nil) { self.menu = menu; self.pick = pick; self.why = why }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menu = try c.decodeIfPresent([[String]].self, forKey: .menu) ?? []
        pick = try c.decodeIfPresent(Int.self, forKey: .pick)
        why = try c.decodeIfPresent(String.self, forKey: .why)
    }

    enum CodingKeys: String, CodingKey { case menu, pick, why }

    /* The card as shown: Claude's pick when it was for this very menu and passes the checks, else the card as it is. */
    public func apply(to card: NextWeekTune.Card) -> NextWeekTune.Card {
        guard menu == card.menu, let pick, let why, let picked = NextWeekTune.picked(card, by: ClaudeAnswer(pick: pick, why: why)) else { return card }
        return picked
    }
}
