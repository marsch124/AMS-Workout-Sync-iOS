import Foundation

/*
 * Search over the sessions and extras (round 28, pick 21).
 *
 * Pure: the app turns each session and each extra into one `SearchEntry`
 * (words only), this finds the ones a query matches. Case and accents do not
 * matter ("Cafe" finds "café"), and EVERY word of the query has to match
 * somewhere in the entry — its title, its description, its notes, what he
 * logged, its sport, or a word of its date ("november", "wed", "2026-11-25").
 */

public struct SearchEntry: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case session, extra }
    public enum Group: String, Sendable { case toCome = "To come", done = "Done", missed = "Missed" }

    public var id: String
    public var kind: Kind
    public var dayKey: String
    public var group: Group
    public var sportId: String
    public var sportLabel: String
    public var title: String
    public var description: String
    public var notes: String
    /* Free words he logged: the note, an extra's "what it was" … never numbers. */
    public var logged: String

    public init(id: String, kind: Kind, dayKey: String, group: Group, sportId: String, sportLabel: String,
                title: String, description: String = "", notes: String = "", logged: String = "") {
        self.id = id; self.kind = kind; self.dayKey = dayKey; self.group = group; self.sportId = sportId
        self.sportLabel = sportLabel; self.title = title; self.description = description
        self.notes = notes; self.logged = logged
    }
}

public struct SearchHit: Equatable, Identifiable, Sendable {
    public var id: String { entry.id }
    public let entry: SearchEntry
    /* The grey line under the row: where the words were found. */
    public let found: String
}

public struct SearchGroupResult: Equatable, Sendable {
    public let group: SearchEntry.Group
    public let hits: [SearchHit]
}

public enum SessionSearch {
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                                 "September", "October", "November", "December"]

    /* Lower case, no accents, "ß" as "ss". */
    public static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00DF}", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
    }

    /* The words of a query: split on spaces and commas, folded, empty ones dropped. */
    public static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" }).map(String.init)
    }

    /* A search is only started by a real word. */
    public static func isActive(_ query: String) -> Bool { !words(query).isEmpty }

    /* "Wednesday Wed November Nov 2026 25 2026-11-25" — the words a date answers to. */
    public static func dateWords(_ dayKey: String) -> String {
        guard let date = parseDayKey(dayKey) else { return dayKey }
        let c = utc.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let y = c.year, let m = c.month, let d = c.day, let wd = c.weekday else { return dayKey }
        let weekday = weekdays[wd - 1], month = months[m - 1]
        return "\(weekday) \(weekday.prefix(3)) \(month) \(month.prefix(3)) \(y) \(d) \(dayKey)"
    }

    /* The fields in the order they are looked at, each with the name shown when it is where the words were found. */
    private static func fields(_ e: SearchEntry) -> [(String, String)] {
        [("Notes", e.notes), ("You logged", e.logged), ("Description", e.description), ("Title", e.title),
         ("Sport", e.sportLabel + " " + e.sportId), ("Date", dateWords(e.dayKey))]
    }

    /* Does every word of the query match somewhere in the entry? */
    public static func matches(_ words: [String], _ e: SearchEntry) -> Bool {
        guard !words.isEmpty else { return false }
        let haystacks = fields(e).map { fold($0.1) }
        return words.allSatisfy { w in haystacks.contains { $0.contains(w) } }
    }

    /* The grey line: the first free-text field holding one of the words, cut round it; else where else it matched. */
    public static func foundLine(_ words: [String], _ e: SearchEntry) -> String {
        let order = fields(e)
        for (label, text) in order where ["Notes", "You logged", "Description"].contains(label) {
            let clean = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).joined(separator: " ")
            if let snippet = snippet(clean, words) { return label + ": " + snippet }
        }
        var where_: [String] = []
        for (label, text) in order where ["Title", "Sport", "Date"].contains(label) {
            let f = fold(text)
            if words.contains(where: { f.contains($0) }) { where_.append(label.lowercased()) }
        }
        return where_.isEmpty ? "" : "Found in the " + where_.joined(separator: " and ")
    }

    /* About 70 characters around the first word found, with "…" where the text goes on. */
    static func snippet(_ text: String, _ words: [String]) -> String? {
        let folded = fold(text)
        // The folded text can differ in length from the original only for "ß"; compare by characters of the folded copy.
        guard let hit = words.compactMap({ folded.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let chars = Array(text)
        guard chars.count == folded.count else { return String(text.prefix(70)) }
        let at = folded.distance(from: folded.startIndex, to: hit.lowerBound)
        let from = max(0, at - 25), to = min(chars.count, at + 45)
        return (from > 0 ? "\u{2026}" : "") + String(chars[from..<to]).trimmingCharacters(in: .whitespaces)
            + (to < chars.count ? "\u{2026}" : "")
    }

    /*
     * The answer: only the groups that hold something, in the order To come,
     * Done, Missed; inside each group the newest day first.
     */
    public static func results(_ query: String, in entries: [SearchEntry]) -> [SearchGroupResult] {
        let w = words(query)
        guard !w.isEmpty else { return [] }
        let found = entries.filter { matches(w, $0) }
            .sorted { $0.dayKey != $1.dayKey ? $0.dayKey > $1.dayKey : $0.id < $1.id }
        return [SearchEntry.Group.toCome, .done, .missed].compactMap { g in
            let hits = found.filter { $0.group == g }.map { SearchHit(entry: $0, found: foundLine(w, $0)) }
            return hits.isEmpty ? nil : SearchGroupResult(group: g, hits: hits)
        }
    }
}
