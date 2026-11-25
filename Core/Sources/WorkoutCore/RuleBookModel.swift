import Foundation

/*
 * The rule book's inputs: plain values, nothing that reads a clock, a file or
 * the network. The app builds them from its PlanBook (see `RuleBook.input`),
 * the tool `rule-check` builds them from a copy of the workbook, and the tests
 * build them by hand.
 *
 * Everything is a value: a check works on copies and never changes the plan.
 * Nothing changes until he taps "Take it", and that is the app's business.
 */

// MARK: - what a session is to the rule book

public enum RBSport: String, Codable, Equatable, Sendable {
    case swim, bike, run, strength, brick, race, rest, other

    public init(disciplineID: String) {
        self = RBSport(rawValue: disciplineID) ?? .other
    }
}

public enum RBStatus: String, Codable, Equatable, Sendable {
    /* Not yet logged. */ case open
    /* Logged. */ case done
    /* He marked it missed. */ case missed
    /* An accepted suggestion changed or dropped it. Counts as followed, never as missed. */ case changed
}

/* The role a session has in its week, fixed when the plan is taken in (spec 3.4). */
public enum RBSlot: String, Codable, Equatable, Sendable {
    case swim = "SWIM", strengthA = "STR_A", strengthB = "STR_B", longRide = "LONG_RIDE", bikeQuality = "BIKE_Q"
    case longRun = "LONG_RUN", brick = "BRICK", runQuality = "RUN_Q", easyRun = "EASY_RUN", postSim = "POST_SIM"
    case thirdRide = "RIDE_3", rest = "REST", other = "OTHER"
}

public enum RBWeekTag: String, Codable, Equatable, Sendable {
    case test, easy, sim, peak2, race, wrapup, load
}

public struct RBSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /* The day it is on now, "yyyy-mm-dd". */
    public var day: String
    public var sport: RBSport
    public var title: String
    public var plannedMin: Int
    public var intensity: String
    public var star: Bool
    public var phase: String
    public var row: Int
    /* The plan week it was written for (its ORIGINAL date), whatever day it is on now. */
    public var originalWeek: Int
    public var slot: RBSlot
    public var status: RBStatus
    /* Dropped by an accepted suggestion: counted 0, shown as "rest (your choice)". */
    public var dropped: Bool
    public var actualMin: Int?
    public var rpe: Int?
    /* Put there by a move (M6's borrowed easy week), not by the plan. */
    public var addedByMove: Bool

    public init(id: String, day: String, sport: RBSport, title: String, plannedMin: Int, intensity: String,
                star: Bool = false, phase: String = "", row: Int = 0, originalWeek: Int, slot: RBSlot = .other,
                status: RBStatus = .open, dropped: Bool = false, actualMin: Int? = nil, rpe: Int? = nil,
                addedByMove: Bool = false) {
        self.id = id; self.day = day; self.sport = sport; self.title = title; self.plannedMin = plannedMin
        self.intensity = intensity; self.star = star; self.phase = phase; self.row = row
        self.originalWeek = originalWeek; self.slot = slot; self.status = status; self.dropped = dropped
        self.actualMin = actualMin; self.rpe = rpe; self.addedByMove = addedByMove
    }

    public var isRest: Bool { sport == .rest }
    /* Takes part in a week's minutes: not rest, not dropped. */
    public var counts: Bool { !isRest && !dropped }
}

public struct RBWeek: Codable, Equatable, Sendable {
    public var number: Int
    public var monday: String
    public var tag: RBWeekTag
    public var phase: String
    public var isTaper: Bool

    public init(number: Int, monday: String, tag: RBWeekTag, phase: String = "", isTaper: Bool = false) {
        self.number = number; self.monday = monday; self.tag = tag; self.phase = phase; self.isTaper = isTaper
    }
}

public struct RBExtra: Codable, Equatable, Sendable {
    public var day: String
    public var activity: String
    public var minutes: Int
    public var countsAsTraining: Bool

    public init(day: String, activity: String, minutes: Int, countsAsTraining: Bool) {
        self.day = day; self.activity = activity; self.minutes = minutes; self.countsAsTraining = countsAsTraining
    }
}

/* When in the day the engine is asked. */
public enum RBMoment: String, Codable, Equatable, Sendable {
    /* After "How do you feel?", or at 07:00 without an answer. Knows nothing logged today. */
    case morning
    /* After a session is logged, and in the evening (T6 runs on Sunday evening). */
    case afterSession
    case evening
}

// MARK: - the five open questions and the tunable numbers

public struct RuleBookSettings: Codable, Equatable, Sendable {
    /* Q1 · keep the plan's own back-to-back quality days (true), or let the app suggest the run quality on Thursday. */
    public var keepBackToBackQuality = true
    /* Q2 · the "something hurts" tap after a session. */
    public var somethingHurtsTap = true
    /* Q3 · a brought-forward easy week leaves the later easy week easy too (true) or makes it a normal week. */
    public var laterEasyWeekStaysEasy = true
    /* Q4 · long sessions grow a step at a time from the longest recent one (L5 and T4 on). */
    public var longSessionsGrowSlowly = true
    /* Q5 · resting pulse is only shown (true), or counts together with a morning answer of 3 or less. */
    public var restingPulseShownOnly = true
    /* T6, the Sunday plan review: off for now (the coach's review), its code and tests kept. No switch on screen. */
    public var planReviewOn = false

    // 8.5 — judgement numbers, tunable
    public var feltHarderMargin = 2
    public var bigWeekFactor = 1.3
    public var behindFraction = 0.4
    public var longStepFraction = 0.10
    public var longStepMinRide = 5
    public var longStepMinRun = 3
    public var lookBackDays = 21
    public var rampCeiling = 1.10
    public var rampWeeks = 3
    public var bigWeekAverageWeeks = 4
    public var tiredCoolDownDays = 4
    public var ladderStepDays = 7
    public var ladderResetDays = 14
    public var longCoolDownDays = 14
    public var bigWeekCoolDownDays = 14
    public var cardsPerSevenDays = 2
    public var cardsPerDay = 1
    public var untouchedAfterTakenDays = 7
    public var hrvStartDay = "2027-01-15"
    public var hrvNightsNeeded = 42

    // From his guide — fixed unless he edits the guide
    public var feverRestHours = 48
    public var feverEasyDays = 2
    public var longFloorPercent = 70
    public var stillNotRightDays = 3
    public var raceWeek = 44
    public var hikesAlwaysCount = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case keepBackToBackQuality, somethingHurtsTap, laterEasyWeekStaysEasy, longSessionsGrowSlowly, restingPulseShownOnly
        case planReviewOn
        case feltHarderMargin, bigWeekFactor, behindFraction, longStepFraction, longStepMinRide, longStepMinRun, lookBackDays
        case rampCeiling, rampWeeks, bigWeekAverageWeeks, tiredCoolDownDays, ladderStepDays, ladderResetDays
        case longCoolDownDays, bigWeekCoolDownDays, cardsPerSevenDays, cardsPerDay, untouchedAfterTakenDays
        case hrvStartDay, hrvNightsNeeded, feverRestHours, feverEasyDays, longFloorPercent, stillNotRightDays, raceWeek
        case hikesAlwaysCount
    }

    /* A number that is missing (an older file) takes its default; one that is there and cannot be read is damage and throws. */
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) throws -> T { try c.decodeIfPresent(T.self, forKey: k) ?? d }
        let d = RuleBookSettings()
        keepBackToBackQuality = try v(.keepBackToBackQuality, d.keepBackToBackQuality)
        somethingHurtsTap = try v(.somethingHurtsTap, d.somethingHurtsTap)
        laterEasyWeekStaysEasy = try v(.laterEasyWeekStaysEasy, d.laterEasyWeekStaysEasy)
        longSessionsGrowSlowly = try v(.longSessionsGrowSlowly, d.longSessionsGrowSlowly)
        // Fixed to "shown only" for now (the coach's review): no switch on screen.
        _ = try v(.restingPulseShownOnly, d.restingPulseShownOnly)
        restingPulseShownOnly = true
        planReviewOn = try v(.planReviewOn, d.planReviewOn)
        feltHarderMargin = try v(.feltHarderMargin, d.feltHarderMargin)
        bigWeekFactor = try v(.bigWeekFactor, d.bigWeekFactor)
        behindFraction = try v(.behindFraction, d.behindFraction)
        longStepFraction = try v(.longStepFraction, d.longStepFraction)
        longStepMinRide = try v(.longStepMinRide, d.longStepMinRide)
        longStepMinRun = try v(.longStepMinRun, d.longStepMinRun)
        lookBackDays = try v(.lookBackDays, d.lookBackDays)
        rampCeiling = try v(.rampCeiling, d.rampCeiling)
        rampWeeks = try v(.rampWeeks, d.rampWeeks)
        bigWeekAverageWeeks = try v(.bigWeekAverageWeeks, d.bigWeekAverageWeeks)
        tiredCoolDownDays = try v(.tiredCoolDownDays, d.tiredCoolDownDays)
        ladderStepDays = try v(.ladderStepDays, d.ladderStepDays)
        ladderResetDays = try v(.ladderResetDays, d.ladderResetDays)
        longCoolDownDays = try v(.longCoolDownDays, d.longCoolDownDays)
        bigWeekCoolDownDays = try v(.bigWeekCoolDownDays, d.bigWeekCoolDownDays)
        cardsPerSevenDays = try v(.cardsPerSevenDays, d.cardsPerSevenDays)
        cardsPerDay = try v(.cardsPerDay, d.cardsPerDay)
        untouchedAfterTakenDays = try v(.untouchedAfterTakenDays, d.untouchedAfterTakenDays)
        hrvStartDay = try v(.hrvStartDay, d.hrvStartDay)
        hrvNightsNeeded = try v(.hrvNightsNeeded, d.hrvNightsNeeded)
        feverRestHours = try v(.feverRestHours, d.feverRestHours)
        feverEasyDays = try v(.feverEasyDays, d.feverEasyDays)
        longFloorPercent = try v(.longFloorPercent, d.longFloorPercent)
        stillNotRightDays = try v(.stillNotRightDays, d.stillNotRightDays)
        raceWeek = try v(.raceWeek, d.raceWeek)
        hikesAlwaysCount = try v(.hikesAlwaysCount, d.hikesAlwaysCount)
    }
}

// MARK: - his taps for section 5

public enum RBIllness: String, Codable, Equatable, Sendable {
    /* "No, a cold above the neck." */ case aboveNeck
    /* "Yes": fever, or chest / body aches. */ case belowNeck
}

public struct RBHealthTaps: Codable, Equatable, Sendable {
    /* "Stop sign" tapped and "A doctor has seen me" not yet. */
    public var stopSignSince: String?
    public var doctorSeenOn: String?
    /* "I'm ill", with its one answer. */
    public var illSince: String?
    public var illness: RBIllness?
    /* "Symptom-free since …" — the day he enters. */
    public var symptomFreeSince: String?
    /* Each "Still not right" tap, by day. */
    public var stillNotRight: [String] = []

    public init(stopSignSince: String? = nil, doctorSeenOn: String? = nil, illSince: String? = nil,
                illness: RBIllness? = nil, symptomFreeSince: String? = nil, stillNotRight: [String] = []) {
        self.stopSignSince = stopSignSince; self.doctorSeenOn = doctorSeenOn; self.illSince = illSince
        self.illness = illness; self.symptomFreeSince = symptomFreeSince; self.stillNotRight = stillNotRight
    }

    enum CodingKeys: String, CodingKey { case stopSignSince, doctorSeenOn, illSince, illness, symptomFreeSince, stillNotRight }

    /* Strict: a tap that is there and cannot be read throws, so a pause never ends without a word. */
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stopSignSince = try c.decodeIfPresent(String.self, forKey: .stopSignSince)
        doctorSeenOn = try c.decodeIfPresent(String.self, forKey: .doctorSeenOn)
        illSince = try c.decodeIfPresent(String.self, forKey: .illSince)
        illness = try c.decodeIfPresent(RBIllness.self, forKey: .illness)
        symptomFreeSince = try c.decodeIfPresent(String.self, forKey: .symptomFreeSince)
        stillNotRight = try c.decodeIfPresent([String].self, forKey: .stillNotRight) ?? []
    }
}

// MARK: - everything a check reads

public struct RuleBookInput {
    public var sessions: [RBSession]
    public var weeks: [RBWeek]
    /* The Monday of plan week 1. */
    public var planStart: String
    /* weekCap[w]: the week's original planned minutes, frozen when the plan was taken in. */
    public var weekCaps: [Int: Int]
    public var extras: [RBExtra]
    /* "How do you feel?" answers, 1 very poor … 5 very good. */
    public var feel: FeelLog
    public var today: String
    public var moment: RBMoment
    /* Past cards and what he answered: the cool-downs and the "2 a week" read it. */
    public var log: [SuggestionRecord]
    public var health: RBHealthTaps
    /* Days he tapped "something hurts" (only read when Q2 is on). */
    public var hurtDays: [String]
    /* Days the app found the resting pulse 5+ above normal for 3 days (only read when Q5 lets it count). */
    public var highPulseDays: [String]
    /* HRV-low days (8.3) and the nights of watch wear since the last measuring change. Dormant until both hold. */
    public var hrvLowDays: [String]
    public var hrvNights: Int
    /* The day the plan was taken into the app: sessions that came in already breaking a limit get one card then. */
    public var importDay: String?
    public var settings: RuleBookSettings

    public init(sessions: [RBSession], weeks: [RBWeek], planStart: String, weekCaps: [Int: Int]? = nil,
                extras: [RBExtra] = [], feel: FeelLog = FeelLog(), today: String, moment: RBMoment = .morning,
                log: [SuggestionRecord] = [], health: RBHealthTaps = RBHealthTaps(), hurtDays: [String] = [],
                highPulseDays: [String] = [], hrvLowDays: [String] = [], hrvNights: Int = 0,
                importDay: String? = nil, settings: RuleBookSettings = RuleBookSettings()) {
        self.sessions = sessions; self.weeks = weeks; self.planStart = planStart
        self.weekCaps = weekCaps ?? RuleBook.weekCaps(sessions)
        self.extras = extras; self.feel = feel; self.today = today; self.moment = moment; self.log = log
        self.health = health; self.hurtDays = hurtDays; self.highPulseDays = highPulseDays
        self.hrvLowDays = hrvLowDays; self.hrvNights = hrvNights; self.importDay = importDay
        self.settings = settings
    }
}

// MARK: - from the app's own book

extension RuleBook {
    /* weekCap[w] = the planned minutes of the sessions written for week w. Freeze this at import. */
    public static func weekCaps(_ sessions: [RBSession]) -> [Int: Int] {
        var caps: [Int: Int] = [:]
        for s in sessions where !s.isRest && !s.addedByMove { caps[s.originalWeek, default: 0] += s.plannedMin }
        return caps
    }

    public static func tag(of week: PlanWeek, raceWeek: Int) -> RBWeekTag {
        let t = normalise(week.tag)
        if week.number == raceWeek || t.contains("race week") { return .race }
        if t.contains("simulation") || t.contains("race sim") { return .sim }
        if t.contains("test") { return .test }
        if t.contains("recovery") || t.contains("easy") { return .easy }
        if t.contains("peak 2") || t.contains("peak2") { return .peak2 }
        if t.contains("wrap") { return .wrapup }
        return .load
    }

    /*
     * The rule book's view of the app's plan. `dropped` holds the sessions an
     * accepted card dropped (the log gives them; the app may pass its own).
     */
    public static func input(book: PlanBook, feel: FeelLog = FeelLog(), extras more: [RBExtra] = [],
                             today: String, moment: RBMoment = .morning, log: [SuggestionRecord] = [],
                             health: RBHealthTaps = RBHealthTaps(), hurtDays: [String] = [],
                             weekCaps: [Int: Int]? = nil, importDay: String? = nil,
                             settings: RuleBookSettings = RuleBookSettings()) -> RuleBookInput {
        let weeks = book.weeks.map { w in
            RBWeek(number: w.number, monday: w.monday, tag: tag(of: w, raceWeek: settings.raceWeek), phase: w.phase,
                   isTaper: normalise(w.phase).contains("taper"))
        }
        let start = planStart(of: book, today: today)
        let dropped = droppedSessions(book)
        var sessions = book.sessions.map { w -> RBSession in
            let a = Stats.actualsOf(w, book.mapping)
            let week = w.planWeek ?? planWeek(w.dayKey, start: start)
            var s = RBSession(
                id: w.key, day: w.dayKey, sport: RBSport(disciplineID: w.discipline.id), title: w.title,
                plannedMin: Int(((Plan.plannedSeconds(w, book.mapping) ?? 0) / 60).rounded()),
                intensity: w.planned.intensity, star: w.isKey, phase: w.phase, row: w.row, originalWeek: week,
                status: w.missed ? .missed : (w.logged ? .done : .open),
                actualMin: a.minutes > 0 ? Int(a.minutes.rounded()) : nil,
                rpe: a.rpe >= 1 ? Int(a.rpe.rounded()) : nil)
            if w.madeInApp && s.sport == .bike { s.slot = .thirdRide }
            if dropped.contains(s.id) { s.dropped = true; s.status = .changed }
            return s
        }
        sessions = assignSlots(sessions, madeInApp: Set(book.sessions.filter(\.madeInApp).map(\.key)))
        var extras = more
        for x in book.extras {
            guard let day = parseDayKey(x.date).flatMap(dayKey), let m = x.minutes, m > 0 else { continue }
            extras.append(RBExtra(day: day, activity: x.activity, minutes: Int(m.rounded()), countsAsTraining: x.isTraining))
        }
        return RuleBookInput(sessions: sessions, weeks: weeks, planStart: start, weekCaps: weekCaps, extras: extras,
                             feel: feel, today: today, moment: moment, log: log, health: health, hurtDays: hurtDays,
                             importDay: importDay, settings: settings)
    }

    /*
     * Sessions a taken card dropped, read from the plan itself — never from
     * this device's log: a rest that says "Rest (your choice)", or a rest whose
     * newest change still standing is a suggestion's. After an Undo, a safety
     * copy put back or another device's change, the plan alone decides.
     */
    public static func droppedSessions(_ book: PlanBook) -> Set<String> {
        var newest: [String: PlanChange] = [:]
        for c in book.changes where !c.undone { newest[c.key] = c }
        var out = Set<String>()
        for w in book.sessions where w.discipline.id == "rest" {
            if w.title == SuggestionApply.restTitle || newest[w.key]?.why.hasPrefix("Suggestion:") == true { out.insert(w.key) }
        }
        return out
    }

    // MARK: week caps (spec 1.1)

    /*
     * The plan's sessions as they were taken in, rebuilt from the change
     * list's saved before-states (the first change of each session holds it).
     * Sessions made in the app are left out.
     */
    public static func takenInSessions(_ book: PlanBook) -> [Workout] {
        var first: [String: PlanChange] = [:]
        for c in book.changes where first[c.key] == nil { first[c.key] = c }
        var out: [Workout] = []
        var seen = Set<String>()
        for w in book.sessions {
            seen.insert(w.key)
            let was = first[w.key].map { $0.kind == "add" ? nil : ($0.undo ?? w) } ?? w
            if let was, !was.madeInApp { out.append(was) }
        }
        for (key, c) in first where !seen.contains(key) && c.kind != "add" {
            if let was = c.undo, !was.madeInApp { out.append(was) }
        }
        return out
    }

    /*
     * Sessions he added on purpose and still has — the Thursday rides and his
     * own new sessions, not a suggestion's copies — each as it was when added.
     * Spec 1.1: the cap moves only when he accepts a plan edit.
     */
    public static func addedOnPurpose(_ book: PlanBook) -> [Workout] {
        book.changes.filter { $0.kind == "add" && !$0.undone && !$0.why.hasPrefix("Suggestion:") }.compactMap { add in
            guard book.session(add.key) != nil else { return nil }
            let later = book.changes.first { $0.key == add.key && $0.kind != "add" && $0.undo != nil }
            return later?.undo ?? book.session(add.key)
        }
    }

    /* The Monday of plan week 1. */
    static func planStart(of book: PlanBook, today: String) -> String {
        book.weeks.first { $0.number == 1 }?.monday
            ?? book.weeks.first.map { PlanView.addDays($0.monday, -7 * ($0.number - 1)) }
            ?? book.sessions.first.map { PlanView.weekStart($0.dayKey) } ?? today
    }

    static func caps(of workouts: [Workout], _ book: PlanBook, today: String) -> [Int: Int] {
        let start = planStart(of: book, today: today)
        var caps: [Int: Int] = [:]
        for w in workouts where w.discipline.id != "rest" {
            let minutes = Int(((Plan.plannedSeconds(w, book.mapping) ?? 0) / 60).rounded())
            caps[w.planWeek ?? planWeek(w.dayKey, start: start), default: 0] += minutes
        }
        return caps
    }

    /* weekCap[w] from the plan as it was taken in: what the app freezes once per plan. */
    public static func takenInCaps(_ book: PlanBook, today: String) -> [Int: Int] {
        caps(of: takenInSessions(book), book, today: today)
    }

    /* The minutes his own added sessions (the Thursday rides among them) give each week. */
    public static func addedCaps(_ book: PlanBook, today: String) -> [Int: Int] {
        caps(of: addedOnPurpose(book), book, today: today)
    }

    /* The two together: the caps the engine reads. */
    public static func weekCaps(frozen: [Int: Int], book: PlanBook, today: String) -> [Int: Int] {
        var out = frozen
        for (w, m) in addedCaps(book, today: today) { out[w, default: 0] += m }
        return out
    }

    /*
     * Slots (3.4), per original week in row order: swim → SWIM · 1st strength → STR_A, 2nd → STR_B ·
     * long bike → LONG_RIDE, other bike → BIKE_Q (a later one → RIDE_3) · long run → LONG_RUN, brick → BRICK,
     * 1st other run → RUN_Q, 2nd → EASY_RUN, a run after a SIM → POST_SIM.
     */
    public static func assignSlots(_ sessions: [RBSession], madeInApp: Set<String> = []) -> [RBSession] {
        var out = sessions
        let byWeek = Dictionary(grouping: out.indices, by: { out[$0].originalWeek })
        for (_, indices) in byWeek {
            var strength = 0, bikes = 0, runs = 0, swims = 0
            var afterSim = false
            for i in indices.sorted(by: { (out[$0].row, out[$0].day) < (out[$1].row, out[$1].day) }) {
                let s = out[i]
                let l = labels(s)
                var slot: RBSlot = .other
                switch s.sport {
                case .rest: slot = .rest
                case .swim: slot = swims == 0 ? .swim : .other; swims += 1
                case .strength: slot = strength == 0 ? .strengthA : (strength == 1 ? .strengthB : .other); strength += 1
                case .bike:
                    if madeInApp.contains(s.id) { slot = .thirdRide }
                    else if l.long { slot = .longRide }
                    else { slot = bikes == 0 ? .bikeQuality : .thirdRide; bikes += 1 }
                case .run:
                    if l.long { slot = .longRun }
                    else if l.brick { slot = .brick }
                    else if afterSim { slot = .postSim }
                    else { slot = runs == 0 ? .runQuality : (runs == 1 ? .easyRun : .other); runs += 1 }
                case .brick: slot = .brick
                default: slot = .other
                }
                afterSim = l.sim
                if out[i].slot == .other || out[i].slot == .rest || !madeInApp.contains(s.id) { out[i].slot = slot }
            }
        }
        return out
    }
}
