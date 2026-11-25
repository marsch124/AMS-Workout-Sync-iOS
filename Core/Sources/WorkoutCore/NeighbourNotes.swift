import Foundation

/*
 * The notes the three iPhone apps leave each other (25 November 2026): how he
 * felt this morning, and what was done in the other apps. They travel in ONE
 * shared Keychain item as a small piece of JSON; this file is the value and the
 * rules, with no Keychain in it, so every rule can be tested.
 *
 * Every field is optional on reading, a field this app does not know is kept
 * and written back as it was, and a note written by a newer format is neither
 * read nor changed.
 */

/* Any JSON, so a field this app has never heard of survives a round trip. */
public enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func unknownFields(_ c: KeyedDecodingContainer<AnyKey>, except known: Set<String>) -> [String: JSONValue] {
    var out: [String: JSONValue] = [:]
    for key in c.allKeys where !known.contains(key.stringValue) {
        if let v = try? c.decode(JSONValue.self, forKey: key) { out[key.stringValue] = v }
    }
    return out
}

/* "feel": how he felt on one day, 1 (very poor) to 5 (very good). */
public struct NeighbourFeel: Codable, Equatable {
    public var day: String?
    public var value: Int?
    public var at: String?
    /* "morning", "training" or "workouts". */
    public var from: String?
    public var extra: [String: JSONValue] = [:]

    public init(day: String?, value: Int?, at: String?, from: String?) {
        self.day = day; self.value = value; self.at = at; self.from = from
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        day = try? c.decodeIfPresent(String.self, forKey: AnyKey("day"))
        value = try? c.decodeIfPresent(Int.self, forKey: AnyKey("value"))
        at = try? c.decodeIfPresent(String.self, forKey: AnyKey("at"))
        from = try? c.decodeIfPresent(String.self, forKey: AnyKey("from"))
        extra = unknownFields(c, except: ["day", "value", "at", "from"])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in extra { try c.encode(v, forKey: AnyKey(k)) }
        try c.encodeIfPresent(day, forKey: AnyKey("day"))
        try c.encodeIfPresent(value, forKey: AnyKey("value"))
        try c.encodeIfPresent(at, forKey: AnyKey("at"))
        try c.encodeIfPresent(from, forKey: AnyKey("from"))
    }
}

/* One thing done: "strength", "stretch" or "routine". */
public struct NeighbourDone: Codable, Equatable {
    public var id: String?
    public var day: String?
    public var kind: String?
    public var title: String?
    public var minutes: Int?
    public var effort: Int?
    /* ISO 8601, as written. */
    public var at: String?
    public var from: String?
    public var extra: [String: JSONValue] = [:]

    public init(id: String?, day: String?, kind: String?, title: String? = nil, minutes: Int? = nil,
                effort: Int? = nil, at: String? = nil, from: String? = nil) {
        self.id = id; self.day = day; self.kind = kind; self.title = title
        self.minutes = minutes; self.effort = effort; self.at = at; self.from = from
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try? c.decodeIfPresent(String.self, forKey: AnyKey("id"))
        day = try? c.decodeIfPresent(String.self, forKey: AnyKey("day"))
        kind = try? c.decodeIfPresent(String.self, forKey: AnyKey("kind"))
        title = try? c.decodeIfPresent(String.self, forKey: AnyKey("title"))
        minutes = try? c.decodeIfPresent(Int.self, forKey: AnyKey("minutes"))
        effort = try? c.decodeIfPresent(Int.self, forKey: AnyKey("effort"))
        at = try? c.decodeIfPresent(String.self, forKey: AnyKey("at"))
        from = try? c.decodeIfPresent(String.self, forKey: AnyKey("from"))
        extra = unknownFields(c, except: ["id", "day", "kind", "title", "minutes", "effort", "at", "from"])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in extra { try c.encode(v, forKey: AnyKey(k)) }
        try c.encodeIfPresent(id, forKey: AnyKey("id"))
        try c.encodeIfPresent(day, forKey: AnyKey("day"))
        try c.encodeIfPresent(kind, forKey: AnyKey("kind"))
        try c.encodeIfPresent(title, forKey: AnyKey("title"))
        try c.encodeIfPresent(minutes, forKey: AnyKey("minutes"))
        try c.encodeIfPresent(effort, forKey: AnyKey("effort"))
        try c.encodeIfPresent(at, forKey: AnyKey("at"))
        try c.encodeIfPresent(from, forKey: AnyKey("from"))
    }
}

public struct NeighbourNotes: Codable, Equatable {
    /* The format this app understands. A higher one is left alone. */
    public static let knownFormat = 1

    public var format: Int?
    public var feel: NeighbourFeel?
    public var done: [NeighbourDone] = []
    public var extra: [String: JSONValue] = [:]

    public init(format: Int? = NeighbourNotes.knownFormat, feel: NeighbourFeel? = nil, done: [NeighbourDone] = []) {
        self.format = format; self.feel = feel; self.done = done
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        format = try? c.decodeIfPresent(Int.self, forKey: AnyKey("format"))
        feel = try? c.decodeIfPresent(NeighbourFeel.self, forKey: AnyKey("feel"))
        done = []
        if var list = try? c.nestedUnkeyedContainer(forKey: AnyKey("done")) {
            while !list.isAtEnd {
                if let d = try? list.decode(NeighbourDone.self) { done.append(d) }
                else { _ = try? list.decode(JSONValue.self) }   // not an object: skipped, and the list moves on
            }
        }
        extra = unknownFields(c, except: ["format", "feel", "done"])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in extra { try c.encode(v, forKey: AnyKey(k)) }
        try c.encodeIfPresent(format, forKey: AnyKey("format"))
        try c.encodeIfPresent(feel, forKey: AnyKey("feel"))
        try c.encode(done, forKey: AnyKey("done"))
    }

    /* Nothing at all, or broken JSON, or a newer format than this app knows: no notes. */
    public static func decode(_ data: Data?) -> NeighbourNotes? {
        guard let data, let notes = try? JSONDecoder().decode(NeighbourNotes.self, from: data) else { return nil }
        guard (notes.format ?? knownFormat) <= knownFormat else { return nil }
        return notes
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /* Only the notes of the last 14 days (today's included) are kept. */
    public func pruned(today: String) -> NeighbourNotes {
        var copy = self
        let oldest = NeighbourRules.addDays(today, -13)
        copy.done = done.filter { ($0.day ?? "") >= oldest }
        return copy
    }
}

public enum NeighbourRules {
    /* How many days back the notes are kept, and the stretching line looks. */
    public static let keepDays = 14

    static func addDays(_ key: String, _ days: Int) -> String { PlanView.addDays(key, days) }

    /*
     * He answered in another app: this morning's answer for the diary, taken
     * once. Nothing when the diary already holds an answer for today (the
     * first answer of the day wins), when the note is of another day, or when
     * the value is not one of the five.
     */
    public static func takeOverFeel(notes: NeighbourNotes?, ownAnswerToday: Feel?, today: String) -> Feel? {
        guard ownAnswerToday == nil, let notes, let feel = notes.feel,
              feel.day == today, let v = feel.value else { return nil }
        return Feel(rawValue: v)
    }

    /*
     * His own answer, put into the notes: the notes to write, or nil when
     * nothing should be written. An answer of today from another app stays;
     * only this app's own earlier answer may change; an earlier day is
     * replaced. A newer format is not touched. No notes yet: a fresh set.
     */
    public static func writingFeel(notes: NeighbourNotes?, own: Feel, today: String, now: Date = Date()) -> NeighbourNotes? {
        var base = notes ?? NeighbourNotes()
        if (base.format ?? NeighbourNotes.knownFormat) > NeighbourNotes.knownFormat { return nil }
        if let there = base.feel, there.day == today {
            guard there.from == "training", there.value != own.rawValue else { return nil }
        }
        let formatter = ISO8601DateFormatter()
        var feel = base.feel?.day == today ? base.feel! : NeighbourFeel(day: today, value: nil, at: nil, from: nil)
        if base.feel?.day != today { feel.extra = [:] }
        feel.day = today
        feel.value = own.rawValue
        feel.at = formatter.string(from: now)
        feel.from = "training"
        base.feel = feel
        base.format = base.format ?? NeighbourNotes.knownFormat
        return base.pruned(today: today)
    }

    /* Each note once: the same id is never counted twice. */
    static func distinct(_ notes: NeighbourNotes) -> [NeighbourDone] {
        var seen = Set<String>()
        return notes.done.filter { d in
            guard let id = d.id, !id.isEmpty else { return true }
            return seen.insert(id).inserted
        }
    }

    /* The first strength note of a day that has not been logged yet. `used` holds the ids already logged. */
    public static func strengthNote(for day: String, in notes: NeighbourNotes?, used: Set<String> = []) -> NeighbourDone? {
        guard let notes, (notes.format ?? NeighbourNotes.knownFormat) <= NeighbourNotes.knownFormat else { return nil }
        return distinct(notes).first { $0.kind == "strength" && $0.day == day && !used.contains($0.id ?? "") }
    }

    /* On how many of the last `lastDays` mornings (today included) he stretched. nil when there is no stretch note at all. */
    public static func stretchMornings(in notes: NeighbourNotes?, lastDays: Int = 7, today: String) -> Int? {
        guard let notes, (notes.format ?? NeighbourNotes.knownFormat) <= NeighbourNotes.knownFormat else { return nil }
        let stretches = distinct(notes).filter { $0.kind == "stretch" }
        guard !stretches.isEmpty else { return nil }
        let oldest = addDays(today, -(lastDays - 1))
        let days = Set(stretches.compactMap(\.day).filter { $0 >= oldest && $0 <= today })
        return days.count
    }

    /* "Done in Workouts at 07:40 · 35 min" — the time in the phone's own zone; a missing part is left out. */
    public static func doneLine(_ note: NeighbourDone, timeZone: TimeZone = .current) -> String {
        var line = "Done in Workouts"
        if let at = note.at, let date = ISO8601DateFormatter().date(from: at) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let c = cal.dateComponents([.hour, .minute], from: date)
            line += String(format: " at %02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        if let m = note.minutes, m > 0 { line += " · \(m) min" }
        return line
    }
}
