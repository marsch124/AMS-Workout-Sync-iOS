import Foundation

/*
 * Away mode (round 28, pick 17): where he is for a while and what he HAS there.
 * Stored on the shelf under "away" (so it follows him between devices); the
 * rule book reads it as one more input. Pure: no clock, no files.
 *
 * Days are "yyyy-mm-dd". `until` is the last day he is away; he is back the day after.
 */

public enum AwayThing: String, Codable, CaseIterable, Equatable, Sendable {
    case pool, bike, gym, openWater = "openwater"

    /* The words on the page ("Bike (or turbo)") and in the chip. */
    public var tickWord: String {
        switch self {
        case .pool: return "Pool"
        case .bike: return "Bike (or turbo)"
        case .gym: return "Gym"
        case .openWater: return "Open water"
        }
    }

    /* "No pool while away" */
    public var chipWord: String {
        switch self {
        case .pool: return "No pool while away"
        case .bike: return "No bike while away"
        case .gym: return "No gym while away"
        case .openWater: return "No open water while away"
        }
    }

    /* "no pool" (the grey line on Today) */
    public var shortNo: String {
        switch self {
        case .pool: return "no pool"
        case .bike: return "no bike"
        case .gym: return "no gym"
        case .openWater: return "no open water"
        }
    }

    /* "without a pool" (the reason line) */
    var withoutWord: String {
        switch self {
        case .pool: return "without a pool"
        case .bike: return "without a bike"
        case .gym: return "without a gym"
        case .openWater: return "without open water"
        }
    }
}

public struct AwayPeriod: Codable, Equatable, Sendable {
    public var from: String
    public var until: String
    /* AwayThing raw values he HAS there. Unknown words are kept as they are and ignored. */
    public var has: [String]

    public init(from: String, until: String, has: [String]) {
        self.from = from; self.until = until; self.has = has
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        until = try c.decodeIfPresent(String.self, forKey: .until) ?? ""
        has = try c.decodeIfPresent([String].self, forKey: .has) ?? []
    }

    enum CodingKeys: String, CodingKey { case from, until, has }

    /* A day inside the period, both ends included. A period with a missing or wrong date holds no day. */
    public func contains(_ day: String) -> Bool {
        parseDayKey(from) != nil && parseDayKey(until) != nil && day >= from && day <= until
    }

    public func has(_ thing: AwayThing) -> Bool { has.contains(thing.rawValue) }

    /* What he does not have there, in the page's order. */
    public var lacking: [AwayThing] { AwayThing.allCases.filter { !has($0) } }

    /* The first day he is back. */
    public var firstDayBack: String { PlanView.addDays(until, 1) }
}

/* What a session needs: any ONE of these is enough. */
public struct AwayNeed: Equatable, Sendable {
    public let anyOf: [AwayThing]
}

public enum Away {

    /*
     * What a session needs, read from its sport and its words (title, and the
     * description when there is one): a swim needs a pool or open water (the
     * words "open water" or "pool" narrow it), a bike or brick needs a bike,
     * strength needs a gym. Everything else needs nothing.
     */
    public static func need(sport: RBSport, text: String) -> AwayNeed? {
        let t = " " + normalise(text) + " "
        switch sport {
        case .swim:
            if t.contains("open water") || t.contains("openwater") || t.contains(" lake ") || t.contains(" sea ") {
                return AwayNeed(anyOf: [.openWater])
            }
            if t.contains(" pool ") { return AwayNeed(anyOf: [.pool]) }
            return AwayNeed(anyOf: [.pool, .openWater])
        case .bike, .brick: return AwayNeed(anyOf: [.bike])
        case .strength: return AwayNeed(anyOf: [.gym])
        default: return nil
        }
    }

    /* What is missing for this need, or nil when he has something that does it. */
    public static func lacking(_ need: AwayNeed?, in period: AwayPeriod) -> AwayThing? {
        guard let need, !need.anyOf.contains(where: { period.has($0) }) else { return nil }
        return need.anyOf.first
    }

    /* The calm grey chip words for a session on `day`, or nil. */
    public static func chip(sport: RBSport, text: String, day: String, period: AwayPeriod?) -> String? {
        guard let period, period.contains(day) else { return nil }
        return lacking(need(sport: sport, text: text), in: period)?.chipWord
    }

    /* "Away until Wed 6 Jan · no pool, no gym" — only while today lies inside the period. */
    public static func todayLine(period: AwayPeriod?, today: String) -> String? {
        guard let period, period.contains(today) else { return nil }
        var line = "Away until " + dayWords(period.until)
        let no = period.lacking.map(\.shortNo)
        if !no.isEmpty { line += " \u{00B7} " + no.joined(separator: ", ") }
        return line
    }

    /* "Wed 6 Jan" */
    public static func dayWords(_ key: String) -> String {
        guard let d = parseDayKey(key) else { return key }
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    /* "6 Jan" */
    static func shortDay(_ key: String) -> String {
        guard let d = parseDayKey(key) else { return key }
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}

// MARK: - the rule book's trigger: away

extension RuleBook {

    /* How many days ahead (today and the two after) an away session may get a card. */
    static let awayLookAheadDays = 2

    /*
     * AW · away: the session cannot be done as planned.
     * Fires on the first open session of today or the next two days that lies
     * inside the away period and needs something he does not have there (swim:
     * no pool and no open water; bike or brick: no bike). Strength without a gym
     * never gets a card: its answer is the "No-gym version", which changes nothing.
     * Menu, in this order, only moves the book already has:
     *   M2 swap it with a later EASY session of the same week that he can do
     *      there, no longer and no harder than the planned one (the planned one
     *      then keeps its new day, or is dropped when it would still be away);
     *   M5 move it to the first day after he is back (same week, never a Friday);
     *   M1 rest (never a key session).
     * Nothing is ever added; every limit judges each choice as for any trigger.
     */
    static func away(_ input: RuleBookInput) -> [Candidate]? {
        guard let period = input.away else { return nil }
        let last = PlanView.addDays(input.today, awayLookAheadDays)
        let asked = Set(input.log.filter { $0.trigger == .away }.map(\.key))
        let due = input.sessions.filter {
            $0.day >= input.today && $0.day <= last && period.contains($0.day) && $0.sport != .strength && touchable($0, input)
                && Away.lacking(Away.need(sport: $0.sport, text: $0.title), in: period) != nil && !asked.contains($0.id)
        }.sorted { ($0.day, $0.row) < ($1.day, $1.row) }
        for s in due {
            let out = awayCandidates(s, period: period, input)
            if !out.isEmpty { return out }
        }
        return nil
    }

    private static func awayCandidates(_ s: RBSession, period: AwayPeriod, _ input: RuleBookInput) -> [Candidate] {
        guard let lack = Away.lacking(Away.need(sport: s.sport, text: s.title), in: period) else { return [] }
        let name = RuleBookWords.name(s)
        let lead = "\(name): \(lack.shortNo) while away"
        let reason = "Why: you are away until \(Away.shortDay(period.until)) \(lack.withoutWord)"
        var out: [Candidate] = []

        // 1 · an easy session he can do there, no longer and no harder.
        let top = zones(s.intensity).top ?? 9
        let partners = input.sessions.filter { e in
            e.day > s.day && input.week(of: e.day) == input.week(of: s.day) && !isFriday(e.day)
                && touchable(e, input) && !labels(e).key && sessionClass(e) == .easy && e.sport != .rest
                && Away.lacking(Away.need(sport: e.sport, text: e.title), in: period) == nil
                && e.plannedMin <= s.plannedMin && (zones(e.intensity).top ?? 9) <= top
        }.sorted { ($0.day, $0.row) < ($1.day, $1.row) }
        for e in partners.prefix(2) {
            let sword = RuleBookWords.sport(s)
            let ewords = RuleBookWords.easyWords(e)
            let why = reason + "; \(RuleBookWords.aAn(ewords)) keeps the day aerobic."
            // The planned session keeps its new day when he can do it there; otherwise it goes (never a key session).
            let stillAway = period.contains(e.day) && Away.lacking(Away.need(sport: s.sport, text: s.title), in: period) != nil
            if stillAway {
                guard !labels(s).key else { continue }
                out.append(Candidate(trigger: .away, step: 0, key: s.id, moves: [.swapWithNextEasy(session: s.id, easy: e.id), .drop(session: s.id)],
                                     headline: "\(lead) \u{2192} \(ewords) \(e.plannedMin) min instead", why: why))
            } else {
                out.append(Candidate(trigger: .away, step: 0, key: s.id, moves: [.swapWithNextEasy(session: s.id, easy: e.id)],
                                     headline: "\(lead) \u{2192} \(ewords) \(e.plannedMin) min (\(sword) moves to \(RuleBookWords.day(e.day)))", why: why))
            }
        }

        // 2 · the first day after he is back, in the same plan week.
        let week = input.week(of: s.day)
        var d = period.firstDayBack
        while input.week(of: d) == week, d > s.day {
            if !isFriday(d) {
                out.append(Candidate(trigger: .away, step: 0, key: s.id, moves: [.moveToDay(session: s.id, day: d)],
                                     headline: "\(lead) \u{2192} \(RuleBookWords.day(d)), after you are back",
                                     why: reason + "; it waits until you are back."))
                break
            }
            d = PlanView.addDays(d, 1)
        }

        // 3 · rest. A key session is never dropped.
        if !labels(s).key {
            out.append(Candidate(trigger: .away, step: 0, key: s.id, moves: [.drop(session: s.id)],
                                 headline: "\(lead) \u{2192} rest", why: reason + "; missed sessions are not made up."))
        }
        return out
    }
}

extension RuleBookWords {
    /* "easy run", "easy ride", "easy swim", "easy session" */
    static func easyWords(_ s: RBSession) -> String {
        switch s.sport {
        case .bike: return "easy ride"
        case .run: return "easy run"
        case .swim: return "easy swim"
        case .strength: return "easy strength"
        default: return "easy session"
        }
    }

    static func aAn(_ words: String) -> String { "an " + words }
}
