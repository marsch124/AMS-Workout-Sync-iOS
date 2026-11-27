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
     * When an answer taken over from the notes was given: the note's own time,
     * never later than now (a clock ahead elsewhere), now when the note has no
     * time that reads. So an answer he gave later in this app, on another
     * device, still wins by its mark.
     */
    public static func takenOverMoment(_ feel: NeighbourFeel?, now: Date = Date()) -> Date {
        guard let at = feel?.at else { return now }
        let plain = ISO8601DateFormatter()
        let fine = ISO8601DateFormatter()
        fine.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let when = plain.date(from: at) ?? fine.date(from: at) else { return now }
        return min(when, now)
    }

    /*
     * He answered in another app: this morning's answer for the diary. Taken
     * when the diary holds no answer for today. An answer that was itself
     * taken over from the notes (`ownAnswerWasTakenOver`) is not his own: the
     * notes are followed, so when the other app changes its answer the same
     * day, the new one replaces it. An answer given in this app is never
     * replaced. Nothing when the note is of another day, is this app's own,
     * or when the value is not one of the five.
     */
    public static func takeOverFeel(notes: NeighbourNotes?, ownAnswerToday: Feel?, today: String,
                                    ownAnswerWasTakenOver: Bool = false) -> Feel? {
        guard let notes, let feel = notes.feel, feel.day == today, let v = feel.value,
              let theirs = Feel(rawValue: v) else { return nil }
        guard let own = ownAnswerToday else { return theirs }
        guard ownAnswerWasTakenOver, feel.from != "training", own != theirs else { return nil }
        return theirs
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

    /*
     * Mobility ticked from Magic Morning (2.15): each planned mobility session still to do, on a day up to
     * today that has a stretch note not used yet, gets that note — the first such session of a day only,
     * each note once. `todo` holds the sessions still to do (key and day); `used` the note ids already logged.
     */
    public static func mobilityTicks(todo: [(key: String, day: String)], notes: NeighbourNotes?, used: Set<String> = [],
                                     today: String) -> [(key: String, note: NeighbourDone)] {
        ticks(kind: "stretch", todo: todo, notes: notes, used: used, today: today)
    }

    /* Strength ticked from Workout Companion (2.16): the same rule, with its `strength` notes. */
    public static func strengthTicks(todo: [(key: String, day: String)], notes: NeighbourNotes?, used: Set<String> = [],
                                     today: String) -> [(key: String, note: NeighbourDone)] {
        ticks(kind: "strength", todo: todo, notes: notes, used: used, today: today)
    }

    /* The one rule behind both: per day up to today, the first session still to do gets the first unused note of `kind`. */
    public static func ticks(kind: String, todo: [(key: String, day: String)], notes: NeighbourNotes?, used: Set<String> = [],
                             today: String) -> [(key: String, note: NeighbourDone)] {
        guard let notes, (notes.format ?? NeighbourNotes.knownFormat) <= NeighbourNotes.knownFormat else { return [] }
        let found = distinct(notes).filter { $0.kind == kind && !($0.id ?? "").isEmpty }
        var taken = used
        var days = Set<String>()
        var out: [(key: String, note: NeighbourDone)] = []
        for s in todo.sorted(by: { $0.day < $1.day }) where s.day <= today && !days.contains(s.day) {
            guard let note = found.first(where: { $0.day == s.day && !taken.contains($0.id ?? "") }), let id = note.id else { continue }
            out.append((key: s.key, note: note))
            taken.insert(id)
            days.insert(s.day)
        }
        return out
    }

    /*
     * 2.19 (his pick, 27 Nov 2026: "Add it as Extra workout"): a Workout Companion strength session on a
     * day that has NO strength session in the plan at all (a rest day, a mobility day) becomes an Extra
     * workout by itself. Today and the 13 days before, never ahead; each note once (`used` holds the ids
     * already turned into a tick or an extra); at most one per day, and none on a day that already has a
     * Strength extra. A day with planned strength is left to `strengthTicks` (to do → ticked; done or
     * missed → nothing), so a session is never counted twice.
     */
    public static func companionExtras(notes: NeighbourNotes?, plannedStrengthDays: Set<String>, strengthExtraDays: Set<String>,
                                       used: Set<String>, today: String) -> [NeighbourDone] {
        guard let notes, (notes.format ?? NeighbourNotes.knownFormat) <= NeighbourNotes.knownFormat else { return [] }
        let oldest = addDays(today, -(keepDays - 1))
        var days = strengthExtraDays
        var out: [NeighbourDone] = []
        let found = distinct(notes).filter { $0.kind == "strength" && $0.from != "morning" && !($0.id ?? "").isEmpty }
        for note in found.sorted(by: { ($0.day ?? "", $0.at ?? "") < ($1.day ?? "", $1.at ?? "") }) {
            guard let day = note.day, let id = note.id, day <= today, day >= oldest,
                  !plannedStrengthDays.contains(day), !days.contains(day), !used.contains(id) else { continue }
            out.append(note)
            days.insert(day)
        }
        return out
    }

    /* The Extra workout a Workout Companion session becomes (2.19): Strength, its minutes and effort, training. */
    public static func companionExtra(_ note: NeighbourDone) -> ExtraEntry {
        var e = ExtraEntry(date: note.day ?? "", activity: "strength")
        if let m = note.minutes, m > 0 { e.minutes = Double(m) }
        if let f = note.effort, (1...10).contains(f) { e.effort = Double(f) }
        e.isTraining = true
        e.notes = companionNote
        return e
    }

    public static let companionNote = "From Workout Companion"

    /* The note's `from` as it goes into the log (2.16): "morning" for Magic Morning, else "workouts". */
    public static func tickSource(_ note: NeighbourDone) -> String { note.from == "morning" ? "morning" : "workouts" }

    /* "Ticked from Magic Morning" / "… Workout Companion" / "… Garmin" (2.17) for a log's `tickedFrom`; nil when logged by hand. */
    public static func tickedLine(from: String?) -> String? {
        switch from {
        case "morning": return "Ticked from Magic Morning"
        case "workouts": return "Ticked from Workout Companion"
        case let f? where f == "garmin" || f.hasPrefix("garmin:"): return "Ticked from Garmin"
        default: return nil
        }
    }

    /*
     * Strength ticked from Garmin (2.17): per day up to today, the first strength session still to do gets
     * the first Garmin strength activity of that day (by start time) that is 10 minutes or longer and not
     * used yet. `used` holds the activity ids already in a log (`garminIdsUsed`).
     */
    public static let garminMinimumSeconds: Double = 600

    public static func garminStrengthTicks(todo: [(key: String, day: String)], activities: [GarminActivitySummary],
                                           used: Set<Int> = [], today: String) -> [(key: String, activity: GarminActivitySummary)] {
        let strength = activities
            .filter { GarminActivity.family(ofGarmin: $0.typeKey) == "strength" && $0.seconds >= garminMinimumSeconds }
            .sorted { ($0.startGMT ?? .distantPast, $0.id) < ($1.startGMT ?? .distantPast, $1.id) }
        var taken = used
        var days = Set<String>()
        var out: [(key: String, activity: GarminActivitySummary)] = []
        for s in todo.sorted(by: { $0.day < $1.day }) where s.day <= today && !days.contains(s.day) {
            guard let a = strength.first(where: { $0.day == s.day && !taken.contains($0.id) }) else { continue }
            out.append((key: s.key, activity: a))
            taken.insert(a.id)
            days.insert(s.day)
        }
        return out
    }

    /* "garmin:<activity id>" — what a Garmin tick leaves in the log. */
    public static func garminSource(_ a: GarminActivitySummary) -> String { "garmin:\(a.id)" }

    /* The Garmin activities already used by a tick, read from the logs themselves — the same on every device. */
    public static func garminIdsUsed(_ sessions: [Workout]) -> Set<Int> {
        Set(sessions.compactMap { w in
            guard let from = tickedFrom(w), from.hasPrefix("garmin:") else { return nil }
            return Int(from.dropFirst("garmin:".count))
        })
    }

    /* Progress (2.17): the plan's strength sessions from the 1st of this month up to today — done, of planned. Missed = not done. */
    public static func strengthMonth(_ sessions: [Workout], today: String) -> (done: Int, planned: Int) {
        let month = String(today.prefix(7))
        var done = 0, planned = 0
        for w in sessions where w.discipline.id == "strength" && w.dayKey.hasPrefix(month) && w.dayKey <= today {
            planned += 1
            if w.logged && !w.missed && w.pending?.missed != true { done += 1 }
        }
        return (done, planned)
    }

    /* Where a session's tick came from: what is waiting to be written first, else what the plan holds. */
    public static func tickedFrom(_ w: Workout) -> String? {
        if let p = w.pending, !p.missed, let from = p.tickedFrom, !from.isEmpty { return from }
        return w.results[PlanBook.tickedFromField]?.text
    }

    /*
     * Progress (2.16): the mobility sessions logged in the plan — those ticked from Magic Morning, and the
     * rest ("by hand"). Missed ones are not counted.
     */
    public static func mobilitySources(_ sessions: [Workout]) -> (fromMorning: Int, byHand: Int) {
        var morning = 0, hand = 0
        for w in sessions where w.discipline.id == "mobility" && w.logged && !w.missed && w.pending?.missed != true {
            if tickedFrom(w) == "morning" { morning += 1 } else { hand += 1 }
        }
        return (morning, hand)
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

    /* "Done in Workout Companion at 07:40 · 35 min" (or "Done in Magic Morning …" for its notes) — the time in the phone's own zone; a missing part is left out. */
    public static func doneLine(_ note: NeighbourDone, timeZone: TimeZone = .current) -> String {
        var line = "Done in " + (note.from == "morning" ? "Magic Morning" : "Workout Companion")
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
