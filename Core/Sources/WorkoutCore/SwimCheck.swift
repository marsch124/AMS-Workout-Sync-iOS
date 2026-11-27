import Foundation

/*
 * Swim video check (round 30, pick 17): one filmed pool length, six still
 * pictures from it, and exactly three plain tips on the stroke. The pure part:
 * which moments of the video are taken, the request, the check of the answer,
 * and what is kept (the tips only, never a picture).
 */

public struct SwimTip: Codable, Equatable, Sendable {
    public let text: String
    /* The id of the drill card that fits the tip, when one does. */
    public let drill: String?
    public init(text: String, drill: String?) { self.text = text; self.drill = drill }
}

public struct SwimCheckEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { time }
    /* "14:32": when the check was made. */
    public let time: String
    public let tips: [SwimTip]
    public init(time: String, tips: [SwimTip]) { self.time = time; self.tips = tips }
}

/* What the shelf holds for one day: `coach/swimcheck/<day>`. */
public struct SwimCheckDay: Codable, Equatable, Sendable {
    public var checks: [SwimCheckEntry]
    public init(checks: [SwimCheckEntry] = []) { self.checks = checks }
}

public enum SwimCheck {
    public static let frameCount = 6
    public static let tipCount = 3
    /* Two short lines on a phone. */
    public static let longestTip = 140
    public static let maxTokens = 900
    /* The longest side of a picture sent, in pixels: small enough to be cheap. */
    public static let pictureSide = 768

    public static let sentWords = "Six still pictures go to Anthropic; the video stays on your device."
    public static let buttonWords = "Send to Claude \u{00B7} about 3 cents"
    public static let didNotPass = "Claude\u{2019}s answer did not pass the app\u{2019}s check \u{2014} nothing shown."
    public static let nothingCame = "No answer came back. Nothing was kept."
    public static let notOn = "Claude is resting: it is not switched on. Settings \u{2192} Claude."

    public static func shelfKey(day: String) -> String { "coach/swimcheck/" + day }

    /* The six moments, evenly spread, each in the middle of its sixth of the video. */
    public static func frameTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [0] }
        return (0..<frameCount).map { (Double($0) + 0.5) / Double(frameCount) * duration }
    }

    /* Day by day, newest first. */
    public static func listing(_ days: [(day: String, value: SwimCheckDay)]) -> [(day: String, entry: SwimCheckEntry)] {
        days.sorted { $0.day > $1.day }.flatMap { d in d.value.checks.reversed().map { (d.day, $0) } }
    }

    // MARK: the request

    public static let system = """
    You look at six still pictures taken in order from one filmed length of front crawl (freestyle) in a pool, by an amateur preparing for a half-distance triathlon. Give exactly three plain tips about the STROKE only: arm entry and reach, pull, elbow height, breathing and head position, kick, rotation, timing. Say only what you can see in the pictures; if something cannot be seen, say a different thing you can see.
    Never mention the swimmer's body, weight, age, health, fitness or appearance. No praise and no blame, no cheering words, no medical talk.
    Each tip is ONE or TWO short sentences in British English, at most 130 characters in all, telling what to try.
    If a tip fits one of these drills, name its id in "drill", otherwise use "none": \(DrillCards.cards(of: .swim).map(\.id).joined(separator: ", ")).
    Reply with the JSON only: {"tips": [{"text": "...", "drill": "..."}, {"text": "...", "drill": "..."}, {"text": "...", "drill": "..."}]}.
    """

    /* The request: the six pictures (JPEG, as base64 text) and one short question. */
    public static func body(jpegBase64: [String]) -> Data {
        var content: [[String: Any]] = jpegBase64.map {
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0]]
        }
        content.append(["type": "text", "text": "Six pictures, in order, from one length of front crawl. Give the three tips."])
        let tip: [String: Any] = [
            "type": "object",
            "properties": ["text": ["type": "string"], "drill": ["type": "string"]],
            "required": ["text", "drill"], "additionalProperties": false,
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["tips": ["type": "array", "items": tip]],
            "required": ["tips"], "additionalProperties": false,
        ]
        let root: [String: Any] = [
            "model": ClaudePick.model,
            "max_tokens": maxTokens,
            "fallbacks": "default",
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
    }

    // MARK: the answer

    /* About the stroke only: words about the body, weight or health are never shown. */
    static let notAboutTheStroke = ["your body", "body fat", "weight", " fat ", " thin ", " belly", "stomach", " diet", "calorie", "health",
                                    "injur", " pain", " hurt", "doctor", "medical", " age ", " older ", " fit ", "fitness", "unfit"]

    public static func cleanTip(_ raw: String) -> String? {
        let text = ClaudeWords.oneLine(raw)
        let lower = " " + text.lowercased() + " "
        guard !text.isEmpty, text.count <= longestTip, ClaudeWords.passes(text),
              !notAboutTheStroke.contains(where: { lower.contains($0) }) else { return nil }
        return text
    }

    /* The drill card a tip is linked to: the one Claude named, else one its words name; nil when none fits. */
    public static func link(text: String, named: String?) -> String? {
        if let named, DrillCards.card(named)?.kind == .swim { return named }
        return DrillCards.matches(in: text, discipline: "swim").first?.id
    }

    /* Exactly three clean tips, or nil. */
    public static func accepted(_ raw: [(text: String, drill: String?)]) -> [SwimTip]? {
        guard raw.count == tipCount else { return nil }
        var out: [SwimTip] = []
        for r in raw {
            guard let text = cleanTip(r.text) else { return nil }
            out.append(SwimTip(text: text, drill: link(text: text, named: r.drill)))
        }
        return out
    }

    /* The tips, or nil whenever anything is off (a refusal or a cut-off is never read). */
    public static func read(_ data: Data) -> [SwimTip]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stop = root["stop_reason"] as? String, stop == "end_turn" || stop == "stop_sequence",
              let blocks = root["content"] as? [[String: Any]],
              let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let inner = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let tips = inner["tips"] as? [[String: Any]] else { return nil }
        var raw: [(text: String, drill: String?)] = []
        for t in tips {
            guard let text = t["text"] as? String else { return nil }
            raw.append((text, t["drill"] as? String))
        }
        return accepted(raw)
    }

    /* DEBUG pictures and the fake switch: three invented tips that pass the same check. */
    public static let invented: [SwimTip] = [
        SwimTip(text: "Your hand lands short of your head. Reach a little further before you pull.", drill: "catch-up"),
        SwimTip(text: "The elbow drops early in the pull. Keep it high, as if reaching over a barrel.", drill: "fist"),
        SwimTip(text: "You lift your head to breathe. Turn it with your shoulders and keep one goggle in the water.", drill: "side-kick"),
    ]
}
