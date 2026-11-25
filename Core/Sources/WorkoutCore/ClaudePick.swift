import Foundation

/*
 * "Claude built in": the pure part.
 *
 * The rule book decides WHETHER a suggestion card appears and builds its
 * menu. Claude may only PICK one item of that menu and word the one-line
 * reason. Everything it says is checked here; anything that is off gives nil
 * and the caller falls back to the rule book's own pick. Nothing in this file
 * touches the network, the Keychain or the disk.
 *
 * Numbering of a menu: 0 keeps the plan as it is, 1 is the rule book's own
 * pick (`Suggestion.choice`), 2 and 3 are `Suggestion.otherChoices`.
 */

/* The tokens one answer used. */
public struct ClaudeUsage: Codable, Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input; self.output = output; self.cacheCreation = cacheCreation; self.cacheRead = cacheRead
    }

    /* US dollars per million: 4.00 in (cache writes count as input), 0.20 cache read, 20.00 out. */
    public var dollars: Double {
        (Double(input + cacheCreation) * 4.0 + Double(cacheRead) * 0.20 + Double(output) * 20.0) / 1_000_000
    }
}

public struct ClaudeAnswer: Codable, Equatable, Sendable {
    /* 0 keep the plan, 1 the rule book's pick, 2… the other choices. */
    public let pick: Int
    /* "Why: …", one short sentence. */
    public let why: String
    public let usage: ClaudeUsage

    public init(pick: Int, why: String, usage: ClaudeUsage = ClaudeUsage()) {
        self.pick = pick; self.why = why; self.usage = usage
    }

    /* The index the card's own answer uses: nil keeps the plan, 0 is the card's choice, 1… the others. */
    public var takenIndex: Int? { pick == 0 ? nil : pick - 1 }
}

/* One past day, as the caller hands it in. */
public struct ClaudeDay: Equatable, Sendable {
    public var day: String
    public var plannedMinutes: Int
    public var doneMinutes: Int
    /* His own words or number for "how hard was it", already formatted by the caller. */
    public var hard: String?
    /* How he felt in the morning, 1–5. */
    public var morning: Int?
    /* "hike 90 min" and the like. */
    public var extras: String?

    public init(day: String, plannedMinutes: Int, doneMinutes: Int, hard: String? = nil, morning: Int? = nil, extras: String? = nil) {
        self.day = day; self.plannedMinutes = plannedMinutes; self.doneMinutes = doneMinutes
        self.hard = hard; self.morning = morning; self.extras = extras
    }
}

/* One coming day of the plan, as one short line ("Tue bike 60 min Z2; strength 30 min"). */
public struct ClaudeAheadDay: Equatable, Sendable {
    public var day: String
    public var sessions: String
    public init(day: String, sessions: String) { self.day = day; self.sessions = sessions }
}

public struct ClaudeContext: Equatable, Sendable {
    public var today: String
    /* The last 14 days, oldest first. */
    public var past: [ClaudeDay]
    /* The next 7 days. */
    public var ahead: [ClaudeAheadDay]

    public init(today: String, past: [ClaudeDay], ahead: [ClaudeAheadDay]) {
        self.today = today; self.past = past; self.ahead = ahead
    }
}

public enum ClaudePick {
    public static let model = "claude-opus-5-5"
    public static let endpoint = "https://api.anthropic.com/v1/messages"
    public static let version = "2026-10-21"
    public static let beta = "server-side-fallback-2026-07-01"

    /* The longest reason that is accepted, and the longest he is asked for. */
    public static let longestWhy = 160
    public static let blocked = ["doctor", "diagnos", "injur", "should see", "medication", "sleep", "slept", "hrv", "pulse"]

    public static let system = """
    You help an amateur athlete who is preparing for a half-distance triathlon. A fixed rule book has already decided that a suggestion is due and has written a numbered menu of changes to his training plan. You may only choose a number from that menu. 0 means keep the plan as it is. You change nothing yourself; he decides with a tap.
    Reply with the JSON only: {"pick": <number from the menu>, "why": "<one sentence>"}.
    The why is ONE short sentence in plain British English, calm and kind. It starts with "Why: " and is at most 120 characters. It is never medical advice. It never mentions sleep, resting pulse or HRV. It never uses a number that is not in the situation you were given.
    """

    /* Valid picks are 0 … menuCount: the rule book's pick plus its other choices. */
    public static func menuCount(for suggestion: Suggestion) -> Int { 1 + suggestion.otherChoices.count }

    public static func request(for suggestion: Suggestion, context: ClaudeContext) -> (system: String, user: String) {
        var lines: [String] = ["The menu. Choose one number."]
        lines.append("0 = keep my plan as it is")
        lines.append("1 = \(suggestion.choice.headline) (the rule book's own pick; its reason: \(suggestion.why))")
        for (i, other) in suggestion.otherChoices.enumerated() {
            lines.append("\(i + 2) = \(other.headline)")
        }
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
        lines.append("The next \(context.ahead.count) days of the plan:")
        for d in context.ahead { lines.append("\(d.day): \(d.sessions)") }
        return (system, lines.joined(separator: "\n"))
    }

    /* The request body, exactly as the service expects it. Nothing else is ever added to it. */
    public static func body(system: String, user: String) -> Data {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["pick": ["type": "integer"], "why": ["type": "string"]],
            "required": ["pick", "why"],
            "additionalProperties": false,
        ]
        let root: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
    }

    /* The tiny check of a freshly typed key: no structured output, a few tokens. */
    public static func testBody() -> Data {
        let root: [String: Any] = [
            "model": model,
            "max_tokens": 16,
            "messages": [["role": "user", "content": "Reply OK"]],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
    }

    /* The answer, or nil whenever anything is off. */
    public static func read(_ data: Data, menuCount: Int) -> ClaudeAnswer? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        // Always the stop reason first: a refusal or a cut-off is never read.
        guard let stop = root["stop_reason"] as? String, stop == "end_turn" || stop == "stop_sequence" else { return nil }
        guard let blocks = root["content"] as? [[String: Any]],
              let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let inner = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let pickNumber = inner["pick"] as? NSNumber, CFGetTypeID(pickNumber) != CFBooleanGetTypeID(),
              Double(pickNumber.intValue) == pickNumber.doubleValue,
              var why = inner["why"] as? String else { return nil }
        let pick = pickNumber.intValue
        guard pick >= 0, pick <= menuCount else { return nil }

        why = why.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !why.isEmpty else { return nil }
        if !why.hasPrefix("Why:") { why = "Why: " + why }
        guard why.count > 4, why.count <= longestWhy else { return nil }
        let lower = why.lowercased()
        guard !blocked.contains(where: { lower.contains($0) }) else { return nil }

        let u = root["usage"] as? [String: Any] ?? [:]
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        let usage = ClaudeUsage(input: n("input_tokens"), output: n("output_tokens"),
                                cacheCreation: n("cache_creation_input_tokens"), cacheRead: n("cache_read_input_tokens"))
        return ClaudeAnswer(pick: pick, why: why, usage: usage)
    }

    /* The usage of any answer, even one that is not used (the cost is paid all the same). */
    public static func usage(in data: Data) -> ClaudeUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let u = root["usage"] as? [String: Any] else { return nil }
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        return ClaudeUsage(input: n("input_tokens"), output: n("output_tokens"),
                           cacheCreation: n("cache_creation_input_tokens"), cacheRead: n("cache_read_input_tokens"))
    }
}

/* The month's ledger: what has been spent this calendar month. */
public struct ClaudeMeter: Codable, Equatable, Sendable {
    public static let defaultCap = 5.00

    public var month: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var dollars: Double
    public var answers: Int

    public init(month: String, inputTokens: Int = 0, outputTokens: Int = 0, dollars: Double = 0, answers: Int = 0) {
        self.month = month; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.dollars = dollars; self.answers = answers
    }

    public static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    public static func fresh(now: Date = Date(), calendar: Calendar = .current) -> ClaudeMeter {
        ClaudeMeter(month: monthKey(now, calendar: calendar))
    }

    /* The ledger as it stands in `now`'s month: a new month starts from nothing. */
    public func current(now: Date = Date(), calendar: Calendar = .current) -> ClaudeMeter {
        month == Self.monthKey(now, calendar: calendar) ? self : Self.fresh(now: now, calendar: calendar)
    }

    public func canSpend(cap: Double = ClaudeMeter.defaultCap, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        current(now: now, calendar: calendar).dollars < cap
    }

    public mutating func add(usage: ClaudeUsage, now: Date = Date(), calendar: Calendar = .current) {
        self = current(now: now, calendar: calendar)
        inputTokens += usage.input + usage.cacheCreation + usage.cacheRead
        outputTokens += usage.output
        dollars += usage.dollars
        answers += 1
    }
}
