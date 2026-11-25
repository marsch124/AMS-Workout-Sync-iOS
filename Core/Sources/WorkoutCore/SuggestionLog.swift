import Foundation

/*
 * The app's side of the rule book, the part that needs no screen: what is
 * kept of every card (suggestions.json), the calm rules around showing one
 * (one a day, closed when its day has passed), and how a card he takes
 * becomes ordinary changes to the plan — each one in "Changes to the plan",
 * each one undoable, all of them carrying the same why-line.
 *
 * Pure: no clock but the `today` handed in, no files. The app reads and
 * writes the bytes; a file that cannot be read is never guessed at.
 */

// MARK: - one card, as it is kept

public struct SuggestionEntry: Codable, Equatable, Identifiable, Sendable {
    public var record: SuggestionRecord
    /* The words of the other choices, in order (record.choices[1...]). */
    public var otherHeadlines: [String]
    /* A plan review (T6): nothing to take here, only to keep. */
    public var isReview: Bool
    /* The plan changes "Take it" made, oldest first: what one Undo takes back. */
    public var changeIDs: [String]
    /* Taken, then taken back with Undo. */
    public var undone: Bool
    /*
     * For each choice (the card's own first), the sessions it changes as they
     * stood when the card was made. At the tap the plan must still say exactly
     * this, or nothing is written.
     */
    public var before: [[RBBefore]]
    /* Claude was asked about this card (once, ever), and whether its answer was used. */
    public var claudeAsked = false
    public var claudePicked = false

    public var id: String { record.id }

    public init(record: SuggestionRecord, otherHeadlines: [String] = [], isReview: Bool = false,
                changeIDs: [String] = [], undone: Bool = false, before: [[RBBefore]] = []) {
        self.record = record; self.otherHeadlines = otherHeadlines; self.isReview = isReview
        self.changeIDs = changeIDs; self.undone = undone; self.before = before
    }

    /* A card as the engine made it, with what each choice would change, from the same input. */
    public init(_ s: Suggestion, input: RuleBookInput) {
        self.init(record: s.record, otherHeadlines: s.otherChoices.map(\.headline), isReview: s.review != nil,
                  before: s.record.choices.map { SuggestionApply.touched($0, input: input)?.map(RBBefore.init) ?? [] })
    }

    /* Without a snapshot: such a card can be kept or closed, never taken. */
    public init(_ s: Suggestion) {
        self.init(record: s.record, otherHeadlines: s.otherChoices.map(\.headline), isReview: s.review != nil)
    }

    enum CodingKeys: String, CodingKey { case record, otherHeadlines, isReview, changeIDs, undone, before, claudeAsked, claudePicked }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        record = try c.decode(SuggestionRecord.self, forKey: .record)
        otherHeadlines = try c.decodeIfPresent([String].self, forKey: .otherHeadlines) ?? []
        isReview = try c.decodeIfPresent(Bool.self, forKey: .isReview) ?? false
        changeIDs = try c.decodeIfPresent([String].self, forKey: .changeIDs) ?? []
        undone = try c.decodeIfPresent(Bool.self, forKey: .undone) ?? false
        before = try c.decodeIfPresent([[RBBefore]].self, forKey: .before) ?? []
        claudeAsked = try c.decodeIfPresent(Bool.self, forKey: .claudeAsked) ?? false
        claudePicked = try c.decodeIfPresent(Bool.self, forKey: .claudePicked) ?? false
    }

    public var headline: String { record.headline }
    public var why: String { record.why }
}

/* One session as a card found it: what must still hold when he taps. */
public struct RBBefore: Codable, Equatable, Sendable {
    public var id: String
    public var day: String
    public var sport: RBSport
    public var title: String
    public var plannedMin: Int
    public var intensity: String
    public var status: RBStatus
    public var dropped: Bool

    public init(_ s: RBSession) {
        id = s.id; day = s.day; sport = s.sport; title = s.title; plannedMin = s.plannedMin
        intensity = s.intensity; status = s.status; dropped = s.dropped
    }
}

// MARK: - everything the keeper keeps

public struct SuggestionKeep: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format = SuggestionKeep.currentFormat
    /* "Suggest changes to my plan": nil until he touches it, which means on. */
    public var on: Bool?
    /* His five answers and the tunable numbers. */
    public var settings = RuleBookSettings()
    /* Every card, oldest first. */
    public var entries: [SuggestionEntry] = []
    /* Stop sign and illness taps. */
    public var health = RBHealthTaps()
    /* Days he tapped a place under "Something hurts?". */
    public var hurtDays: [String] = []
    /* Sessions already asked "Something hurts?", with what he answered ("none" for nothing). */
    public var hurtAsked: [String: String] = [:]
    /* The plan these notes belong to (its taken-in moment): a new plan starts a fresh log. */
    public var plan: Double?
    /* When the stop sign and the illness taps last changed, for sharing them with his other devices (PauseShare). */
    public var stopStamp = PauseStamp.never
    public var illStamp = PauseStamp.never

    public init() {}

    enum CodingKeys: String, CodingKey { case format, on, settings, entries, health, hurtDays, hurtAsked, plan, stopStamp, illStamp, later }

    /*
     * Cards of a trigger that builds before round 28 do not know (the away card, "AW").
     * An older build reading such a card in `entries` would call the whole file unreadable
     * and rest every suggestion (and stop sharing the pause) on this device. So they are
     * written apart, under "later", each with its place in the list; an older build skips
     * that key and reads the rest as always. Read back, every card is in its place again.
     */
    public static let triggersOlderBuildsKnow: Set<RBTrigger> = [.section5, .cameInBreaking, .t1, .t2, .t3, .t4, .t5, .t6, .hurts, .backToBack]

    struct Later: Codable, Equatable {
        var at: Int
        var entry: SuggestionEntry
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encodeIfPresent(on, forKey: .on)
        try c.encode(settings, forKey: .settings)
        var classic: [SuggestionEntry] = []
        var later: [Later] = []
        for (i, e) in entries.enumerated() {
            if Self.triggersOlderBuildsKnow.contains(e.record.trigger) { classic.append(e) } else { later.append(Later(at: i, entry: e)) }
        }
        try c.encode(classic, forKey: .entries)
        if !later.isEmpty { try c.encode(later, forKey: .later) }
        try c.encode(health, forKey: .health)
        try c.encode(hurtDays, forKey: .hurtDays)
        try c.encode(hurtAsked, forKey: .hurtAsked)
        try c.encodeIfPresent(plan, forKey: .plan)
        try c.encode(stopStamp, forKey: .stopStamp)
        try c.encode(illStamp, forKey: .illStamp)
    }

    /* The stop sign and illness taps as they are shared through iCloud. */
    public var pause: PauseShare { PauseShare(health: health, stop: stopStamp, ill: illStamp) }

    /* A tap here moved the taps from `was`: stamp what changed, so the other devices can tell. */
    public mutating func stampPause(from was: PauseShare, now: Date = Date()) {
        let p = PauseShare.stamped(was, to: health, now: now)
        stopStamp = p.stop
        illStamp = p.ill
    }

    /* The taps as joined with his other devices. */
    public mutating func takePause(_ p: PauseShare) {
        health = p.health
        stopStamp = p.stop
        illStamp = p.ill
    }

    /*
     * Every part must read, or the whole file counts as unreadable: the app
     * then shows nothing and writes nothing, rather than save the defaults
     * over his answers or end a pause without a word. Only a part that is
     * missing altogether (an older file) takes its default.
     */
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? SuggestionKeep.currentFormat
        on = try c.decodeIfPresent(Bool.self, forKey: .on)
        settings = try c.decodeIfPresent(RuleBookSettings.self, forKey: .settings) ?? RuleBookSettings()
        entries = try c.decodeIfPresent([SuggestionEntry].self, forKey: .entries) ?? []
        // Cards written apart for older builds, put back in their places (an older build that wrote the file since has dropped them).
        for l in (try c.decodeIfPresent([Later].self, forKey: .later) ?? []).sorted(by: { $0.at < $1.at }) {
            entries.insert(l.entry, at: min(max(0, l.at), entries.count))
        }
        health = try c.decodeIfPresent(RBHealthTaps.self, forKey: .health) ?? RBHealthTaps()
        hurtDays = try c.decodeIfPresent([String].self, forKey: .hurtDays) ?? []
        hurtAsked = try c.decodeIfPresent([String: String].self, forKey: .hurtAsked) ?? [:]
        plan = try c.decodeIfPresent(Double.self, forKey: .plan)
        stopStamp = try c.decodeIfPresent(PauseStamp.self, forKey: .stopStamp) ?? .never
        illStamp = try c.decodeIfPresent(PauseStamp.self, forKey: .illStamp) ?? .never
    }

    /* The notes belong to the plan taken in at `stamp`; a different plan starts a fresh log (his answers and taps stay). */
    @discardableResult
    public mutating func belong(to stamp: Double) -> Bool {
        guard plan != stamp else { return false }
        if plan != nil { entries = []; hurtAsked = [:] }
        plan = stamp
        return true
    }

    public var isOn: Bool { on ?? true }

    /* What the rule book reads for its cool-downs and its "one a day". */
    public var log: [SuggestionRecord] { entries.map(\.record) }

    public var newestFirst: [SuggestionEntry] { entries.reversed() }

    public static func decoded(_ data: Data) throws -> SuggestionKeep {
        let keep = try JSONDecoder().decode(SuggestionKeep.self, from: data)
        guard keep.format <= currentFormat else { throw CocoaError(.fileReadCorruptFile) }
        return keep
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    // MARK: the calm rules

    /* A card left unanswered closes as "Keep my plan", silently, after its day. */
    public mutating func closeStale(today: String) {
        for i in entries.indices where entries[i].record.answer == nil && entries[i].record.closesOn < today {
            entries[i].record.answer = .closedUnanswered
            entries[i].record.answeredOn = entries[i].record.closesOn
        }
    }

    /* The card waiting for his answer today, if any. */
    public func openEntry(on today: String) -> SuggestionEntry? {
        entries.last { $0.record.isOpen(on: today) }
    }

    /* A card taken today and not undone: its place shows "Changed — Undo" until the day ends. */
    public func changedEntry(on today: String) -> SuggestionEntry? {
        entries.last { $0.record.wasTaken && $0.record.answeredOn == today && !$0.undone }
    }

    /*
     * Never a second card the same day, and never one while another is open.
     * His own taps (stop sign, illness, the return after it) are the exception:
     * their card may follow another the same day, once the other is answered.
     */
    public func mayShowNew(on today: String, trigger: RBTrigger? = nil) -> Bool {
        guard openEntry(on: today) == nil else { return false }
        let sameDay = entries.filter { $0.record.day == today }
        if trigger == .section5 { return !sameDay.contains { $0.record.trigger == .section5 } }
        return sameDay.isEmpty
    }

    @discardableResult
    public mutating func add(_ entry: SuggestionEntry, today: String) -> Bool {
        guard mayShowNew(on: today, trigger: entry.record.trigger), entry.record.day == today else { return false }
        entries.append(entry)
        return true
    }

    /* Closed without a change: the plan had moved on, or he paused. */
    public mutating func putAway(_ id: String, _ answer: RBAnswer, on day: String) {
        guard let i = entries.lastIndex(where: { $0.id == id }), entries[i].record.answer == nil else { return }
        entries[i].record.answer = answer
        entries[i].record.answeredOn = day
    }

    /* Every open card closed (the stop sign, an illness): the ids closed. */
    @discardableResult
    public mutating func putAwayOpen(_ answer: RBAnswer, on day: String) -> [String] {
        let open = entries.filter { $0.record.isOpen(on: day) }.map(\.id)
        for id in open { putAway(id, answer, on: day) }
        return open
    }

    /* A taken answer taken back before the plan was written (the plan could not be saved). */
    public mutating func unanswer(_ id: String) {
        guard let i = entries.lastIndex(where: { $0.id == id }) else { return }
        entries[i].record.answer = nil
        entries[i].record.answeredOn = nil
        entries[i].changeIDs = []
    }

    public mutating func answer(_ id: String, _ answer: RBAnswer, on day: String, changeIDs: [String] = []) {
        guard let i = entries.lastIndex(where: { $0.id == id }), entries[i].record.answer == nil else { return }
        entries[i].record.answer = answer
        entries[i].record.answeredOn = day
        entries[i].changeIDs = changeIDs
    }

    /*
     * Undo of a taken card. The rule book then reads it as kept, so a session
     * it dropped is no longer counted as dropped; the log still says it was
     * taken and undone.
     */
    public mutating func undo(_ id: String) {
        guard let i = entries.lastIndex(where: { $0.id == id }), entries[i].record.wasTaken else { return }
        entries[i].undone = true
        entries[i].record.answer = .keptPlan
    }

    /* His answer in words, for "What was suggested". */
    public func answerWords(_ e: SuggestionEntry, today: String) -> String {
        if e.undone {
            if let i = e.takenIndex, i > 0, e.otherHeadlines.indices.contains(i - 1) {
                return "Other choice: \(e.otherHeadlines[i - 1]) — undone"
            }
            return "Taken, then undone"
        }
        switch e.record.answer {
        case .took(let i)?:
            if i > 0, e.otherHeadlines.indices.contains(i - 1) { return "Other choice: " + e.otherHeadlines[i - 1] }
            return "Taken"
        case .keptPlan?: return "Kept my plan"
        case .planChanged?: return "Put away \u{2014} the plan had changed"
        case .paused?: return "Put away \u{2014} you paused"
        case .closedUnanswered?: return "No answer"
        case nil: return e.record.isOpen(on: today) ? "No answer yet" : "No answer"
        }
    }

    // MARK: "Something hurts?"

    public func wasAskedHurts(_ session: String) -> Bool { hurtAsked[session] != nil }

    /* The places that mark the day; "other" and "Nothing hurts" are only remembered. */
    public static let markingPlaces: Set<String> = ["calf", "achilles", "knee"]

    /* A place, or nil for "Nothing hurts". Only calf, Achilles or knee marks the day. */
    public mutating func hurts(_ place: String?, session: String, on day: String) {
        hurtAsked[session] = place ?? "none"
        if let place, SuggestionKeep.markingPlaces.contains(place), !hurtDays.contains(day) { hurtDays.append(day) }
    }
}

extension SuggestionEntry {
    /* Which choice he took (0 the card's own), also after an Undo. */
    public var takenIndex: Int? {
        if case .took(let i)? = record.answer { return i }
        return undone ? 0 : nil
    }
}

// MARK: - a taken card, as changes to the plan

/* One session's part in a taken card. Only what differs is set. */
public enum SuggestionEdit: Equatable, Sendable {
    case change(key: String, day: String?, minutes: Int?, intensity: String?, title: String?, sport: RBSport?, star: Bool?)
    /* Dropped: it becomes "Rest (your choice)" — followed, never missed. */
    case drop(key: String)
    /* A copy of a session on another day (an easy week brought forward). */
    case add(copyOf: String, day: String)

    public var key: String {
        switch self {
        case .change(let k, _, _, _, _, _, _), .drop(let k): return k
        case .add(let k, _): return k
        }
    }
}

public enum SuggestionApply {
    public static let restTitle = "Rest (your choice)"

    /* The plan's sessions the moves change, as edits; in the plan's own order, additions last. */
    public static func edits(for moves: [Move], input: RuleBookInput) throws -> [SuggestionEdit] {
        let after = try RuleBook.apply(moves, to: input.sessions, input: input)
        let new = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [SuggestionEdit] = []
        for b in input.sessions {
            guard let a = new[b.id] else { continue }
            if a.dropped && !b.dropped { out.append(.drop(key: b.id)); continue }
            let edit = SuggestionEdit.change(
                key: b.id, day: a.day != b.day ? a.day : nil, minutes: a.plannedMin != b.plannedMin ? a.plannedMin : nil,
                intensity: a.intensity != b.intensity ? a.intensity : nil, title: a.title != b.title ? a.title : nil,
                sport: a.sport != b.sport ? a.sport : nil, star: a.star != b.star ? a.star : nil)
            if edit != .change(key: b.id, day: nil, minutes: nil, intensity: nil, title: nil, sport: nil, star: nil) {
                out.append(edit)
            }
        }
        let known = Set(input.sessions.map(\.id))
        for a in after where !known.contains(a.id) {
            let source = String(a.id.split(separator: "@").first ?? Substring(a.id))
            out.append(.add(copyOf: source, day: a.day))
        }
        return out
    }

    // MARK: does the card still fit?

    /*
     * The plan's sessions a choice would change, as they stand now: those it
     * changes, the sources of any copies it adds, and for an extra rest day
     * every session on that day (a logged one too, so it is seen). Nil when
     * the moves no longer fit the plan at all.
     */
    public static func touched(_ moves: [Move], input: RuleBookInput) -> [RBSession]? {
        guard let after = try? RuleBook.apply(moves, to: input.sessions, input: input) else { return nil }
        let old = Dictionary(input.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ids = Set<String>()
        for a in after {
            if let b = old[a.id] {
                if a != b { ids.insert(a.id) }
            } else {
                ids.insert(String(a.id.split(separator: "@").first ?? Substring(a.id)))
            }
        }
        for case .extraRestDay(let day) in moves {
            for s in input.sessions where s.day == day && !s.isRest { ids.insert(s.id) }
        }
        return input.sessions.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
    }

    /*
     * Whether choice `i` of a card may be written into the plan as it is NOW.
     * No when: the sessions it changes are not exactly as they were when the
     * card was made; one of them is logged; one missed is not moved forward;
     * anything would end up longer or harder than it is now; anything before
     * today would change; the hard limits fail on today's plan (the calm rules
     * aside — this card was already allowed); or nothing would change at all.
     */
    public static func fits(_ entry: SuggestionEntry, choice i: Int, input: RuleBookInput) -> Bool {
        guard let moves = entry.record.choice(i) else { return false }
        if moves.isEmpty { return entry.isReview }
        guard entry.before.indices.contains(i), !entry.before[i].isEmpty,
              let now = touched(moves, input: input) else { return false }
        let snap = entry.before[i].sorted { $0.id < $1.id }
        guard now.map(RBBefore.init) == snap else { return false }
        guard let after = try? RuleBook.apply(moves, to: input.sessions, input: input) else { return false }
        let new = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func top(_ x: RBSession) -> Int {
            x.sport == .strength ? (RuleBook.zones(x.intensity).rpeTop ?? 0) : (RuleBook.zones(x.intensity).top ?? 0)
        }
        for b in now {
            if b.status == .done { return false }
            guard let a = new[b.id] else { return false }
            if b.status == .missed && !(a.day != b.day && a.day >= input.today) { return false }
            if a == b { continue }
            if a.plannedMin > b.plannedMin || (top(a) > top(b) && !a.dropped) { return false }
            if a.day < input.today { return false }
        }
        let known = Set(input.sessions.map(\.id))
        if after.contains(where: { !known.contains($0.id) && $0.day < input.today }) { return false }
        var check = input
        check.log.removeAll { $0.id == entry.id }
        let failures = RuleBook.limitFailures(moves, trigger: entry.record.trigger, input: check)
        guard failures.allSatisfy({ $0.limit == .l11 }) else { return false }
        guard let edits = try? edits(for: moves, input: input), !edits.isEmpty else { return false }
        return true
    }

    /* The why-line a taken choice writes beside each of its changes. */
    public static func why(_ headline: String) -> String { "Suggestion: " + headline }

    /* A card whose changes are already in the plan (taken before, on this device or another): never twice. */
    public static func alreadyInPlan(_ entry: SuggestionEntry, headline: String, book: PlanBook) -> Bool {
        let line = why(headline)
        let since = parseDayKey(entry.record.day).map { $0.addingTimeInterval(-86_400) } ?? .distantPast
        let keys = Set(entry.before.flatMap { $0.map(\.id) })
        if !entry.changeIDs.isEmpty, book.changes.contains(where: { entry.changeIDs.contains($0.id) && !$0.undone }) { return true }
        return book.changes.contains { $0.why == line && !$0.undone && $0.at >= since && keys.contains($0.key) }
    }

    /* Of a taken card's changes, those still in the plan and not undone. */
    public static func liveIDs(_ ids: [String], in book: PlanBook) -> [String] {
        ids.filter { id in book.changes.contains { $0.id == id && !$0.undone } }
    }

    /* What the Change page would hold after the edit. */
    public static func draft(for edit: SuggestionEdit, from base: SessionDraft) -> SessionDraft {
        var d = base
        switch edit {
        case .drop:
            return restDraft(from: base)
        case .change(_, let day, let minutes, let intensity, let title, let sport, let star):
            if let day { d.dayKey = day }
            if let minutes { d.minutes = Double(minutes) }
            if let intensity { d.intensity = intensity }
            if let title { d.title = title }
            if let sport { d.sport = sport.rawValue }
            if let star { d.isKey = star }
        case .add(_, let day):
            d.dayKey = day
        }
        return d
    }

    /* A dropped session: rest, on its own day, saying what it was. */
    public static func restDraft(from base: SessionDraft) -> SessionDraft {
        let length = base.minutes.map { $0 > 0 ? ", \(Int($0.rounded())) min" : "" } ?? ""
        return SessionDraft(dayKey: base.dayKey, sport: "rest", title: restTitle, minutes: nil, intensity: "",
                            purpose: "Instead of: \(base.title)\(length).", isKey: false)
    }

    /*
     * The card's moves, written into the book as ordinary changes, all with
     * the same why-line. Returns the ids of the changes made, oldest first.
     * Either all of them land or the book is left as it was.
     */
    public static func take(_ moves: [Move], input: RuleBookInput, to book: inout PlanBook, why: String,
                            now: Date = Date()) throws -> [String] {
        let edits = try edits(for: moves, input: input)
        var copy = book
        var ids: [String] = []
        for edit in edits {
            guard let base = copy.draft(of: edit.key) else { throw BookError.noSession(edit.key) }
            let d = draft(for: edit, from: base)
            switch edit {
            case .add:
                _ = try copy.add(d, why: why, now: now)
                if let id = copy.changes.last?.id { ids.append(id) }
            default:
                let was = copy.session(edit.key)
                if let change = try copy.change(edit.key, to: d, why: why, now: now) {
                    ids.append(change.id)
                    if let was, d.dayKey != was.dayKey {
                        let from = copy.moves[was.key]?.from ?? was.dayKey
                        copy.moves[was.key] = MoveRecord(from: from, to: d.dayKey, disciplineId: was.discipline.id, at: now)
                    }
                }
            }
        }
        book = copy
        return ids
    }

    /* One Undo for a whole taken card: newest change first. Refused as a whole if any was changed again since. */
    public static func undo(_ ids: [String], in book: inout PlanBook, now: Date = Date()) throws {
        guard ids.allSatisfy({ book.canUndo($0) }) else { throw BookError.newerChange }
        var copy = book
        for id in ids.reversed() { try copy.undo(id, now: now) }
        book = copy
    }

    // MARK: his own edits

    /* The plan as it would be after his own change of one session (key nil: a new one). */
    public static func edited(_ input: RuleBookInput, key: String?, to d: SessionDraft) -> [RBSession] {
        var out = input.sessions
        let minutes = Int((d.minutes ?? 0).rounded())
        if let key, let i = out.firstIndex(where: { $0.id == key }) {
            out[i].day = d.dayKey
            out[i].sport = RBSport(disciplineID: d.sport)
            out[i].title = d.title
            out[i].plannedMin = minutes
            out[i].intensity = d.intensity
            out[i].star = d.isKey
        } else if key == nil {
            out.append(RBSession(id: "new", day: d.dayKey, sport: RBSport(disciplineID: d.sport), title: d.title,
                                 plannedMin: minutes, intensity: d.intensity, star: d.isKey, row: Int.max,
                                 originalWeek: input.week(of: d.dayKey), slot: .other, addedByMove: true))
        }
        return out
    }

    /*
     * The one calm grey line for his own change, or nil. Only the first
     * warning, and only its statement: he is never asked a question.
     */
    public static func note(before: [RBSession], after: [RBSession], input: RuleBookInput) -> String? {
        guard before != after, let first = RuleBook.warnings(before: before, after: after, input: input).first else { return nil }
        return statement(first)
    }

    /* His own change of one session (key nil: a new one), as the grey line it earns, or nil. */
    public static func note(changing key: String?, to d: SessionDraft, input: RuleBookInput) -> String? {
        note(before: input.sessions, after: edited(input, key: key, to: d), input: input)
    }

    /* His own move of one session to another day. */
    public static func note(moving key: String, to day: String, input: RuleBookInput) -> String? {
        var after = input.sessions
        guard let i = after.firstIndex(where: { $0.id == key }), after[i].day != day else { return nil }
        after[i].day = day
        return note(before: input.sessions, after: after, input: input)
    }

    /* "Friday is your rest day. Move anyway?" → "Friday is your rest day." */
    public static func statement(_ line: String) -> String {
        let parts = line.components(separatedBy: ". ")
        guard parts.count > 1, parts.last?.hasSuffix("?") == true else { return line }
        return parts.dropLast().joined(separator: ". ") + "."
    }
}
