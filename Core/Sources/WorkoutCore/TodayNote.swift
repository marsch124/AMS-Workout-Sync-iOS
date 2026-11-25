import Foundation

/*
 * Round 28, "todaynote": what this app tells AMS Deck Mate and PARAGON about today, and the one safe thing
 * they may ask in return ("done"). All pure: the note's content from the plan for a given day, the words,
 * the two links and the guard that decides whether "done from outside" may log. The Keychain and the file
 * are in the app (TodayNote.swift there). No health numbers are in the note, only the plan's own words.
 */

public struct TodayNote: Codable, Equatable {
    /* The format. A reader that knows a lower number than this one reads nothing. */
    public static let format = 1

    public struct Session: Codable, Equatable {
        public var key: String
        /* "swim", "bike", "run", "strength", "mobility" ... or "rest". */
        public var sport: String
        public var sportWord: String
        public var title: String
        /* Whole minutes planned; absent when the plan gives no length. */
        public var minutes: Int?
        /* "45 min", "1 h 10 min"; empty when there is no length. */
        public var length: String
        /* "todo", "done", "missed" or "rest". */
        public var state: String
        /* True when the "done" link below would log this session on this device right now. */
        public var canDone: Bool
        /* amsworkoutsync://session/<key>. */
        public var open: String
        /* amsworkoutsync://done/<key>; only present when canDone is true. */
        public var done: String?
    }

    public var v: Int
    /* Today, yyyy-MM-dd (the phone's own day). A reader whose own today differs must not show the sessions. */
    public var day: String
    /* "Tue 1 Dec". */
    public var dayWords: String
    /* ISO 8601 moment of writing. */
    public var written: String
    public var sessions: [Session]
    /* The first session tomorrow in one line ("Run, 45 min"), "Rest day", or absent when nothing is planned. */
    public var tomorrow: String?
    /* "3 h 20 min done of 6 h planned", or "Nothing planned". */
    public var week: String
    public var weekDoneMinutes: Int
    public var weekPlannedMinutes: Int
}

public enum TodayNoteMaker {
    public static func make(briefs: [SessionBrief], today: String, canLog: Bool, planReady: Bool,
                            weekDoneSeconds: Double, weekPlannedSeconds: Double, now: Date = Date()) -> TodayNote {
        let sessions = briefs.filter { $0.dayKey == today }.map { b -> TodayNote.Session in
            let ok = DoneFromOutside.verdict(briefs: briefs, key: b.key, today: today, canLog: canLog, planReady: planReady).logs
            let state = b.isRest ? "rest" : b.missed ? "missed" : b.done ? "done" : "todo"
            let minutes = (b.plannedSeconds ?? 0) > 0 ? Int(((b.plannedSeconds ?? 0) / 60).rounded()) : nil
            return TodayNote.Session(key: b.key, sport: b.sportID, sportWord: b.sportLabel, title: b.title,
                                     minutes: minutes, length: b.isRest ? "" : SystemWords.lengthWords(b.plannedSeconds),
                                     state: state, canDone: ok, open: SystemLink.sessionURL(b.key),
                                     done: ok ? SystemLink.doneURL(b.key) : nil)
        }
        return TodayNote(v: TodayNote.format, day: today, dayWords: SystemWords.dayWords(today),
                         written: ISO8601DateFormatter().string(from: now), sessions: sessions,
                         tomorrow: tomorrowLine(briefs, PlanView.addDays(today, 1)),
                         week: weekWords(done: weekDoneSeconds, planned: weekPlannedSeconds),
                         weekDoneMinutes: Int((max(weekDoneSeconds, 0) / 60).rounded()),
                         weekPlannedMinutes: Int((max(weekPlannedSeconds, 0) / 60).rounded()))
    }

    /* "Run, 45 min"; "Rest day" when the day holds only rest; nil when the plan has nothing on it. */
    public static func tomorrowLine(_ briefs: [SessionBrief], _ day: String) -> String? {
        let all = briefs.filter { $0.dayKey == day }
        guard !all.isEmpty else { return nil }
        guard let first = all.first(where: { !$0.isRest }) else { return "Rest day" }
        let length = SystemWords.lengthWords(first.plannedSeconds)
        return length.isEmpty ? first.sportLabel : "\(first.sportLabel), \(length)"
    }

    public static func weekWords(done: Double, planned: Double) -> String {
        if planned <= 0 { return "Nothing planned" }
        let d = done > 0 ? SystemWords.lengthWords(done) : "Nothing"
        return "\(d) done of \(SystemWords.lengthWords(planned)) planned"
    }

    /* What counts as "the same" for rewriting: everything but the moment of writing. */
    public static func sameContent(_ a: TodayNote, _ b: TodayNote) -> Bool {
        var x = a; x.written = ""
        var y = b; y.written = ""
        return x == y
    }

    /* The bytes: sorted keys, plain JSON. */
    public static func encoded(_ note: TodayNote) -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try? e.encode(note)
    }
}

/*
 * "Done" asked from outside (amsworkoutsync://done/<key>): logs the session as planned only when it is
 * exactly what the in-app button would log. Anything else opens the session and changes nothing.
 */
public enum DoneFromOutside {
    public enum Verdict: Equatable {
        case log(SessionBrief)
        /* Nothing changes; the app opens on this session (or on Today when the key is unknown). */
        case openOnly(Why)
        public var logs: Bool { if case .log = self { return true } else { return false } }
    }

    public enum Why: Equatable {
        case planNotReady, loggingNotAllowed, unknownSession, notToday, rest, alreadyDone, missed, noLength
    }

    public static func verdict(briefs: [SessionBrief], key: String, today: String, canLog: Bool, planReady: Bool) -> Verdict {
        guard planReady else { return .openOnly(.planNotReady) }
        guard let b = briefs.first(where: { $0.key == key }) else { return .openOnly(.unknownSession) }
        guard b.dayKey == today else { return .openOnly(.notToday) }
        if b.isRest { return .openOnly(.rest) }
        if b.done { return .openOnly(.alreadyDone) }
        if b.missed { return .openOnly(.missed) }
        if (b.plannedSeconds ?? 0) <= 0 { return .openOnly(.noLength) }
        guard canLog else { return .openOnly(.loggingNotAllowed) }
        return .log(b)
    }
}

extension SystemLink {
    private static let safeKey: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~")
        return s
    }()

    /* amsworkoutsync://done/<key>. */
    public static func doneURL(_ key: String) -> String {
        "amsworkoutsync://done/" + (key.addingPercentEncoding(withAllowedCharacters: safeKey) ?? key)
    }

    /* The key of a done link (host "done", the path already decoded), or nil. */
    public static func doneKey(host: String?, path: String) -> String? {
        guard host == "done" else { return nil }
        let key = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return key.isEmpty ? nil : key
    }
}
