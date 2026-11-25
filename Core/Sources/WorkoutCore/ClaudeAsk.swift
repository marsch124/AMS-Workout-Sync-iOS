import Foundation

/*
 * "Ask about your plan": the pure part.
 *
 * He types a question; Claude explains the plan and the rule book INSIDE the
 * rule book. It never changes the plan, and its answer has no button that
 * does: when he asks for a change it says what the rule book allows and points
 * to the app's own buttons (Move, Change, the suggestion card). Anything about
 * illness or pain never leaves the phone: the app answers it itself with one
 * fixed line. Everything Claude writes passes the same word check as the rest.
 */

/* One coming or past day of the plan, as one short line ("Tue bike 60 min Z2; strength 30 min"). */
public struct ClaudeAskDay: Equatable, Sendable {
    public var day: String
    public var sessions: String
    public init(day: String, sessions: String) { self.day = day; self.sessions = sessions }
}

public struct ClaudeAskPlan: Equatable, Sendable {
    public var today: String
    /* "Build 2, week 12, test week" */
    public var phase: String
    /* The current week and the next two, day by day. */
    public var days: [ClaudeAskDay]
    /* Names only: "Zone 1", "Zone 2" … never a figure. */
    public var zoneNames: [String]

    public init(today: String, phase: String, days: [ClaudeAskDay], zoneNames: [String]) {
        self.today = today; self.phase = phase; self.days = days; self.zoneNames = zoneNames
    }
}

public struct ClaudeAskItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public let at: Date
    public let question: String
    public let answer: String
    /* The app's own fixed answer: nothing was sent. */
    public let local: Bool
    public init(id: UUID = UUID(), at: Date, question: String, answer: String, local: Bool = false) {
        self.id = id; self.at = at; self.question = question; self.answer = answer; self.local = local
    }
}

public enum ClaudeAsk {
    public static let maxTokens = 1200
    public static let longestQuestion = 300
    public static let longestAnswer = 900
    public static let kept = 5

    public static let examples = ["Why is Thursday\u{2019}s ride only 45 minutes?",
                                  "What does this week\u{2019}s easy week change?",
                                  "Can I move Saturday\u{2019}s long run to Sunday?"]

    public static let sentWords = "Your question, this week and the next two weeks of the plan (day, sport, minutes, effort), the phase, the rule book\u{2019}s limits in words, and the names of your zones \u{2014} no figures, no names, no notes."
    public static let costWords = "It counts toward the 5 US dollars a month."
    public static let didNotPass = "Claude\u{2019}s answer did not pass the app\u{2019}s check \u{2014} nothing shown."
    public static let nothingCame = "No answer came back. Try again in a minute."
    public static let noChange = "Claude explains only. To change something, use Move or Change on a session, or the suggestion card on Today."
    /* Illness and pain are never put to Claude. */
    public static let doctorLine = "That is a question for a doctor. The app\u{2019}s Stop sign page is under Not well? at the foot of Today."

    public static let system = """
    You explain ONE athlete's training plan and the app's rule book, in plain British English, in at most 120 words. Answer only from the plan and rules you are given, inside them. You never change the plan.
    If he wants a change, say what the rule book allows and point to the app's own buttons: Move or Change on a session, or the suggestion card on Today. Never offer a button or a step of your own.
    No medical advice: for illness or pain say only "That is a question for a doctor; the app's Stop sign page is under Not well?". Never promise or guess race times. Say "Zone 2", never heart rate, pulse or HRV. Never mention sleep.
    Reply with the JSON only: {"answer": "<text>"}.
    """

    // MARK: the gate

    private static let illWords: Set<String> = ["ill", "illness", "sick", "fever", "flu", "cold", "covid", "cough", "nausea", "faint",
                                                 "dizzy", "dizziness", "doctor", "hurt", "hurts", "hurting", "pain", "painful", "ache",
                                                 "aches", "aching", "sore", "niggle", "symptom", "symptoms", "breathless", "breathlessness"]
    private static let illPrefixes = ["injur", "medic", "diagnos", "infect", "chest"]

    /* Whether the question is about illness or pain: then it is answered here and never sent. */
    public static func isAboutIllness(_ question: String) -> Bool {
        let words = question.lowercased().split(whereSeparator: { !($0.isLetter || $0 == "\u{2019}" || $0 == "'") }).map(String.init)
        return words.contains { illWords.contains($0) || illPrefixes.contains(where: $0.hasPrefix) }
    }

    /* The question as it is sent: one line, control marks gone, not too long; nil when nothing is left. */
    public static func cleanQuestion(_ raw: String) -> String? {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }
        let one = ClaudeWords.oneLine(String(String.UnicodeScalarView(scalars)))
        guard !one.isEmpty else { return nil }
        return String(one.prefix(longestQuestion))
    }

    // MARK: the rule book in words

    public static func rulesInWords(_ s: RuleBookSettings = RuleBookSettings()) -> String {
        let ramp = Int(((s.rampCeiling - 1) * 100).rounded())
        let step = Int((s.longStepFraction * 100).rounded())
        return [
            "Friday is the rest day: a change never leaves a training session on a Friday.",
            "A change never makes two hard days in a row (the plan\u{2019}s own pairs are left alone).",
            "A week never goes over the planned minutes it first had.",
            "A week may grow only up to \(ramp) per cent above the average of the last \(s.rampWeeks) weeks.",
            "A long ride or long run grows a step at a time: about \(step) per cent, at least \(s.longStepMinRide) minutes for a ride and \(s.longStepMinRun) for a run, from the longest of the last \(s.lookBackDays) days.",
            "Protected sessions (the key sessions, easy weeks and the taper) are never cut, shortened, made easier or moved by a suggestion; easy weeks and the taper only get easier.",
            "A suggestion never makes anything harder or longer and never adds a session.",
            "Missed sessions are gone: nothing is made up afterwards.",
            "The Monday swim never goes two weeks running.",
            "After a fever nothing is suggested for \(s.feverRestHours) hours; the Stop sign and I\u{2019}m ill steps are his own taps.",
            "Calm: one open suggestion, one a day, \(s.cardsPerSevenDays) a week, none in race week (week \(s.raceWeek)); a change he took is left alone for a week.",
            "A suggestion comes only from a fixed menu of moves, and nothing in the plan moves without his own tap. He can always change a session himself with Move or Change; the app then shows one calm grey line if that breaks a rule, and lets him go on.",
        ].map { "- " + $0 }.joined(separator: "\n")
    }

    // MARK: what is sent

    public static func request(question: String, plan: ClaudeAskPlan, settings: RuleBookSettings = RuleBookSettings()) -> (system: String, user: String) {
        var lines: [String] = []
        lines.append("Today is \(plan.today).")
        if !plan.phase.isEmpty { lines.append("The phase: \(plan.phase).") }
        lines.append("")
        lines.append("The rule book's limits, in words:")
        lines.append(rulesInWords(settings))
        lines.append("")
        lines.append("His zones (names only): " + (plan.zoneNames.isEmpty ? "none entered" : plan.zoneNames.joined(separator: ", ")) + ".")
        lines.append("")
        lines.append("The plan, this week and the next two (minutes; done or missed where it is):")
        for d in plan.days { lines.append("\(d.day): \(d.sessions)") }
        lines.append("")
        lines.append("His question: \(question)")
        return (system, lines.joined(separator: "\n"))
    }

    public static func body(system: String, user: String) -> Data {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["answer": ["type": "string"]],
            "required": ["answer"],
            "additionalProperties": false,
        ]
        let root: [String: Any] = [
            "model": ClaudePick.model,
            "max_tokens": maxTokens,
            "fallbacks": "default",
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
    }

    // MARK: what comes back

    /* The answer as it may be shown, or nil: short, plain text, no medical words, passes the rule book's word check. */
    public static func cleanAnswer(_ raw: String) -> String? {
        let text = ClaudeWords.oneLine(raw)
        guard !text.isEmpty, text.count <= longestAnswer, ClaudeWords.passes(text, allowPraise: true) else { return nil }
        return text
    }

    public static func read(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stop = root["stop_reason"] as? String, stop == "end_turn" || stop == "stop_sequence",
              let blocks = root["content"] as? [[String: Any]],
              let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let inner = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let answer = inner["answer"] as? String else { return nil }
        return cleanAnswer(answer)
    }

    /* DEBUG pictures and the fake switch. */
    public static let inventedQuestion = "Why is Thursday\u{2019}s ride only 45 minutes?"
    public static let inventedAnswer = "Thursday is the lighter day between the Wednesday run and the long ride on Saturday, so the plan keeps it short and easy. The rule book does not let a suggestion make a session longer. If you want it different, use Move or Change on that session; the app will show one grey line if it breaks a rule, and you can still go on."

    // MARK: the plan as text

    /* This week and the next two, day by day, from the app's own plan. Titles are left out: only day, sport, minutes and effort. */
    public static func plan(book: PlanBook, today: String) -> ClaudeAskPlan {
        let monday = PlanView.weekStart(today)
        var days: [ClaudeAskDay] = []
        for i in 0..<21 {
            let day = PlanView.addDays(monday, i)
            let of = book.sessions.filter { $0.dayKey == day && $0.discipline.id != "rest" }
            let names = ClaudeExport.weekdays
            let text = of.isEmpty ? "rest" : of.map { w -> String in
                var s = w.discipline.label
                if let p = Plan.plannedSeconds(w, book.mapping), p > 0 { s += " \(ClaudeExport.figure(p / 60)) min" }
                if !w.planned.intensity.isEmpty { s += " " + w.planned.intensity }
                if w.missed { s += " (missed)" } else if w.logged { s += " (done)" }
                return s
            }.joined(separator: "; ")
            days.append(ClaudeAskDay(day: "\(names[i % 7]) \(day)", sessions: text))
        }
        var phase = ""
        if let w = book.weeks.first(where: { $0.monday == monday }) {
            phase = "\(w.phase.isEmpty ? "no named phase" : w.phase), week \(w.number)" + (w.tag.isEmpty ? "" : ", " + w.tag.lowercased())
        }
        var zones: [String] = []
        if let z = book.zones {
            for table in z.tables {
                for row in table.rows where !zones.contains(row.label) { zones.append(row.label) }
            }
        }
        return ClaudeAskPlan(today: today, phase: phase, days: days, zoneNames: Array(zones.prefix(12)))
    }
}

// MARK: - kept on the device

public protocol ClaudeAskStoring {
    func load() -> [ClaudeAskItem]
    func save(_ items: [ClaudeAskItem])
}

/* Per device: the last five questions and answers, in UserDefaults. */
public struct UserDefaultsAskStore: ClaudeAskStoring {
    static let key = "claude-ask-history"
    let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> [ClaudeAskItem] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ClaudeAskItem].self, from: data)) ?? []
    }

    public func save(_ items: [ClaudeAskItem]) {
        if items.isEmpty { defaults.removeObject(forKey: Self.key); return }
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.key) }
    }
}

extension Array where Element == ClaudeAskItem {
    /* Newest first, the last five. */
    public func adding(_ item: ClaudeAskItem) -> [ClaudeAskItem] {
        Array(([item] + self).prefix(ClaudeAsk.kept))
    }
}
