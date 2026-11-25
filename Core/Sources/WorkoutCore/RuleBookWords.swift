import Foundation

/*
 * Every sentence a card can say: one change line, one reason line, the three
 * buttons and the footer. Plain, calm British English; fixed templates only
 * (L13) — no "healthy", "fit", "safe" or "your heart", ever.
 */
extension RuleBookWords {
    public static let takeIt = "Take it"
    public static let keepMyPlan = "Keep my plan"
    public static let otherChoice = "Other choice"
    public static let showMe = "Show me"
    public static let footer = "Training suggestion — not medical advice."
    public static let gone = "Gone — no catching up needed."
    public static let travelling = "Travelling? Run outside, use a hotel bike or rower for the aerobic minutes, do bodyweight strength. Match the minutes and the zone, not the exact workout."
    public static let droppedLabel = "rest (your choice)"
    public static let changedUndo = "Changed — Undo"
    public static let niggleLine = "Calf, Achilles or knee niggle? Make this a row or an easy spin instead."

    // MARK: why-lines (spec section 4)

    public static let whyPoorMornings = "Why: you felt poor two mornings running."
    public static let whyHardSessions = "Why: two sessions this week felt much harder than planned."
    public static let whyStillTired = "Why: still tired after the rest day."
    public static let whyTiredOverWeek = "Why: tired signs for over a week; your guide brings the easy week forward."
    public static let whyTwoTiredWeeks = "Why: two tired weeks in a row — your guide says: easy week now."
    public static let whyMissedKey = "Why: you missed 2 days; your guide keeps the key session and drops an easy one."
    public static func whyMissedKey(days: Int) -> String {
        "Why: you missed \(days) days; your guide keeps the key session and drops an easy one."
    }
    public static func whyBackShort(days: Int) -> String { "Why: welcome back after \(days) days off; ease in for two days." }
    public static let whyBackLong = "Why: welcome back. Your guide: one easy week for each week off."
    public static func whyLong(sport: RBSport, longest: Int) -> String {
        let word = sport == .bike ? "ride" : "run"
        return "Why: your longest \(word) in the last 3 weeks was \(longest) min; long \(word)s grow a step at a time."
    }
    public static func whyBigWeek(ratio: Double, hikes: Bool = true) -> String {
        "Why: last week\(hikes ? ", with the hikes," : "") you trained \(ratioWords(ratio)) your planned time."
    }
    public static func whyBehind(weeks: Int) -> String {
        weeks <= 2 ? "Why: your guide cuts one normal week from this phase and keeps the easy week."
            : weeks <= 4 ? "Why: your guide shortens the early phases by a week each and keeps both race simulations."
            : "Why: your guide plans again around the days that cannot move."
    }
    public static func whyCameIn(easyWeek: Bool, isRun: Bool) -> String {
        let what = isRun ? "run" : "session"
        return easyWeek ? "Why: it is last week's \(what); missed sessions are not made up, and this is your easy week."
            : "Why: it is last week's \(what); missed sessions are not made up, and this week is already full."
    }
    public static let whyHurts = "Why: you said something hurts; your guide makes the Thursday run a row or an easy spin."
    public static let whyBackToBack = "Why: hard bike and hard run on two days in a row; you asked for the run quality on Thursday."

    /* "a third more", "half again", "about twice" … in words, never a percentage. */
    public static func ratioWords(_ r: Double) -> String {
        switch r {
        case ..<1.42: return "about a third more than"
        case ..<1.75: return "about half again"
        case ..<2.5: return "about twice"
        default: return "well over twice"
        }
    }

    // MARK: change lines

    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    public static func day(_ key: String) -> String { dayNames[RuleBook.weekday(key)] }

    public static func sport(_ s: RBSession) -> String {
        let l = RuleBook.labels(s)
        switch s.sport {
        case .run: return l.long ? "long run" : (l.brick ? "brick run" : "run")
        case .bike: return "bike"
        case .swim: return "swim"
        case .strength: return "strength"
        case .brick: return "brick"
        case .race: return "race"
        case .rest: return "rest"
        case .other: return "session"
        }
    }

    /* "Wed run" */
    public static func name(_ s: RBSession) -> String { day(s.day) + " " + sport(s) }

    /* "Wed run: 50 min → rest" (M1, M7 on a one-session day) */
    public static func dropLine(_ s: RBSession) -> String {
        let long = RuleBook.labels(s).long
        let what = long ? " " + (s.sport == .bike ? "long ride" : "long run") : ""
        let label = long ? day(s.day) + " " + (s.sport == .bike ? "bike" : "run") : name(s)
        return "\(label): \(s.plannedMin) min\(what) → rest"
    }

    /* "Wed run: 50 → 35 min, easy" / "Sun bike: 115 → 90 min" / "Tue bike → easy" */
    public static func easierLine(_ s: RBSession, minutes: Int?, easier: Bool, instead: RBSubstitute? = nil) -> String {
        let label = RuleBook.labels(s).long ? day(s.day) + " " + (s.sport == .bike ? "bike" : "run") : name(s)
        var line = label
        if let minutes, minutes != s.plannedMin { line += ": \(s.plannedMin) → \(minutes) min" }
        if let instead { return line + (instead == .row ? " → row, same minutes, easy" : " → easy spin, same minutes") }
        if easier { line += minutes == nil || minutes == s.plannedMin ? " → easy" : ", easy" }
        return line
    }

    /* "Next 3 days easy: Tue bike, Wed run → easy" */
    public static func easyDaysLine(count: Int, sessions: [RBSession]) -> String {
        "Next \(count) days easy: " + sessions.map(name).joined(separator: ", ") + " → easy"
    }

    /* "Sat long run → Thu (instead of the easy run)" */
    public static func keySwapLine(_ key: RBSession, to day: String, replacing e: RBSession) -> String {
        "\(name(key)) → \(Self.day(day)) (instead of the \(replacedWord(e)))"
    }

    static func replacedWord(_ s: RBSession) -> String {
        switch s.slot {
        case .easyRun: return "easy run"
        case .strengthB: return "second strength session"
        case .swim: return "swim"
        case .thirdRide: return "third ride"
        default: return sport(s)
        }
    }

    /* "Wed run ⇄ Thu run" in words */
    public static func swapLine(_ a: RBSession, _ b: RBSession) -> String {
        "\(name(a)) swaps with \(name(b))"
    }

    public static func moveLine(_ s: RBSession, to day: String) -> String { "\(name(s)) → \(Self.day(day))" }

    public static func easyWeekLine(wasMonday: String?) -> String {
        guard let m = wasMonday, let d = parseDayKey(m) else { return "This week becomes your easy week" }
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"
        return "This week becomes your easy week (was \(f.string(from: d)))"
    }

    public static func reviewLine(weeks: Int) -> String {
        weeks == 1 ? "Plan review: you are about a week behind" : "Plan review: you are about \(weeks) weeks behind"
    }

    // MARK: his own edits

    /* One calm grey line; never a block. */
    public static func ownEditWarning(_ f: LimitFailure) -> String {
        switch f.limit {
        case .l1: return "Friday is your rest day. Move anyway?"
        case .l2: return "That makes two hard days in a row. Change anyway?"
        case .l3: return "That week goes over its planned time. Change anyway?"
        case .l6: return "This one is protected in your plan. Change anyway?"
        case .l8: return "Missed sessions are not made up. Move anyway?"
        default: return f.reason
        }
    }
}

extension RuleBook {
    static func dayWord(_ key: String) -> String { RuleBookWords.day(key) }
    static func sportWord(_ s: RBSession) -> String { RuleBookWords.sport(s) }
}
