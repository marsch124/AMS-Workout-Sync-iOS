import Foundation

/*
 * "Your week with Claude": the pure part.
 *
 * From Sunday 17:00 until the end of Monday one card on Today may ask Claude to
 * look back at the week: five short lines (facts and patterns) and ONE question
 * for him to think about. Everything Claude sends back is checked here, line by
 * line; anything off gives nil and nothing is shown. Nothing in this file
 * touches the network, the Keychain or the disk (except the small stores at the
 * foot, which only read and write their own preference key).
 */

/* The word check every free-text answer of Claude passes before it is shown. */
public enum ClaudeWords {
    /* Praise and judging words: the review states facts, it does not cheer or grade. */
    static let praise = ["well done", "excellent", "amazing", "fantastic", "brilliant", "congrat", "proud", "good job",
                         "awesome", "superb", "impressive", "fabulous", "wonderful", "no improvement", "disappoint"]

    /* Plain text, never medical, never about sleep, passes the rule book's own word check (L13). */
    public static func passes(_ text: String, allowPraise: Bool = false) -> Bool {
        let lower = text.lowercased()
        guard !text.isEmpty else { return false }
        guard !ClaudePick.blocked.contains(where: { lower.contains($0) }),
              !ClaudePick.notPlain.contains(where: { lower.contains($0) }) else { return false }
        if !allowPraise, praise.contains(where: { lower.contains($0) }) { return false }
        guard !text.unicodeScalars.contains(where: { ClaudePick.markup.contains($0) || CharacterSet.controlCharacters.contains($0) }) else { return false }
        return RuleBook.l13Words([text]) == nil
    }

    /* The digit runs of a text ("120 / 150 min" gives 120, 150). */
    public static func numbers(in text: String) -> Set<String> {
        var out = Set<String>(), run = ""
        for ch in text {
            if ch.isASCII, ch.isNumber { run.append(ch) } else { if !run.isEmpty { out.insert(run) }; run = "" }
        }
        if !run.isEmpty { out.insert(run) }
        return out
    }

    /* One line: whitespace folded. */
    public static func oneLine(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

public struct ClaudeReviewAnswer: Codable, Equatable, Sendable {
    public let lines: [String]
    public let question: String
    public init(lines: [String], question: String) { self.lines = lines; self.question = question }
}

/* One written week, as kept on the device. */
public struct ClaudeSavedReview: Codable, Equatable, Identifiable, Sendable {
    public var id: String { week }
    /* The Monday of the week it is about. */
    public let week: String
    public let writtenAt: Date
    public let answer: ClaudeReviewAnswer
    public init(week: String, writtenAt: Date, answer: ClaudeReviewAnswer) {
        self.week = week; self.writtenAt = writtenAt; self.answer = answer
    }
}

public enum ClaudeReview {
    public static let lineCount = 5
    public static let longestLine = 140
    public static let longestQuestion = 160
    /* Small on purpose: five lines and a question are well under 300 tokens. */
    public static let maxTokens = 1200

    /* What the card says before the first use, word for word. */
    public static let sentWords = "This week\u{2019}s training numbers and your answers to the two questions \u{2014} no names, no notes."
    public static let costWords = "It counts toward the 5 US dollars a month."
    public static let didNotPass = "Claude\u{2019}s answer did not pass the app\u{2019}s check \u{2014} nothing shown."
    public static let nothingCame = "No answer came back. Nothing was changed."

    public static let system = """
    You write a short, calm look back at ONE week of training for an amateur athlete preparing for a half-distance triathlon. You are given only that week's numbers. You change nothing and give no instructions.
    Reply with the JSON only: {"lines": ["...", "...", "...", "...", "..."], "question": "..."}.
    Exactly five lines. Each line is ONE plain sentence in British English, at most 120 characters: a fact or a pattern from the numbers (planned against done, how the mornings were, how hard sessions felt against the plan, what was missed or moved, what comes next week). No praise and no blame, no cheering words, no medical talk. Never mention sleep or say anything was caused by sleep. Use only numbers that appear in the week's numbers; do not add up or work out new ones.
    Then ONE question for him to think about: a question, not advice, ending with a question mark, at most 140 characters.
    """

    // MARK: when

    /* Sunday from 17:00 until the end of Monday, by the clock on the device. */
    public static func inWindow(now: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        return (weekday == 1 && hour >= 17) || weekday == 2
    }

    /* The Monday of the week being looked back at: this week's on Sunday, last week's on Monday. */
    public static func week(today: String) -> String {
        let monday = PlanView.weekStart(today)
        return monday == today ? PlanView.addDays(monday, -7) : monday
    }

    // MARK: what is sent

    static let sportOrder: [RBSport] = [.swim, .bike, .run, .strength, .brick, .race, .other]

    /* The week's facts as the one text Claude is given. Day names, sports, minutes, the five mood words, effort figures: nothing else. */
    public static func userText(from input: RuleBookInput, monday: String) -> String {
        let days = (0..<7).map { PlanView.addDays(monday, $0) }
        let inWeek = input.sessions.filter { days.contains($0.day) && $0.sport != .rest }
        var out: [String] = []
        out.append("The week looked back at: \(RuleBookWords.day(days[0])) \(days[0]) to \(RuleBookWords.day(days[6])) \(days[6]).")

        // Planned against done, per sport.
        out.append("Minutes done / planned, per sport:")
        var totalDone = 0, totalPlanned = 0
        for sport in sportOrder {
            let mine = inWeek.filter { $0.sport == sport && $0.counts }
            guard !mine.isEmpty else { continue }
            let planned = mine.reduce(0) { $0 + $1.plannedMin }
            let done = mine.filter { $0.status == .done }.reduce(0) { $0 + ($1.actualMin ?? $1.plannedMin) }
            totalDone += done; totalPlanned += planned
            out.append("\(sport.rawValue): \(done) / \(planned)")
        }
        if totalPlanned == 0 { out.append("nothing planned") }
        out.append("Total: \(totalDone) / \(totalPlanned)")

        // The mornings, in his five words.
        let mornings = days.map { d in "\(RuleBookWords.day(d)) \(input.feel.answer(on: d)?.word ?? "no answer")" }
        out.append("How he felt each morning: " + mornings.joined(separator: ", ") + ".")

        // How hard it felt (1 to 10) against what the plan said.
        let felt = inWeek.filter { $0.status == .done && ($0.rpe ?? 0) > 0 }
        if felt.isEmpty {
            out.append("How hard sessions felt: nothing answered.")
        } else {
            out.append("How hard sessions felt, 1 to 10, against the plan's own effort:")
            for s in felt.prefix(8) {
                let plan = s.intensity.isEmpty ? "" : " (planned: \(s.intensity))"
                out.append("\(RuleBookWords.name(s)): felt \(s.rpe ?? 0) of 10\(plan)")
            }
        }

        // Missed, moved, changed.
        let missed = inWeek.filter { $0.status == .missed }
        let moved = input.sessions.filter { $0.sport != .rest && $0.counts && input.week(of: $0.day) != $0.originalWeek
            && (days.contains($0.day) || input.week(of: monday) == $0.originalWeek) }
        let changed = inWeek.filter { $0.status == .changed || $0.dropped }
        out.append("Missed: \(missed.count)" + (missed.isEmpty ? "." : " (" + missed.map { "\(RuleBookWords.name($0)) \($0.plannedMin) min" }.joined(separator: ", ") + ")."))
        out.append("Moved to another day or week: \(moved.count).")
        out.append("Changed or dropped by an accepted suggestion: \(changed.count).")

        // Extras.
        let extras = input.extras.filter { days.contains($0.day) }
        if !extras.isEmpty {
            out.append("Extras outside the plan: " + extras.map { "\($0.activity) \($0.minutes) min" }.joined(separator: ", ") + ".")
        }

        // Suggestions: taken, kept, other.
        let cards = input.log.filter { days.contains($0.day) }
        let taken = cards.filter { if case .took? = $0.answer { return true } else { return false } }
        let kept = cards.filter { $0.answer == .keptPlan }
        let rest = cards.count - taken.count - kept.count
        out.append("Suggestions this week: \(taken.count) taken, \(kept.count) kept as planned, \(rest) not answered or put away."
                   + (taken.isEmpty ? "" : " Taken: " + taken.map(\.headline).joined(separator: "; ") + "."))

        // Next week, in short.
        out.append("Next week's plan:")
        for i in 7..<14 {
            let d = PlanView.addDays(monday, i)
            let of = input.sessions.filter { $0.day == d && $0.sport != .rest && !$0.dropped && $0.status != .missed }
            let line = of.isEmpty ? "rest" : of.map { "\($0.sport.rawValue) \($0.plannedMin) min\($0.intensity.isEmpty ? "" : " " + $0.intensity)" }.joined(separator: "; ")
            out.append("\(RuleBookWords.day(d)): \(line)")
        }
        return out.joined(separator: "\n")
    }

    /* The request body, exactly as the service expects it: the same model, effort and route as the pick; a small output limit. */
    public static func body(system: String, user: String) -> Data {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["lines": ["type": "array", "items": ["type": "string"]], "question": ["type": "string"]],
            "required": ["lines", "question"],
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

    /* One line as it may be shown, or nil. */
    public static func cleanLine(_ raw: String) -> String? {
        let line = ClaudeWords.oneLine(raw)
        guard !line.isEmpty, line.count <= longestLine, ClaudeWords.passes(line) else { return nil }
        return line
    }

    public static func cleanQuestion(_ raw: String) -> String? {
        let q = ClaudeWords.oneLine(raw)
        guard q.hasSuffix("?"), q.count <= longestQuestion, ClaudeWords.passes(q) else { return nil }
        return q
    }

    /*
     * Five clean lines and one clean question, and no number that was not in the
     * week's numbers (`facts`); otherwise nil.
     */
    public static func accepted(lines: [String], question: String, facts: String) -> ClaudeReviewAnswer? {
        guard lines.count == lineCount else { return nil }
        let cleaned = lines.compactMap(cleanLine)
        guard cleaned.count == lineCount, let q = cleanQuestion(question) else { return nil }
        let known = ClaudeWords.numbers(in: facts)
        guard (cleaned + [q]).allSatisfy({ ClaudeWords.numbers(in: $0).isSubset(of: known) }) else { return nil }
        return ClaudeReviewAnswer(lines: cleaned, question: q)
    }

    /* The answer, or nil whenever anything is off (a refusal or a cut-off is never read). */
    public static func read(_ data: Data, facts: String) -> ClaudeReviewAnswer? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stop = root["stop_reason"] as? String, stop == "end_turn" || stop == "stop_sequence",
              let blocks = root["content"] as? [[String: Any]],
              let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let inner = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let lines = inner["lines"] as? [String], let question = inner["question"] as? String else { return nil }
        return accepted(lines: lines, question: question, facts: facts)
    }

    /* DEBUG pictures and the fake switch: an invented answer that passes the same check. */
    public static let invented = ClaudeReviewAnswer(
        lines: ["Most of the planned bike and run minutes were done; the swim was the lightest part.",
                "Mornings were mixed: two Good, two OK, one Tired and two without an answer.",
                "The long ride felt harder than its plan said; the other sessions felt as planned.",
                "One run was missed and one session moved to another day.",
                "Next week starts with a rest day and keeps the same number of sessions."],
        question: "What made the long ride feel harder than planned?")
}

// MARK: - kept on the device

public protocol ClaudeReviewStoring {
    func load() -> [ClaudeSavedReview]
    func save(_ reviews: [ClaudeSavedReview])
}

/*
 * Per device for now: the reviews are kept in UserDefaults. A shared store that
 * follows him between devices can sit behind this protocol later.
 */
public struct UserDefaultsReviewStore: ClaudeReviewStoring {
    static let key = "claude-reviews"
    let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> [ClaudeSavedReview] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ClaudeSavedReview].self, from: data)) ?? []
    }

    public func save(_ reviews: [ClaudeSavedReview]) {
        if let data = try? JSONEncoder().encode(reviews) { defaults.set(data, forKey: Self.key) }
    }
}

extension Array where Element == ClaudeSavedReview {
    /* One per week (a second one for the same week replaces the first), newest week first, the last twelve. */
    public func adding(_ review: ClaudeSavedReview) -> [ClaudeSavedReview] {
        (filter { $0.week != review.week } + [review]).sorted { $0.week > $1.week }.prefix(12).map { $0 }
    }
}
