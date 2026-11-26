import Foundation

/*
 * What the system (Spotlight, Siri, the keyboard) says about the plan. All
 * pure: which sessions are put into Spotlight and in which words, the
 * sentences Siri speaks, which session "Log today's run" means, and the
 * address a Spotlight result opens. The app files only hand over data.
 */

/* One session, as much as the system parts need to know. */
public struct SessionBrief: Equatable {
    public let key: String
    public let dayKey: String
    public let sportID: String
    public let sportLabel: String
    public let title: String
    public let plannedSeconds: Double?
    public let done: Bool
    public let missed: Bool

    public init(key: String, dayKey: String, sportID: String, sportLabel: String, title: String,
                plannedSeconds: Double?, done: Bool, missed: Bool) {
        self.key = key; self.dayKey = dayKey; self.sportID = sportID; self.sportLabel = sportLabel
        self.title = title; self.plannedSeconds = plannedSeconds; self.done = done; self.missed = missed
    }

    public init(_ w: Workout, _ mapping: Mapping) {
        self.init(key: w.key, dayKey: w.dayKey, sportID: w.discipline.id, sportLabel: w.discipline.label, title: w.title,
                  plannedSeconds: Plan.plannedSeconds(w, mapping), done: w.logged && !w.missed, missed: w.missed)
    }

    public var isRest: Bool { sportID == "rest" }
}

/* One line for the system's search: its words and the words people may type to find it. */
public struct SpotlightEntry: Equatable {
    public let key: String
    public let title: String
    public let detail: String
    public let keywords: [String]
}

public enum SystemWords {
    // MARK: days and lengths

    private static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let weekdayFull = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func parts(_ key: String) -> (weekday: Int, day: Int, month: Int)? {
        guard let date = parseDayKey(key) else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let p = c.dateComponents([.weekday, .day, .month], from: date)
        guard let w = p.weekday, let d = p.day, let m = p.month else { return nil }
        return (w - 1, d, m - 1)
    }

    /* "Tue 1 Dec". */
    public static func dayWords(_ key: String) -> String {
        guard let p = parts(key) else { return key }
        return "\(weekdayShort[p.weekday]) \(p.day) \(monthShort[p.month])"
    }

    /* "Tuesday". */
    public static func weekdayName(_ key: String) -> String {
        parts(key).map { weekdayFull[$0.weekday] } ?? ""
    }

    /* "40 min", "1 h 10 min", "2 h": the way it is spoken and read in a search result. */
    public static func lengthWords(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    // MARK: Spotlight

    /* The window of days put into the system's search: the next 14 days still to do, and the last 14 days' done ones. */
    public static let spotlightDays = 14

    public static func spotlightEntries(_ briefs: [SessionBrief], today: String) -> [SpotlightEntry] {
        let last = PlanView.addDays(today, spotlightDays - 1)
        let first = PlanView.addDays(today, -spotlightDays)
        let chosen = briefs.filter { b in
            guard !b.isRest, !b.missed else { return false }
            if b.done { return b.dayKey >= first && b.dayKey <= today }
            return b.dayKey >= today && b.dayKey <= last
        }
        .sorted { ($0.dayKey, $0.key) < ($1.dayKey, $1.key) }
        return chosen.map { b in
            let length = lengthWords(b.plannedSeconds)
            var title = "\(dayWords(b.dayKey)) \u{00B7} \(b.sportLabel)"
            if !length.isEmpty { title += " \u{00B7} \(length)" }
            var words: [String] = [b.sportLabel, b.sportLabel.lowercased(), weekdayName(b.dayKey), String(weekdayName(b.dayKey).prefix(3)),
                                   dayWords(b.dayKey), "session", "training", "triathlon"]
            words += b.title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 }
            var seen = Set<String>()
            let keywords = words.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            let detail = b.done ? "Done" : "To do"
            return SpotlightEntry(key: b.key, title: title, detail: b.title.isEmpty ? detail : "\(b.title) \u{00B7} \(detail)", keywords: keywords)
        }
    }

    // MARK: Siri

    private static func line(_ b: SessionBrief) -> String {
        let length = lengthWords(b.plannedSeconds)
        let core = length.isEmpty ? b.sportLabel : "\(b.sportLabel), \(length)"
        return b.done ? core + ", done" : core
    }

    /* "Today: Swim, 40 min, and Run, 45 min." or "Today is a rest day." `word` is "Today" or "Tomorrow". */
    public static func spokenDay(_ briefs: [SessionBrief], day: String, word: String) -> String {
        let sessions = briefs.filter { $0.dayKey == day && !$0.isRest }
        if sessions.isEmpty { return "\(word) is a rest day." }
        let lines = sessions.map(line)
        if lines.count == 1 { return "\(word): \(lines[0])." }
        return "\(word): " + lines.dropLast().joined(separator: ", ") + ", and " + lines[lines.count - 1] + "."
    }

    /* "This week: 3 h 20 min done of 6 h planned." */
    public static func spokenWeek(doneSeconds: Double, plannedSeconds: Double) -> String {
        if plannedSeconds <= 0 { return "Nothing is planned this week." }
        let done = doneSeconds > 0 ? lengthWords(doneSeconds) : "Nothing"
        return "This week: \(done) done of \(lengthWords(plannedSeconds)) planned."
    }

    /* What "Log today's <sport> as done" means. Nothing is logged unless it is exactly one open session of that sport. */
    public enum LogPick: Equatable {
        case log(SessionBrief)
        case noSession
        case two
        case alreadyDone(SessionBrief)
        case missed(SessionBrief)
        case noLength(SessionBrief)
    }

    public static func pickToLog(_ briefs: [SessionBrief], today: String, sportID: String) -> LogPick {
        let same = briefs.filter { $0.dayKey == today && $0.sportID == sportID }
        if same.isEmpty { return .noSession }
        if same.count > 1 { return .two }
        let one = same[0]
        if one.done { return .alreadyDone(one) }
        if one.missed { return .missed(one) }
        if (one.plannedSeconds ?? 0) <= 0 { return .noLength(one) }
        return .log(one)
    }

    public static func loggedWords(_ b: SessionBrief) -> String {
        let length = lengthWords(b.plannedSeconds)
        return length.isEmpty ? "Logged: \(b.sportLabel)" : "Logged: \(b.sportLabel) \u{00B7} \(length)"
    }

    public static func refusal(_ pick: LogPick, sport: String) -> String {
        switch pick {
        case .log: return ""
        case .noSession: return "There is no \(sport.lowercased()) planned today. Nothing was logged."
        case .two: return "There are two \(sport.lowercased()) sessions today. Nothing was logged; open the app and choose."
        case .alreadyDone(let b): return "Today's \(b.sportLabel.lowercased()) is already done. Nothing was changed."
        case .missed(let b): return "Today's \(b.sportLabel.lowercased()) is marked as missed. Nothing was changed."
        case .noLength(let b): return "Today's \(b.sportLabel.lowercased()) has no planned length, so \"done as planned\" has nothing to log. Nothing was changed."
        }
    }
}

/* The address a Spotlight result (or any link) opens: amsworkoutsync://session/<key>. */
public enum SystemLink {
    private static let safe: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~")
        return s
    }()

    public static func sessionURL(_ key: String) -> String {
        "amsworkoutsync://session/" + (key.addingPercentEncoding(withAllowedCharacters: safe) ?? key)
    }

    /* 2.11 — the pages a link opens (AMS Deck Mate's page group "Triathlon"): amsworkoutsync://plan, …/sessions,
       …/body, …/progress, …/settings. amsworkoutsync://today stays as it was. */
    public static let pages = ["plan", "sessions", "body", "progress", "settings"]

    /* The page a link names in its host, or nil when it names none of `pages`. */
    public static func page(host: String?) -> String? {
        guard let name = host?.lowercased(), pages.contains(name) else { return nil }
        return name
    }

    /* The session key in a link's host and path (the path already decoded, as URL gives it), or nil if the link is not a session link. */
    public static func sessionKey(host: String?, path: String) -> String? {
        guard host == "session" else { return nil }
        let key = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return key.isEmpty ? nil : key
    }
}
