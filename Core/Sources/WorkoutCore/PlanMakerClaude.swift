import Foundation

/*
 * "Ask Claude to look it over" (round 30, pick 1): the pure part.
 *
 * The rules made the draft and offer a numbered menu of allowed tweaks
 * (PlanMaker.menu: the long ride or long run to another day, 10 % more or
 * less in one block). Claude may only pick from that menu — none, one or two,
 * never two with the same aim — and write three short lines. Everything it
 * sends back is checked here like ClaudePick checks a pick; anything off gives
 * nil and nothing is shown. The draft changes only when he taps "Use these
 * changes", and then through the same rules. Nothing here touches the network.
 */
public struct PlanMakerClaudeAnswer: Codable, Equatable, Sendable {
    public let picks: [PlanTweak]
    public let note: [String]
    public init(picks: [PlanTweak], note: [String]) { self.picks = picks; self.note = note }
}

public enum PlanMakerClaude {
    public static let lineCount = 3
    public static let longestLine = 120
    public static let mostPicks = 2
    public static let maxTokens = 1200

    /* What the card says before the first use. */
    public static let sentWords = "The draft\u{2019}s weeks, hours and week shape \u{2014} no names, no notes."

    public static let system = """
    You look over a DRAFT season plan for an amateur athlete preparing for a triathlon. A fixed rule book made the draft and offers a numbered menu of allowed changes. You may only choose numbers from that menu: none, one or two, never two with the same aim. 0 means change nothing. You change nothing yourself; he decides with a tap.
    Reply with the JSON only: {"picks": [<numbers from the menu>], "note": ["...", "...", "..."]}.
    The note is exactly three lines. Each line is ONE plain sentence in British English, at most 110 characters: what you notice about the draft's shape and, if you picked something, why. Calm: no praise, no blame, no medical talk. Never mention sleep, pulse or HRV. Use only numbers that appear in the draft's facts or the menu.
    """

    static func hours(_ minutes: Int) -> String {
        let h = Double(minutes) / 60
        return String(format: "%.1f", (h * 10).rounded() / 10)
    }

    /* The draft's facts as the one text Claude is given: no name, no notes, nothing of his plan. */
    public static func facts(settings s: PlanMakerSettings, shape raw: WeekShape, tweaks: [PlanTweak], weeks: [MadeWeek]) -> String {
        let shape = PlanMaker.effectiveShape(raw, tweaks: tweaks)
        var out: [String] = ["The draft, in numbers."]
        let raceWeekday = parseDayKey(s.raceDay) == nil ? "" : WeekShape.weekdayNames[RuleBook.weekday(s.raceDay)]
        out.append("Distance: \(s.distance.title.lowercased()). Race day: \(raceWeekday) \(s.raceDay).")
        let toRace = weeks.filter { $0.block != .postSeason }.count
        out.append("Weeks to the race: \(toRace), race week included; then \(weeks.count - toRace) post-season weeks.")
        out.append("Hours a week asked for: from \(hours(Int(s.hoursLow * 60))) to \(hours(Int(s.hoursHigh * 60))).")
        out.append("An easy week every \(s.easyEvery == 3 ? "3rd" : "4th") week; tests about every \(s.testEvery) weeks.")
        let spans = PlanMaker.spans(weeks).map { b -> String in
            let range = b.block == .raceWeek || b.block == .postSeason ? "" : " (\(hours(b.minLow)) to \(hours(b.minHigh)) hours a week)"
            return "\(b.block.title) \(b.weeks) week\(b.weeks == 1 ? "" : "s")\(range)"
        }
        out.append("Blocks: " + spans.joined(separator: ", ") + ".")
        let days = (0..<7).map { d -> String in
            let list = shape.days[d].map(WeekShape.word)
            return WeekShape.weekdayNames[d] + " " + (list.isEmpty ? "nothing" : list.joined(separator: " and "))
        }
        out.append("Week shape: " + days.joined(separator: "; ") + ".")
        out.append("Long ride on \(WeekShape.weekdayNames[shape.longRide]), long run on \(WeekShape.weekdayNames[shape.longRun]), rest day \(WeekShape.weekdayNames[shape.rest]).")
        let rides = weeks.flatMap(\.sessions).filter { $0.sport == "bike" && $0.title.hasPrefix("Long ride") }.map(\.minutes)
        let runs = weeks.flatMap(\.sessions).filter { $0.sport == "run" && $0.title.hasPrefix("Long run") }.map(\.minutes)
        if let r = rides.max(), let first = rides.first { out.append("Long ride: \(first) minutes at first, \(r) at most.") }
        if let r = runs.max(), let first = runs.first { out.append("Long run: \(first) minutes at first, \(r) at most.") }
        return out.joined(separator: "\n")
    }

    public static func menuText(_ menu: [PlanTweak]) -> String {
        var lines = ["The menu. Choose none, one or two numbers.", "0 = change nothing"]
        for (i, t) in menu.enumerated() { lines.append("\(i + 1) = \(t.words)") }
        return lines.joined(separator: "\n")
    }

    public static func user(facts: String, menu: [PlanTweak]) -> String { facts + "\n\n" + menuText(menu) }

    /* The request body, exactly as the service expects it: the same model, effort and route as the pick. */
    public static func body(system: String, user: String) -> Data {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["picks": ["type": "array", "items": ["type": "integer"]],
                           "note": ["type": "array", "items": ["type": "string"]]],
            "required": ["picks", "note"],
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

    /*
     * The answer as it may be shown, or nil: picks inside the menu (0 only on
     * its own), at most two, never two with the same aim; exactly three clean
     * lines, none with a number that is not in the facts or the menu.
     */
    public static func accepted(picks raw: [Int], note: [String], menu: [PlanTweak], facts: String) -> PlanMakerClaudeAnswer? {
        var picks = raw
        if picks.contains(0) {
            guard picks.allSatisfy({ $0 == 0 }) else { return nil }
            picks = []
        }
        guard picks.count <= mostPicks, Set(picks).count == picks.count,
              picks.allSatisfy({ $0 >= 1 && $0 <= menu.count }) else { return nil }
        let tweaks = picks.map { menu[$0 - 1] }
        guard Set(tweaks.map(\.target)).count == tweaks.count else { return nil }
        guard note.count == lineCount else { return nil }
        let known = ClaudeWords.numbers(in: facts + "\n" + menuText(menu))
        var lines: [String] = []
        for raw in note {
            let line = ClaudeWords.oneLine(raw)
            guard !line.isEmpty, line.count <= longestLine, ClaudeWords.passes(line),
                  ClaudeWords.numbers(in: line).isSubset(of: known) else { return nil }
            lines.append(line)
        }
        return PlanMakerClaudeAnswer(picks: tweaks, note: lines)
    }

    /* The answer, or nil whenever anything is off (a refusal or a cut-off is never read). */
    public static func read(_ data: Data, menu: [PlanTweak], facts: String) -> PlanMakerClaudeAnswer? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stop = root["stop_reason"] as? String, stop == "end_turn" || stop == "stop_sequence",
              let blocks = root["content"] as? [[String: Any]],
              let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let inner = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let rawPicks = inner["picks"] as? [Any], let note = inner["note"] as? [String] else { return nil }
        var picks: [Int] = []
        for p in rawPicks {
            guard let n = p as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), Double(n.intValue) == n.doubleValue else { return nil }
            picks.append(n.intValue)
        }
        return accepted(picks: picks, note: note, menu: menu, facts: facts)
    }

    /* DEBUG pictures and the fake switch: an invented answer that passes the same check. */
    public static func invented(menu: [PlanTweak], facts: String) -> PlanMakerClaudeAnswer {
        let pick = menu.firstIndex(of: .volume(.peak, false)).map { [$0 + 1] } ?? []
        let note = ["The long sessions sit on the weekend, with the rest day just before them.",
                    "Base is the longest block, so the hours climb slowly before Build.",
                    "A little less in Peak keeps the last hard weeks fresh before the taper."]
        return accepted(picks: pick, note: note, menu: menu, facts: facts) ?? PlanMakerClaudeAnswer(picks: [], note: note)
    }
}
