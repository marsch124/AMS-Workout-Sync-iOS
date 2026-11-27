import Foundation

/*
 * Round 30, lane "raceweek": the tune-up race (12), race week (13) and the race
 * report (15). Pure rules: nothing here reads the shelf, the plan file or Garmin.
 *
 * Shelf keys (one entry each, small):
 *   raceweek/tuneups               -> [TuneUp]          his tune-up races
 *   raceweek/room/<tune-up id>     -> TuneUpRoomState   what he answered to "Make room"
 *   raceweek/<race day>/ticks      -> [String]          ids of the race-week things he ticked
 *   raceweek/<race day>/start      -> String            "07:30", the start time of a main race
 *   raceweek/<race day>/report     -> RaceReport        the legs as Garmin held them
 */

public enum RaceWeekKeys {
    public static let tuneups = "raceweek/tuneups"
    public static func room(_ id: String) -> String { "raceweek/room/\(id)" }
    public static func ticks(_ raceDay: String) -> String { "raceweek/\(raceDay)/ticks" }
    public static func start(_ raceDay: String) -> String { "raceweek/\(raceDay)/start" }
    public static func report(_ raceDay: String) -> String { "raceweek/\(raceDay)/report" }
}

// MARK: - the kinds of race

public enum RaceSize: String, Codable, CaseIterable, Sendable {
    case sprint, olympic, other, half, full

    public var word: String {
        switch self {
        case .sprint: return "Sprint"
        case .olympic: return "Olympic"
        case .other: return "Other"
        case .half: return "Half"
        case .full: return "Full"
        }
    }

    /* The race week list is shorter for a sprint, an Olympic and an "other" (a short rehearsal). */
    public var isShort: Bool { self == .sprint || self == .olympic || self == .other }

    /* From the plan's own race title ("Half-distance triathlon"); nil when it names no kind. */
    public static func from(title: String) -> RaceSize? {
        let t = title.lowercased()
        if t.contains("70.3") || t.contains("half") { return .half }
        if t.contains("sprint") { return .sprint }
        if t.contains("olympic") || t.contains("standard distance") { return .olympic }
        if t.contains("full distance") || t.contains("iron distance") || t.contains("140.6") || t.contains("ironman") { return .full }
        return nil
    }
}

// MARK: - the tune-up race

public struct TuneUp: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var day: String
    public var size: RaceSize
    /* Only for "other". */
    public var km: Double?
    public var place: String
    /* "07:30", empty = not typed. */
    public var start: String

    public init(id: String = UUID().uuidString, name: String = "", day: String, size: RaceSize = .sprint,
                km: Double? = nil, place: String = "", start: String = "") {
        self.id = id; self.name = name; self.day = day; self.size = size; self.km = km; self.place = place; self.start = start
    }

    private enum Key: String, CodingKey { case id, name, day, size, km, place, start }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? ""
        size = (try? c.decodeIfPresent(RaceSize.self, forKey: .size)) ?? .other
        km = try? c.decodeIfPresent(Double.self, forKey: .km)
        place = (try? c.decodeIfPresent(String.self, forKey: .place)) ?? ""
        start = (try? c.decodeIfPresent(String.self, forKey: .start)) ?? ""
    }

    /* "Sprint", "Olympic", "12 km". */
    public var distanceWords: String {
        if size == .other, let km, km > 0 {
            let whole = km.rounded() == km
            return (whole ? String(Int(km)) : String(format: "%.1f", km)) + " km"
        }
        return size == .other ? "Own distance" : size.word
    }

    public var title: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Tune-up race" : name }
}

public enum TuneUpList {
    /* Sorted by day; a bad entry (no day) is dropped. */
    public static func sorted(_ list: [TuneUp]) -> [TuneUp] {
        list.filter { parseDayKey($0.day) != nil }.sorted { ($0.day, $0.id) < ($1.day, $1.id) }
    }

    public static func on(_ day: String, in list: [TuneUp]) -> [TuneUp] { list.filter { $0.day == day } }
}

/* "HH:mm" as minutes after midnight; nil when it is not a time. */
public enum ClockText {
    public static func minutes(_ text: String) -> Int? {
        let p = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ":").split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func text(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

// MARK: - make room for the tune-up

public enum TuneUpRoom {
    public static let why = "Room for the tune-up race"
    public static func why(batch: String = String(UUID().uuidString.prefix(8))) -> String { why + " #" + batch }
    public static func isOurs(_ why: String) -> Bool { why == Self.why || why.hasPrefix(Self.why + " #") }
    public static func batch(of why: String) -> String? {
        guard isOurs(why) else { return nil }
        guard let r = why.range(of: " #", options: .backwards) else { return "" }
        return String(why[r.upperBound...])
    }

    /* A tune-up this close to the main race, or to a test, is not changed around. */
    public static let nearRaceDays = 21

    public struct Edit: Equatable {
        public let key: String
        public let day: String
        public let words: String
        public let draft: SessionDraft
    }

    public struct Removal: Equatable {
        public let key: String
        public let day: String
        public let words: String
    }

    public struct Change: Equatable {
        public var edits: [Edit] = []
        public var removals: [Removal] = []
        /* "Make room for the tune-up: Thu and Fri shorter and easy, Sat rest, Mon and Tue easy" */
        public var headline = ""
        /* The exact changes, day by day, in words. */
        public var lines: [String] = []
        /* One calm grey line: why nothing is offered. */
        public var grey: String?
        public init() {}
        public var isEmpty: Bool { edits.isEmpty && removals.isEmpty }
    }

    static func untouchable(_ s: Workout) -> Bool {
        !s.results.isEmpty || s.logged || s.missed || s.pending != nil || s.pendingMove != nil
    }

    static func isTest(_ s: Workout) -> Bool { normalise(s.title).contains("test") }

    static func protected(_ s: Workout) -> Bool {
        ["rest", "race"].contains(s.discipline.id) || isTest(s) || untouchable(s)
    }

    public static func weekdayName(_ day: String) -> String {
        guard let d = parseDayKey(day) else { return day }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][utc.component(.weekday, from: d) - 1]
    }

    /* "Thu and Fri", "Mon, Tue and Wed". */
    static func join(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    public static let tooCloseWords = "A tune-up this close to your main race leaves too little time to recover, so your plan is left as it is."
    public static let testWeekWords = "There is a test in that week, so your plan is left as it is."
    public static let pastWords = "That day has already gone by, so your plan is left as it is."
    public static let nothingWords = "Nothing in your plan needs to change around it."

    /*
     * What making room would change. `mainRaceDay` is the plan's own race. Offsets from the tune-up day:
     * -3 and -2 shorter and easy (60 %, to 5 minutes, at least 15), -1 rest (sessions taken out), +1 and +2 easy
     * (at most 60 minutes). A session that is done, logged, missed, waiting, a test, a race or a day already
     * gone is never touched; mobility stays on the rest day.
     */
    public static func plan(_ tuneUp: TuneUp, sessions: [Workout], weeks: [PlanWeek], mainRaceDay: String?,
                            mapping: Mapping, today: String) -> Change {
        var out = Change()
        let d = tuneUp.day
        guard parseDayKey(d) != nil else { return out }
        if d <= today { out.grey = pastWords; return out }
        if let race = mainRaceDay, abs(Stats.daysBetween(d, race)) < nearRaceDays { out.grey = tooCloseWords; return out }
        let span = (-3...2).map { PlanView.addDays(d, $0) }
        let testWeek = weeks.contains { w in w.isTest && span.contains { PlanView.weekStart($0) == PlanView.weekStart(w.monday) } }
        if testWeek || sessions.contains(where: { span.contains($0.dayKey) && isTest($0) }) { out.grey = testWeekWords; return out }

        func minutesText(_ m: Double) -> String { "\(Int(m.rounded())) min" }
        var shorter: [String] = [], rest: [String] = [], easy: [String] = []
        for offset in [-3, -2, -1, 1, 2] {
            let day = PlanView.addDays(d, offset)
            if day <= today { continue }
            for s in sessions where s.dayKey == day && !protected(s) {
                let mins = Plan.plannedSeconds(s, mapping).map { $0 / 60 }
                let sport = s.discipline.label
                if offset == -1 {
                    if s.discipline.id == "mobility" { continue }
                    out.removals.append(Removal(key: s.key, day: day, words: "\(weekdayName(day)) \u{00B7} \(sport) taken out"))
                    if !rest.contains(weekdayName(day)) { rest.append(weekdayName(day)) }
                    continue
                }
                if s.discipline.id == "mobility" { continue }
                var dr = SessionDraft(dayKey: day, sport: s.discipline.id, title: s.title, minutes: mins,
                                      intensity: s.planned.intensity, purpose: s.planned.description, isKey: s.isKey)
                let was = dr
                if let m = mins { dr.minutes = offset < 0 ? min(m, max(15, (m * 0.6 / 5).rounded() * 5)) : min(m, 60) }
                dr.intensity = "Easy"
                dr.isKey = false
                if dr == was { continue }
                let name = weekdayName(day)
                var words = "\(name) \u{00B7} \(sport)"
                if let a = mins, let b = dr.minutes, a != b { words += " \(minutesText(a)) \u{2192} \(minutesText(b))," }
                words += " easy"
                out.edits.append(Edit(key: s.key, day: day, words: words, draft: dr))
                if offset < 0 { if !shorter.contains(name) { shorter.append(name) } } else if !easy.contains(name) { easy.append(name) }
            }
        }
        guard !out.isEmpty else { out.grey = nothingWords; return out }
        var parts: [String] = []
        if !shorter.isEmpty { parts.append(join(shorter) + " shorter and easy") }
        if !rest.isEmpty { parts.append(join(rest) + " rest") }
        if !easy.isEmpty { parts.append(join(easy) + " easy") }
        out.headline = "Make room for the tune-up: " + parts.joined(separator: ", ")
        out.lines = (out.edits.map { ($0.day, $0.words) } + out.removals.map { ($0.day, $0.words) })
            .sorted { $0.0 < $1.0 }.map { $0.1 }
        return out
    }

    /* Writes the change into the book, all of it or none. Returns the changes' ids. */
    @discardableResult
    public static func apply(_ c: Change, to book: inout PlanBook, why: String = TuneUpRoom.why(), now: Date = Date()) throws -> [String] {
        var copy = book
        var ids: [String] = []
        for e in c.edits {
            guard let s = copy.session(e.key) else { throw BookError.noSession(e.key) }
            // Logged, missed or waiting since the card was worked out: never changed.
            if protected(s) { continue }
            if let change = try copy.change(e.key, to: e.draft, why: why, now: now) { ids.append(change.id) }
        }
        for r in c.removals {
            if let s = copy.session(r.key), protected(s) { continue }
            let change = try copy.remove(r.key, why: why, now: now)
            ids.append(change.id)
        }
        book = copy
        return ids
    }

    /*
     * Round 30 safety: room already made around this tune-up (on this device, or on another whose
     * answer has not reached this one's shelf yet) — never offered a second time, so nothing is cut twice.
     */
    public static func takenInPlan(_ changes: [PlanChange], tuneUp: TuneUp) -> Bool {
        let span = Set((-3...2).map { PlanView.addDays(tuneUp.day, $0) })
        return changes.contains { c in isOurs(c.why) && !c.undone && span.contains(c.afterDay ?? c.undo?.dayKey ?? "") }
    }

    public static func undoable(_ changes: [PlanChange], book: PlanBook) -> [PlanChange] {
        changes.filter { c in
            guard isOurs(c.why), !c.undone, book.canUndo(c.id) else { return false }
            guard let s = book.session(c.key) else { return c.kind != "add" }
            return !untouchable(s)
        }
    }

    /* One Undo for the whole round, newest first, all or none. */
    @discardableResult
    public static func undo(batch: String, in book: inout PlanBook, now: Date = Date()) throws -> Int {
        let list = undoable(book.changes.filter { TuneUpRoom.batch(of: $0.why) == batch }, book: book)
        var copy = book
        for c in list.reversed() { try copy.undo(c.id, now: now) }
        book = copy
        return list.count
    }
}

/* What he answered to the card, kept on the shelf (one small entry per tune-up). */
public struct TuneUpRoomState: Codable, Equatable, Sendable {
    public enum Answer: String, Codable, Sendable { case took, kept }
    public var answer: Answer
    public var batch: String
    public init(answer: Answer, batch: String = "") { self.answer = answer; self.batch = batch }
}

// MARK: - race week

public struct RaceWeekItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let text: String
}

public struct RaceWeekDay: Equatable, Identifiable, Sendable {
    /* Days before the race: 7 … 1; 0 = race day. */
    public let before: Int
    public let day: String
    public let items: [RaceWeekItem]
    public var id: Int { before }
}

public enum RaceWeek {
    /* Seven days before until race day. */
    public static func isOn(days: Int) -> Bool { (0...7).contains(days) }

    /* "Race week · 5 days to go", "Race week · tomorrow", "Race week · today". */
    public static func cardWords(days: Int) -> String {
        switch days {
        case 0: return "Race week \u{00B7} race day"
        case 1: return "Race week \u{00B7} 1 day to go"
        default: return "Race week \u{00B7} \(days) days to go"
        }
    }

    private static func item(_ before: Int, _ key: String, _ text: String) -> RaceWeekItem {
        RaceWeekItem(id: "d\(before)-\(key)", text: text)
    }

    /* The list, day by day. A sprint, an Olympic or another short race gets fewer things. */
    public static func days(raceDay: String, size: RaceSize?) -> [RaceWeekDay] {
        let short = size?.isShort ?? false
        func d(_ n: Int, _ items: [RaceWeekItem]) -> RaceWeekDay {
            RaceWeekDay(before: n, day: PlanView.addDays(raceDay, -n), items: items)
        }
        var out: [RaceWeekDay] = []
        out.append(d(7, [item(7, "bike-check", "Bike check: tyres, brakes, gears and chain")]
                    + (short ? [] : [item(7, "guide", "Read the race guide again: start, route and cut-off times")])))
        out.append(d(6, [item(6, "key-session", short ? "One short session with a few race-pace efforts" : "The last key session, then keep the rest easy")]))
        out.append(d(5, short ? [] : [item(5, "travel-plan", "Check where you sleep and how you get there")]))
        out.append(d(4, [item(4, "easy", "Easy day, short and loose")]
                    + (short ? [] : [item(4, "kit", "Lay out your kit and check it against the kit list")])))
        out.append(d(3, [item(3, "carbs", short ? "A little more carbohydrate at each meal" : "Carbs up: a little more at each meal")]
                    + (short ? [] : [item(3, "spares", "Spare tubes, CO2 or pump, and your nutrition bought")])))
        out.append(d(2, [item(2, "pack", "Pack with your kit list")]
                    + (short ? [] : [item(2, "carbs", "Carbs up again; drink well through the day")])
                    + [item(2, "travel", "Travel to the race")]))
        out.append(d(1, [item(1, "check-in", "Check in and collect your number"),
                         item(1, "rack", "Rack the bike and walk through transition"),
                         item(1, "briefing", "Go to the briefing"),
                         item(1, "early-night", "Early night")]))
        return out.filter { !$0.items.isEmpty }
    }

    public static func allItems(raceDay: String, size: RaceSize?) -> [RaceWeekItem] {
        days(raceDay: raceDay, size: size).flatMap(\.items)
    }

    /* Things ticked, of those that are on the list. */
    public static func tickedCount(_ ticks: [String], raceDay: String, size: RaceSize?) -> Int {
        let ids = Set(allItems(raceDay: raceDay, size: size).map(\.id))
        return Set(ticks).intersection(ids).count
    }

    // MARK: race morning

    public struct MorningStep: Equatable, Identifiable, Sendable {
        public let clock: String
        public let text: String
        public var id: String { clock + text }
    }

    public static let defaultStart = "08:00"

    /* Worked back from the start time: wake 3 h before, breakfast 2 h 45, leave 2 h, there 1 h 45, set up, wetsuit 25 min, start. */
    public static func morning(start: String) -> [MorningStep] {
        let s = ClockText.minutes(start) ?? ClockText.minutes(defaultStart) ?? 480
        func step(_ before: Int, _ text: String) -> MorningStep { MorningStep(clock: ClockText.text(s - before), text: text) }
        return [step(180, "Wake up"), step(165, "Breakfast"), step(120, "Leave for the race"),
                step(105, "Transition opens: set up the bike and your kit"),
                step(25, "Wetsuit on, warm up"), step(0, "Start")]
    }
}

// MARK: - the race report

public struct RaceLegResult: Codable, Equatable, Sendable {
    public var leg: String
    public var seconds: Double
    public var metres: Double?
    /* Garmin's own average speed, metres a second. */
    public var speedMps: Double?
    public var avgHr: Double?

    public init(leg: RaceLeg, seconds: Double, metres: Double? = nil, speedMps: Double? = nil, avgHr: Double? = nil) {
        self.leg = leg.rawValue; self.seconds = seconds; self.metres = metres; self.speedMps = speedMps; self.avgHr = avgHr
    }

    public var raceLeg: RaceLeg? { RaceLeg(rawValue: leg) }
}

/* What the report keeps on the shelf: the legs, numbers only. */
public struct RaceReport: Codable, Equatable, Sendable {
    public var day: String
    public var legs: [RaceLegResult]
    public init(day: String, legs: [RaceLegResult]) { self.day = day; self.legs = legs }

    public func leg(_ l: RaceLeg) -> RaceLegResult? { legs.first { $0.leg == l.rawValue } }

    public struct Row: Equatable, Sendable {
        public let leg: RaceLeg
        public let actual: Double
        public let planned: Int?
        /* actual - planned, seconds; nil without a plan. */
        public var difference: Double? { planned.map { actual - Double($0) } }
        /* Bar: actual against the larger of the two, 0…1; planned mark in the same scale. */
        public let fillFraction: Double
        public let plannedFraction: Double?
        public let speedMps: Double?
        public let metres: Double?
        public let avgHr: Double?
    }

    /* The five parts in race order, each against the race page's own plan. */
    public func rows(plan: RacePacing) -> [Row] {
        RaceLeg.allCases.compactMap { l in
            guard let r = leg(l) else { return nil }
            let planned = plan.seconds(l)
            let top = max(r.seconds, Double(planned ?? 0), 1)
            return Row(leg: l, actual: r.seconds, planned: planned, fillFraction: r.seconds / top,
                       plannedFraction: planned.map { Double($0) / top }, speedMps: r.speedMps, metres: r.metres, avgHr: r.avgHr)
        }
    }

    /* "Bike 3h 02m · planned 3h 00m" (planned only where he typed it). */
    public static func line(_ row: Row) -> String {
        let base = row.leg.word + " " + RacePacing.words(Int(row.actual.rounded()), changeOver: row.leg.isChangeOver)
        guard let p = row.planned else { return base }
        return base + " \u{00B7} planned " + RacePacing.words(p, changeOver: row.leg.isChangeOver)
    }

    /* Garmin's own speed written for the sport: swim per 100 m, bike km/h, run per km. A unit change, nothing worked out. */
    public static func speedWords(_ leg: RaceLeg, mps: Double?) -> String? {
        guard let v = mps, v > 0 else { return nil }
        switch leg {
        case .swim: return clock(100 / v) + " /100 m"
        case .bike: return String(format: "%.1f km/h", v * 3.6)
        case .run: return clock(1000 / v) + " /km"
        default: return nil
        }
    }

    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    /*
     * "What to keep": two or three plain lines from rules. The steadiest leg (smallest difference from the plan)
     * and the leg that drifted most (largest), only when two or more legs have a plan; then the changeovers.
     * Never a judgement: it says what is.
     */
    public func keep(plan: RacePacing) -> [String] {
        var out: [String] = []
        let compared = rows(plan: plan).filter { !$0.leg.isChangeOver && $0.planned != nil }
        func pct(_ r: Row) -> Double { abs(r.difference ?? 0) / Double(r.planned ?? 1) * 100 }
        func said(_ r: Row) -> String {
            let p = pct(r)
            let side = (r.difference ?? 0) > 0 ? "over" : "under"
            return p < 0.5 ? "on its plan" : "\(Int(p.rounded())) % \(side) its plan"
        }
        if compared.count >= 2, let steady = compared.min(by: { pct($0) < pct($1) }), let drift = compared.max(by: { pct($0) < pct($1) }) {
            out.append("The steadiest leg was the \(steady.leg.word.lowercased()): \(said(steady)).")
            if drift.leg != steady.leg { out.append("The leg that drifted most was the \(drift.leg.word.lowercased()): \(said(drift)).") }
        } else if let only = compared.first {
            out.append("The \(only.leg.word.lowercased()) was \(said(only)).")
        }
        let t1 = leg(.t1), t2 = leg(.t2)
        if t1 != nil || t2 != nil {
            var parts: [String] = []
            if let t1 { parts.append("T1 " + RacePacing.words(Int(t1.seconds.rounded()), changeOver: true)) }
            if let t2 { parts.append("T2 " + RacePacing.words(Int(t2.seconds.rounded()), changeOver: true)) }
            out.append("The changeovers: " + parts.joined(separator: ", ") + ".")
        }
        if out.isEmpty { out.append("Type your times on the race page to see each leg against your plan.") }
        return Array(out.prefix(3))
    }
}

/* Garmin's multisport activity: the parent holds the children's ids; each child has its own summary. */
public enum GarminMultisport {
    public static func isMultisport(typeKey: String) -> Bool { typeKey.lowercased().contains("multi_sport") }

    /* metadataDTO.childIds of the parent's detail answer. */
    public static func childIds(parent json: Any?) -> [Int] {
        guard let root = json as? [String: Any], let meta = root["metadataDTO"] as? [String: Any],
              let list = meta["childIds"] as? [Any] else { return [] }
        return list.compactMap { ($0 as? NSNumber)?.intValue ?? Int("\($0)") }
    }

    public struct Child: Equatable {
        public var typeKey: String
        public var start: String
        public var seconds: Double
        public var metres: Double?
        public var speedMps: Double?
        public var avgHr: Double?
        public init(typeKey: String, start: String, seconds: Double, metres: Double? = nil, speedMps: Double? = nil, avgHr: Double? = nil) {
            self.typeKey = typeKey; self.start = start; self.seconds = seconds
            self.metres = metres; self.speedMps = speedMps; self.avgHr = avgHr
        }
    }

    /* A child's detail answer: activityTypeDTO.typeKey and summaryDTO (startTimeGMT, duration, distance, averageSpeed, averageHR). */
    public static func child(detail json: Any?) -> Child? {
        guard let root = json as? [String: Any], let sum = root["summaryDTO"] as? [String: Any] else { return nil }
        let type = ((root["activityTypeDTO"] as? [String: Any])?["typeKey"] as? String) ?? ""
        func num(_ k: String) -> Double? { GarminMorning.number(sum[k]) }
        guard let secs = num("duration"), secs > 0 else { return nil }
        return Child(typeKey: type, start: (sum["startTimeGMT"] as? String) ?? "", seconds: secs,
                     metres: num("distance").flatMap { $0 > 0 ? $0 : nil },
                     speedMps: num("averageSpeed").flatMap { $0 > 0 ? $0 : nil },
                     avgHr: num("averageHR").flatMap { $0 > 0 ? $0 : nil })
    }

    /* The children in start order become swim, T1, bike, T2, run; the first transition is T1, the second T2. */
    public static func legs(_ children: [Child]) -> [RaceLegResult] {
        var out: [RaceLegResult] = []
        var transitions = 0
        for c in children.sorted(by: { $0.start < $1.start }) {
            let t = c.typeKey.lowercased()
            let leg: RaceLeg?
            if t.contains("transition") { transitions += 1; leg = transitions == 1 ? .t1 : (transitions == 2 ? .t2 : nil) }
            else if t.contains("swim") { leg = .swim }
            else if t.contains("bik") || t.contains("cycl") { leg = .bike }
            else if t.contains("run") { leg = .run }
            else { leg = nil }
            guard let leg, !out.contains(where: { $0.leg == leg.rawValue }) else { continue }
            out.append(RaceLegResult(leg: leg, seconds: c.seconds, metres: c.metres, speedMps: c.speedMps, avgHr: c.avgHr))
        }
        return out
    }
}
