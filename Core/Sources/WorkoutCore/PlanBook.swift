import Foundation

/*
 * The plan, living in the app.
 *
 * Until 2.0 the plan's home was an Excel workbook in Dropbox, and this app a
 * careful guest in it. The book is the plan's own home: every session, every
 * extra, the zones and the weeks, as one document the app owns.
 *
 * Three rules shaped it, each from something that went wrong with the file:
 *
 *   - A session keeps the name it had in the workbook ("Weekly Schedules!7")
 *     for good. Photographs, the move log and the Training calendar all hang
 *     on that name, and a session that changed it would quietly lose them.
 *   - What is logged is turned into values by the very code that wrote the
 *     workbook (Plan.buildEdits) and stored the way the reader would have read
 *     it back. So "done as planned" means exactly what it meant in Excel, to
 *     the minute — and a test holds the two side by side to prove it.
 *   - It is read tolerantly. A book written by an older app must never fail
 *     to open because a newer one grew a field (the queue's lesson, 30 Sep).
 */

public struct PlanWeek: Codable, Equatable, Identifiable {
    public var id: Int { number }
    public let number: Int
    /* The Monday the week starts on, as a day key. */
    public let monday: String
    public let phase: String
    /* "TEST WEEK", "RECOVERY" … as the plan's own heading says; empty for an ordinary week. */
    public let tag: String

    public init(number: Int, monday: String, phase: String, tag: String) {
        self.number = number; self.monday = monday; self.phase = phase; self.tag = tag
    }

    public var isEasy: Bool { normalise(tag).contains("recovery") || normalise(tag).contains("easy") }
    public var isTest: Bool { normalise(tag).contains("test") }
}

/* One change to the plan itself — not a log, a change of what was planned. */
public struct PlanChange: Codable, Equatable, Identifiable {
    public let id: String
    public let at: Date
    /* edit | add | remove */
    public let kind: String
    public let key: String
    public let title: String
    public let before: String
    public let after: String
    public let why: String
    /* The session as it was, so the change can be taken back. Nil for an added one. */
    public var undo: Workout?
    public var undone: Bool = false
    /* The day the change left the session on: an undo moves it back only if it is still there. */
    public var afterDay: String?
    /* A removal: the mark of the log the session had then, so a merge can tell a log the removing device saw from one it never saw. */
    public var logAt: Date?

    public init(id: String = UUID().uuidString, at: Date, kind: String, key: String, title: String,
                before: String, after: String, why: String, undo: Workout?, afterDay: String? = nil, logAt: Date? = nil) {
        self.id = id; self.at = at; self.kind = kind; self.key = key; self.title = title
        self.before = before; self.after = after; self.why = why; self.undo = undo; self.afterDay = afterDay
        self.logAt = logAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        at = (try? c.decode(Date.self, forKey: .at)) ?? Date(timeIntervalSince1970: 0)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "edit"
        key = (try? c.decode(String.self, forKey: .key)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        before = (try? c.decode(String.self, forKey: .before)) ?? ""
        after = (try? c.decode(String.self, forKey: .after)) ?? ""
        why = (try? c.decode(String.self, forKey: .why)) ?? ""
        undo = try? c.decodeIfPresent(Workout.self, forKey: .undo)
        undone = (try? c.decodeIfPresent(Bool.self, forKey: .undone)) ?? false
        afterDay = try? c.decodeIfPresent(String.self, forKey: .afterDay)
        logAt = try? c.decodeIfPresent(Date.self, forKey: .logAt)
    }
}

/* Where the book came from: the one-time import. */
public struct PlanOrigin: Codable, Equatable {
    public var fileName: String
    public var takenAt: Date
    public var sessions: Int
    public var extras: Int
    /* Format 2: the last row the imported Extras sheet had; extras made in the app are numbered after it. Nil in an older book. */
    public var extrasLastRow: Int? = nil
    /* Format 2: SHA-256 of the frozen original workbook, filled by the Store. */
    public var originalHash: String? = nil

    public init(fileName: String, takenAt: Date, sessions: Int, extras: Int,
                extrasLastRow: Int? = nil, originalHash: String? = nil) {
        self.fileName = fileName; self.takenAt = takenAt; self.sessions = sessions; self.extras = extras
        self.extrasLastRow = extrasLastRow; self.originalHash = originalHash
    }
}

/* What the page for changing a session holds. Minutes are minutes, whatever the plan counts in. */
public struct SessionDraft: Equatable {
    public var dayKey: String
    /* A discipline id: swim, bike, run, strength, mobility, brick, race, rest, other. */
    public var sport: String
    public var title: String
    public var minutes: Double?
    public var intensity: String
    public var purpose: String
    public var isKey: Bool

    public init(dayKey: String, sport: String, title: String = "", minutes: Double? = nil,
                intensity: String = "", purpose: String = "", isKey: Bool = false) {
        self.dayKey = dayKey; self.sport = sport; self.title = title; self.minutes = minutes
        self.intensity = intensity; self.purpose = purpose; self.isKey = isKey
    }
}

public enum BookError: Error, LocalizedError, Equatable {
    case noSession(String)
    case noExtra(String)
    case badDay(String)
    case nothingToUndo
    case newerChange
    case newerApp

    public var errorDescription: String? {
        switch self {
        case .noSession(let title): return "\u{201C}\(title)\u{201D} is no longer in the plan."
        case .noExtra(let label): return "That \(label) is no longer among your extra workouts."
        case .badDay(let key): return "\u{201C}\(key)\u{201D} is not a day."
        case .nothingToUndo: return "There is nothing to undo."
        case .newerChange: return "This session was changed again later. Undo the newest change to it first."
        case .newerApp: return "This plan was saved by a newer version of the app. Update the app on this device first; nothing was changed."
        }
    }
}

public enum Applied: Equatable { case written, dropped }

public struct PlanBook: Codable, Equatable {
    public static let currentFormat = 2
    public static let appSheet = "App"

    public var format: Int = PlanBook.currentFormat
    public var sessions: [Workout]
    public var extras: [ExtraRecord]
    public var zones: Zones?
    /* The test blocks, in order: those with numbers and those still to come. The zones follow the last numbers. */
    public var tests: [TestResult] = []
    public var weeks: [PlanWeek]
    /* Units and which boxes a session has, as the workbook had them. */
    public var mapping: Mapping
    public var origin: PlanOrigin
    public var changes: [PlanChange] = []
    /* When each session or extra last changed — what "the newest change wins" goes by between devices. */
    public var stamps: [String: Date] = [:]
    /* Sessions taken out of the plan, and when: so another device does not bring one back. */
    public var removed: [String: Date] = [:]
    public var counter: Int = 0
    /* The entries already written in, by their ids: one that comes round again is not written twice. */
    public var applied: [String] = []
    /* When each of them was written, so the list is trimmed by age — the oldest go first. */
    public var appliedAt: [String: Date] = [:]
    /* Format 2: the move log (a session moved from one day to another), so every device reads the same one. */
    public var moves: [String: MoveRecord] = [:]

    public init(sessions: [Workout], extras: [ExtraRecord], zones: Zones?, weeks: [PlanWeek],
                mapping: Mapping, origin: PlanOrigin) {
        self.sessions = sessions; self.extras = extras; self.zones = zones; self.weeks = weeks
        self.mapping = mapping; self.origin = origin
        // A book taken in just now: every extra it holds is the workbook's own, so the line is its last row.
        if self.origin.extrasLastRow == nil { self.origin.extrasLastRow = max(extras.map(\.row).max() ?? 1, 1) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(Int.self, forKey: .format)) ?? 1
        // The sessions and the mapping are the plan: without them there is no
        // book, and saying so is better than opening an empty one.
        mapping = try c.decode(Mapping.self, forKey: .mapping)
        var read = try c.decode([Workout].self, forKey: .sessions)
        // "Missed" is the done box holding the plan's own word for it; a
        // session cannot know that word by itself, so it is settled here.
        let missedWord = normalise(mapping.missedValue)
        for i in read.indices {
            read[i].missed = read[i].results["done"].map { normalise($0.text) == missedWord } ?? false
        }
        sessions = read
        // A field that is absent is an older book and gets its default. A
        // field that is there and cannot be read is damage: it throws, so the
        // app turns to a safety copy instead of opening without his extras
        // and then saving that emptiness over them.
        extras = try c.decodeIfPresent([ExtraRecord].self, forKey: .extras) ?? []
        zones = try c.decodeIfPresent(Zones.self, forKey: .zones)
        tests = try c.decodeIfPresent([TestResult].self, forKey: .tests) ?? []
        weeks = try c.decodeIfPresent([PlanWeek].self, forKey: .weeks) ?? []
        origin = try c.decodeIfPresent(PlanOrigin.self, forKey: .origin)
            ?? PlanOrigin(fileName: "", takenAt: Date(timeIntervalSince1970: 0), sessions: sessions.count, extras: extras.count)
        changes = try c.decodeIfPresent([PlanChange].self, forKey: .changes) ?? []
        stamps = try c.decodeIfPresent([String: Date].self, forKey: .stamps) ?? [:]
        removed = try c.decodeIfPresent([String: Date].self, forKey: .removed) ?? [:]
        counter = try c.decodeIfPresent(Int.self, forKey: .counter) ?? 0
        applied = try c.decodeIfPresent([String].self, forKey: .applied) ?? []
        appliedAt = (try? c.decodeIfPresent([String: Date].self, forKey: .appliedAt)) ?? [:]
        moves = try c.decodeIfPresent([String: MoveRecord].self, forKey: .moves) ?? [:]
        // A change kept for undoing holds a session as it was; its missed mark is settled the same way.
        for i in changes.indices {
            if let done = changes[i].undo?.results["done"] { changes[i].undo?.missed = normalise(done.text) == missedWord }
        }
        // Format 1 -> 2: nothing is stamped "now". What was logged takes the stamp the session had
        // (it was the only one), and the line between imported and app-made extras is drawn.
        if format < 2 {
            for w in sessions where !w.results.isEmpty {
                if let t = stamps[w.key], stamps["log:" + w.key] == nil { stamps["log:" + w.key] = t }
            }
            format = 2
            if origin.extrasLastRow == nil { origin.extrasLastRow = extrasBoundary }
        }
    }

    /* Written by a newer app: it may hold things this one does not know and would drop on saving. */
    public var isFromNewerApp: Bool { format > PlanBook.currentFormat }

    // MARK: on disk

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        // No call should let a number that is not a number in; if one ever
        // gets there, the plan must still save rather than refuse every save after it.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data) throws -> PlanBook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try decoder.decode(PlanBook.self, from: data)
    }

    // MARK: order

    /* By day, then in the order the plan had them; a session made in the app comes after. */
    static func inOrder(_ sessions: [Workout]) -> [Workout] {
        sessions.enumerated().sorted {
            if $0.element.date != $1.element.date { return $0.element.date < $1.element.date }
            if $0.element.row != $1.element.row { return $0.element.row < $1.element.row }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    static func inOrder(_ extras: [ExtraRecord]) -> [ExtraRecord] {
        extras.sorted { a, b in a.date != b.date ? a.date > b.date : a.row > b.row }
    }

    public func session(_ key: String) -> Workout? { sessions.first { $0.key == key } }

    // MARK: logging

    /*
     * One logged entry, written into the book.
     *
     * The entry is turned into cell edits by Plan.buildEdits — the same
     * function that wrote the workbook — and each edit is stored as the reader
     * would have read that cell back. Nothing about what "logged" means is
     * decided twice.
     */
    public mutating func apply(_ queued: QueuedEntry, now: Date = Date()) throws -> Applied {
        // Written already (the app was stopped between saving the plan and
        // clearing the entry): once is enough.
        if applied.contains(queued.id) { return .written }
        if let extra = queued.extra {
            let how = try apply(extra: extra, now: now)
            remember(queued.id, now: now)
            return how
        }

        // A session's name is for good here, so the name is asked first; the
        // looser search by day and wording is only for an entry made before
        // the plan moved in.
        // An entry that names a session means that session and no other: if it
        // has been taken out of the plan, the entry is refused rather than
        // written into a neighbour that happens to read alike.
        let found = queued.workoutKey.isEmpty ? Sync.findWorkout(for: queued, in: sessions) : session(queued.workoutKey)
        guard let found, let i = sessions.firstIndex(where: { $0.key == found.key }) else {
            throw BookError.noSession(queued.title)
        }
        var w = sessions[i]
        var entry = queued.entry
        // The weekday is worked out from the date now, not kept beside it.
        entry.weekdayNames = nil
        if entry.moveTo == nil && entry.completedAt == nil { entry.completedAt = now }

        let edits = Plan.buildEdits(w, entry, mapping)
        if edits.isEmpty { return .dropped }

        var movedDay = false, wroteLog = false
        for edit in edits {
            switch edit.field {
            case "date":
                if case .date(let day) = edit.value, let key = dayKey(day) { w = w.on(day, key); movedDay = true }
            case "weekday":
                break
            default:
                w.results[edit.field] = PlanBook.readBack(edit.value)
                wroteLog = true
            }
        }
        w.loggedInSheet = Plan.isLogged(w.results)
        w.logged = w.loggedInSheet
        w.missed = w.results["done"].map { normalise($0.text) == normalise(mapping.missedValue) } ?? false
        w.pending = nil
        w.pendingMove = nil
        sessions[i] = w
        sessions = PlanBook.inOrder(sessions)
        // Two sides, two marks: what was planned (the day) and what was logged (the boxes) are
        // merged apart between devices, so a log never overwrites a change of plan, nor the reverse.
        if movedDay { stamps[w.key] = now }
        if wroteLog || !movedDay { stamps["log:" + w.key] = now }
        remember(queued.id, now: now)
        return .written
    }

    /* The list is oldest first (a merge keeps it so), so the ones trimmed off the front are the oldest. */
    private mutating func remember(_ id: String, now: Date) {
        applied.append(id)
        appliedAt[id] = now
        if applied.count > 300 {
            for gone in applied.prefix(applied.count - 300) { appliedAt[gone] = nil }
            applied.removeFirst(applied.count - 300)
        }
    }

    /* A written cell, as Sheet would hand it back. */
    static func readBack(_ value: EditValue) -> ResultValue? {
        switch value {
        case .number(let n):
            return n.isFinite ? ResultValue(text: jsNumberString(n), number: n, date: nil) : nil
        case .text(let t):
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : ResultValue(text: trimmed, number: nil, date: nil)
        case .date(let d):
            return ResultValue(text: dayKey(d) ?? "", number: nil, date: d)
        case .blank:
            return nil
        }
    }

    // MARK: extras

    private static func text(_ n: Double?) -> String { finite(n).map(jsNumberString) ?? "" }
    static func finite(_ n: Double?) -> Double? { n.flatMap { $0.isFinite ? $0 : nil } }

    func extraIndex(_ target: ExtraTarget) -> Int? {
        let byRow = extras.indices.sorted { extras[$0].row < extras[$1].row }
        if !target.ref.isEmpty, let i = byRow.first(where: { extras[$0].ref == target.ref }) { return i }
        return byRow.first { i in
            let r = extras[i]
            return r.ref.isEmpty && r.date == target.date && normalise(r.label) == normalise(target.label)
                && r.minutes == target.minutes
        }
    }

    func alreadyRecorded(_ entry: ExtraEntry) -> Bool {
        if !entry.ref.isEmpty { return extras.contains { $0.ref == entry.ref } }
        let label = Extras.activity(entry.activity).label
        return extras.contains { $0.date == entry.date && normalise($0.label) == normalise(label) && $0.minutes == entry.minutes }
    }

    public mutating func apply(extra x: ExtraEntry, now: Date = Date()) throws -> Applied {
        let label = Extras.activity(x.activity).label

        if let target = x.editing {
            guard let i = extraIndex(target) else { throw BookError.noExtra(label) }
            let changed = Set(target.fields)
            if changed.isEmpty { return .dropped }
            let r = extras[i]
            func pick<T>(_ field: String, _ new: T, _ old: T) -> T { changed.contains(field) ? new : old }
            let activityChanged = changed.contains(ExtraField.activity)
            let record = ExtraRecord(
                row: r.row,
                date: pick(ExtraField.date, x.date, r.date),
                activity: activityChanged ? PlanBook.activityID(forLabel: label) : r.activity,
                label: activityChanged ? label : r.label,
                what: pick(ExtraField.what, x.what.trimmingCharacters(in: .whitespacesAndNewlines), r.what),
                minutes: pick(ExtraField.duration, PlanBook.finite(x.minutes), r.minutes),
                distance: pick(ExtraField.distance, PlanBook.text(x.distance), r.distance),
                avgHr: pick(ExtraField.avgHr, PlanBook.text(x.avgHr), r.avgHr),
                effort: pick(ExtraField.effort, PlanBook.text(x.effort), r.effort),
                isTraining: pick(ExtraField.isTraining, x.isTraining, r.isTraining),
                notes: pick(ExtraField.notes, x.notes.trimmingCharacters(in: .whitespacesAndNewlines), r.notes),
                ref: r.ref.isEmpty && !x.ref.isEmpty ? x.ref : r.ref)
            extras[i] = record
            extras = PlanBook.inOrder(extras)
            stamps["extra:" + record.id] = now
            return .written
        }

        // Adding is not the same twice over: a replay must not leave two of it.
        if alreadyRecorded(x) { return .written }
        let row = (extras.map(\.row).max() ?? 1) + 1
        let record = ExtraRecord(
            row: row, date: x.date, activity: PlanBook.activityID(forLabel: label), label: label,
            what: x.what.trimmingCharacters(in: .whitespacesAndNewlines), minutes: PlanBook.finite(x.minutes),
            distance: PlanBook.text(x.distance), avgHr: PlanBook.text(x.avgHr), effort: PlanBook.text(x.effort),
            isTraining: x.isTraining, notes: x.notes.trimmingCharacters(in: .whitespacesAndNewlines), ref: x.ref)
        extras.append(record)
        extras = PlanBook.inOrder(extras)
        stamps["extra:" + record.id] = now
        return .written
    }

    /* The sheet kept an activity as its label and found the id again from it; so does this. */
    static func activityID(forLabel label: String) -> String {
        Extras.defaultActivities.first { normalise($0.label) == normalise(label) }?.id ?? "other"
    }

    // MARK: changing the plan itself

    public func draft(of key: String) -> SessionDraft? {
        guard let w = session(key) else { return nil }
        return SessionDraft(
            dayKey: w.dayKey, sport: w.discipline.id, title: w.title,
            minutes: Plan.plannedSeconds(w, mapping).map { ($0 / 60 * 100).rounded() / 100 },
            intensity: w.planned.intensity, purpose: w.planned.description, isKey: w.isKey)
    }

    static func rawSport(_ id: String, keeping w: Workout?) -> String {
        if let w, w.discipline.id == id { return w.disciplineRaw }
        switch id {
        case "brick": return "Bike + Run"
        case "race": return "RACE"
        case "rest": return "Rest"
        case "other": return "Other"
        default: return (Disciplines.five.first { $0.id == id }?.label) ?? id.capitalized
        }
    }

    private var mainLabel: String {
        sessions.lazy.compactMap { w -> String? in
            guard w.sections.count == 1, w.sections[0].kind == "main", !w.planned.description.isEmpty else { return nil }
            return w.sections[0].label
        }.first ?? "Session"
    }

    /* A session with the draft laid into it. The day is not touched here. */
    private func shaped(_ w: Workout, by d: SessionDraft) -> Workout {
        var w = w
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        w.disciplineRaw = PlanBook.rawSport(d.sport, keeping: w)
        w.discipline = Disciplines.classify(w.disciplineRaw)
        if !title.isEmpty { w.title = title }
        // A length is a number of minutes that is not negative; anything else is no length.
        w.planned.durationRaw = d.minutes.flatMap { $0.isFinite && $0 >= 0 ? durationToCell($0 * 60, mapping.units.duration) : nil }
        w.planned.intensity = d.intensity.trimmingCharacters(in: .whitespacesAndNewlines)
        w.planned.description = d.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        // One plain block of words under the heading, as a simple plan has it.
        // A plan with warm-up and cool-down columns keeps its own blocks.
        if w.sections.count <= 1 && (w.sections.first?.kind ?? "main") == "main" {
            let words = w.planned.description.isEmpty ? w.title : w.planned.description
            let label = w.sections.first?.label ?? mainLabel
            w.sections = words.isEmpty ? [] : [Section(kind: "main", label: label, text: words)]
        }
        w.setKey(d.isKey)
        return w
    }

    static func day(_ key: String) -> String {
        guard let date = parseDayKey(key) else { return key }
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    static func minutesText(_ m: Double?) -> String {
        guard let m, m > 0 else { return "no length" }
        return jsNumberString((m * 10).rounded() / 10) + " min"
    }

    /* Only what differs, in plain words: "60 min → 40 min". */
    static func difference(_ a: SessionDraft, _ b: SessionDraft) -> (before: String, after: String) {
        var before: [String] = [], after: [String] = []
        func note(_ x: String, _ y: String) { before.append(x.isEmpty ? "nothing" : x); after.append(y.isEmpty ? "nothing" : y) }
        if a.dayKey != b.dayKey { note(day(a.dayKey), day(b.dayKey)) }
        if a.sport != b.sport { note(rawSport(a.sport, keeping: nil), rawSport(b.sport, keeping: nil)) }
        if a.minutes != b.minutes { note(minutesText(a.minutes), minutesText(b.minutes)) }
        if a.intensity != b.intensity { note(a.intensity, b.intensity) }
        if a.title != b.title { note(a.title, b.title) }
        if a.purpose != b.purpose { note(a.purpose, b.purpose) }
        if a.isKey != b.isKey { note(a.isKey ? "key session" : "ordinary session", b.isKey ? "key session" : "ordinary session") }
        return (before.joined(separator: " · "), after.joined(separator: " · "))
    }

    static func summary(_ d: SessionDraft) -> String {
        [rawSport(d.sport, keeping: nil), minutesText(d.minutes), d.intensity, day(d.dayKey)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private mutating func record(_ change: PlanChange) {
        changes.append(change)
        // The list is kept short, but a removal is never dropped from it: it
        // is the only place a taken-out session — and what was logged on it — still lives.
        var over = changes.count - 400
        if over > 0 {
            changes = changes.filter { c in
                if over > 0 && c.kind != "remove" && c.id != change.id { over -= 1; return false }
                return true
            }
        }
    }

    /* Change a planned session. Returns nil when the draft says what the plan already says. */
    @discardableResult
    public mutating func change(_ key: String, to draft: SessionDraft, why: String = "", now: Date = Date()) throws -> PlanChange? {
        guard let i = sessions.firstIndex(where: { $0.key == key }), let was = self.draft(of: key) else {
            throw BookError.noSession(key)
        }
        var d = draft
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.title.isEmpty { d.title = was.title }
        d.intensity = d.intensity.trimmingCharacters(in: .whitespacesAndNewlines)
        d.purpose = d.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = parseDayKey(d.dayKey), let day = dayKey(date) else { throw BookError.badDay(d.dayKey) }
        d.dayKey = day
        if d == was { return nil }

        let old = sessions[i]
        var w = shaped(old, by: d)
        if d.dayKey != old.dayKey { w = w.on(date, d.dayKey) }
        sessions[i] = w
        sessions = PlanBook.inOrder(sessions)
        stamps[key] = now
        let diff = PlanBook.difference(was, d)
        let change = PlanChange(at: now, kind: "edit", key: key, title: old.title,
                                before: diff.before, after: diff.after, why: why, undo: old, afterDay: d.dayKey)
        record(change)
        return change
    }

    /* A new session, made in the app. */
    @discardableResult
    public mutating func add(_ draft: SessionDraft, why: String = "", now: Date = Date()) throws -> Workout {
        guard let date = parseDayKey(draft.dayKey), let day = dayKey(date) else { throw BookError.badDay(draft.dayKey) }
        var draft = draft
        draft.dayKey = day
        counter += 1
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let tail = String((0..<6).map { _ in alphabet[Int.random(in: 0..<36)] })
        let row = 100_000 + counter
        let key = PlanBook.appSheet + "!" + String(counter) + tail
        let label = PlanBook.rawSport(draft.sport, keeping: nil)
        let blank = Workout(
            key: key, sheet: PlanBook.appSheet, row: row, rows: [row], date: date, dayKey: draft.dayKey,
            disciplineRaw: label, discipline: Disciplines.classify(label),
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? label : draft.title,
            phase: phase(on: draft.dayKey), sections: [],
            planned: Planned(durationRaw: nil, distanceRaw: nil, intensity: "", description: ""),
            results: [:], loggedInSheet: false, missed: false)
        let w = shaped(blank, by: draft)
        sessions.append(w)
        sessions = PlanBook.inOrder(sessions)
        stamps[key] = now
        removed[key] = nil
        record(PlanChange(at: now, kind: "add", key: key, title: w.title, before: "",
                          after: PlanBook.summary(self.draft(of: key) ?? draft), why: why, undo: nil))
        return w
    }

    /* Take a session out of the plan. It is kept in the list of changes, so it can come back. */
    @discardableResult
    public mutating func remove(_ key: String, why: String = "", now: Date = Date()) throws -> PlanChange {
        guard let i = sessions.firstIndex(where: { $0.key == key }), let was = draft(of: key) else {
            throw BookError.noSession(key)
        }
        let old = sessions.remove(at: i)
        let logAt = old.results.isEmpty ? nil : (stamps["log:" + key] ?? stamps[key])
        removed[key] = now
        stamps[key] = now
        let change = PlanChange(at: now, kind: "remove", key: key, title: old.title,
                                before: PlanBook.summary(was), after: "", why: why, undo: old, logAt: logAt)
        record(change)
        return change
    }

    /* Only the newest change to a session can be undone: undoing an older one would quietly take the later ones with it. */
    public func canUndo(_ changeID: String) -> Bool {
        guard let c = changes.firstIndex(where: { $0.id == changeID }), !changes[c].undone else { return false }
        let key = changes[c].key
        return !changes[(c + 1)...].contains { $0.key == key && !$0.undone }
    }

    /*
     * Undo one change: an edited session reads as before, a removed one
     * returns, an added one goes. What was logged is never lost by it — an
     * added session that has been logged since is taken out the way any
     * session is, so it stays in the list and can come back.
     */
    public mutating func undo(_ changeID: String, now: Date = Date()) throws {
        guard let c = changes.firstIndex(where: { $0.id == changeID }), !changes[c].undone else {
            throw BookError.nothingToUndo
        }
        guard canUndo(changeID) else { throw BookError.newerChange }
        let change = changes[c]
        switch change.kind {
        case "add":
            // Anything at all logged on it (not only a finished session): taken out the way any session is, kept in the list.
            if let made = session(change.key), !made.results.isEmpty {
                changes[c].undone = true
                try remove(change.key, why: "Undo of adding it", now: now)
                return
            }
            sessions.removeAll { $0.key == change.key }
            removed[change.key] = now
        default:
            guard var old = change.undo else { throw BookError.nothingToUndo }
            old.missed = old.results["done"].map { normalise($0.text) == normalise(mapping.missedValue) } ?? false
            old.loggedInSheet = Plan.isLogged(old.results)
            old.logged = old.loggedInSheet
            if let i = sessions.firstIndex(where: { $0.key == change.key }) {
                let current = sessions[i]
                // What was logged since stays; only the plan's side goes back.
                old.results = current.results
                old.loggedInSheet = current.loggedInSheet
                old.logged = current.logged
                old.missed = current.missed
                // Moved again since the change: it stays on the day he put it.
                if let after = change.afterDay, current.dayKey != after { old = old.on(current.date, current.dayKey) }
                sessions[i] = old
                // A move this change wrote into the move log goes with it.
                if let m = moves[change.key], m.at == change.at {
                    moves[change.key] = m.from == old.dayKey ? nil
                        : MoveRecord(from: m.from, to: old.dayKey, disciplineId: m.disciplineId, at: now)
                }
            } else {
                sessions.append(old)
                // Its log comes back with the mark it had, never "now": a log made since on another device stays newer.
                if !old.results.isEmpty, let t = change.logAt { stamps["log:" + change.key] = t }
            }
            removed[change.key] = nil
        }
        sessions = PlanBook.inOrder(sessions)
        stamps[change.key] = now
        changes[c].undone = true
    }

    // MARK: tests and zones

    /*
     * A test's numbers, entered in the app. The test takes the place of the
     * one with its name, or joins the end; the zones are then worked out
     * afresh from the last numbers there are — a zone changes from a test and
     * from nothing else.
     */
    public mutating func record(_ test: TestResult, now: Date = Date()) {
        if let i = tests.firstIndex(where: { $0.name == test.name }) { tests[i] = test } else { tests.append(test) }
        zones = zones?.recalculated(from: tests)
        stamps["tests"] = now
    }

    // MARK: weeks and phases

    public func week(on dayKey: String) -> PlanWeek? {
        let monday = PlanView.weekStart(dayKey)
        return weeks.first { $0.monday == monday }
    }

    /* The phase a day belongs to: its week's, else the nearest session's. */
    public func phase(on dayKey: String) -> String {
        if let week = week(on: dayKey), !week.phase.isEmpty { return week.phase }
        let before = sessions.last { $0.dayKey <= dayKey && !$0.phase.isEmpty }
        return before?.phase ?? sessions.first { !$0.phase.isEmpty }?.phase ?? ""
    }
}

// MARK: - a session, as the book keeps it

extension Workout {
    /* The same session on another day. */
    func on(_ date: Date, _ key: String) -> Workout {
        Workout(key: self.key, sheet: sheet, row: row, rows: rows, date: date, dayKey: key,
                disciplineRaw: disciplineRaw, discipline: discipline, title: title, phase: phase,
                sections: sections, planned: planned, results: results, loggedInSheet: loggedInSheet,
                missed: missed, logged: logged, pending: pending, pendingMove: pendingMove, source: source)
    }

    /* The plan week this session was written for, whatever day it has been moved to since. */
    public var planWeek: Int? { source?["Week"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }

    /* A key session: the plan's own star. */
    public var isKey: Bool { !(source?["Key"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    mutating func setKey(_ on: Bool) {
        if on == isKey { return }
        var s = source ?? [:]
        s["Key"] = on ? "\u{2605}" : ""
        source = s
    }

    /* Made in the app rather than taken in from the workbook. */
    public var madeInApp: Bool { sheet == PlanBook.appSheet }
}

extension Workout: Codable {
    enum CodingKeys: String, CodingKey {
        case key, sheet, row, rows, dayKey, disciplineRaw, title, phase, sections, planned, results, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(String.self, forKey: .key)
        let dayKey = try c.decode(String.self, forKey: .dayKey)
        guard let date = parseDayKey(dayKey) else {
            throw DecodingError.dataCorruptedError(forKey: .dayKey, in: c, debugDescription: "not a day: \(dayKey)")
        }
        let raw = try c.decodeIfPresent(String.self, forKey: .disciplineRaw) ?? ""
        // Absent is an older book; present and unreadable is damage, and throws.
        let results = try c.decodeIfPresent([String: ResultValue].self, forKey: .results) ?? [:]
        let row = try c.decodeIfPresent(Int.self, forKey: .row) ?? 0
        self.init(
            key: key, sheet: try c.decodeIfPresent(String.self, forKey: .sheet) ?? "", row: row,
            rows: try c.decodeIfPresent([Int].self, forKey: .rows) ?? [row], date: date, dayKey: dayKey,
            disciplineRaw: raw, discipline: Disciplines.classify(raw),
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            phase: try c.decodeIfPresent(String.self, forKey: .phase) ?? "",
            sections: try c.decodeIfPresent([Section].self, forKey: .sections) ?? [],
            planned: try c.decodeIfPresent(Planned.self, forKey: .planned)
                ?? Planned(durationRaw: nil, distanceRaw: nil, intensity: "", description: ""),
            results: results, loggedInSheet: Plan.isLogged(results), missed: false)
        logged = loggedInSheet
        source = try c.decodeIfPresent([String: String].self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(sheet, forKey: .sheet)
        try c.encode(row, forKey: .row)
        try c.encode(rows, forKey: .rows)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(disciplineRaw, forKey: .disciplineRaw)
        try c.encode(title, forKey: .title)
        try c.encode(phase, forKey: .phase)
        try c.encode(sections, forKey: .sections)
        try c.encode(planned, forKey: .planned)
        try c.encode(results, forKey: .results)
        try c.encodeIfPresent(source, forKey: .source)
    }
}
