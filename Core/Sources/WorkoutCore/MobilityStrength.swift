import Foundation

/*
 * Mobility and strength days (2.14): mobility every Monday, Wednesday and
 * Friday, strength every Tuesday and Thursday — 30 minutes each, from a start
 * day (tomorrow) to race week.
 *
 *   Mobility .... added on Mon, Wed, Fri, race week included, nothing after it.
 *   Strength .... the plan's own strength sessions of a week move to Tuesday
 *                 and Thursday (the earliest first), keeping their exercises,
 *                 set to 30 min. A week where the plan has only one gets a
 *                 second on Thursday: a copy of the plan's last earlier second
 *                 session of a week, or of the week's own when that is a light
 *                 one. A week without strength in the plan (race week, after
 *                 the race) gets none.
 *
 * Never touched: a day before the start, a session logged, marked missed or
 * waiting for a log, a session this rule moved before and he put back
 * himself. Never made twice: each added session has one fixed name per day
 * on every device ("App!mob-<day>", "App!str-<day>"), and a name this rule
 * added once is not offered again (only an Undo frees it).
 *
 * `plan` only says what would change, so a page can show it first; `apply`
 * writes it into a book; `undo` takes the whole lot back in one go.
 */
public enum MobilityStrength {
    /* The reason line of every change this rule makes; " #<batch>" after it keeps one round apart from the next. */
    public static let why = "Mobility and strength days"
    public static let minutes: Double = 30
    public static let mobilityTitle = "Mobility: hips, hamstrings, calves, upper back"
    public static let mobilityPurpose = "Keeps you supple and helps you recover"
    public static let mobilityIntensity = "Easy"
    /* Words a moved session no longer fits: it is not the week's only one any more. */
    static let singleWords = "(single weekly session)"

    /* Days after Monday. */
    static let mobilityOffsets = [0, 2, 4]
    static let strengthOffsets = [1, 3]

    public static func mobilityKey(_ day: String) -> String { PlanBook.appSheet + "!mob-" + day }
    public static func strengthKey(_ day: String) -> String { PlanBook.appSheet + "!str-" + day }

    public static func why(batch: String = String(UUID().uuidString.prefix(8))) -> String { why + " #" + batch }
    public static func isOurs(_ why: String) -> Bool { why == Self.why || why.hasPrefix(Self.why + " #") }
    public static func batch(of why: String) -> String? {
        guard isOurs(why) else { return nil }
        guard let r = why.range(of: " #", options: .backwards) else { return "" }
        return String(why[r.upperBound...])
    }

    public struct Move: Equatable {
        public let key: String
        public let from: String
        public let draft: SessionDraft
    }

    public struct Add: Equatable {
        public let key: String
        public let draft: SessionDraft
    }

    /* One plan week as the page shows it. Days are day keys. */
    public struct Week: Equatable, Identifiable {
        public var id: Int { number }
        public let number: Int
        public let monday: String
        public var mobility: [String] = []
        public var moves: [(from: String, to: String)] = []
        public var strengthAdded: [String] = []
        public var before: Double = 0
        public var after: Double = 0

        public static func == (a: Week, b: Week) -> Bool {
            a.number == b.number && a.monday == b.monday && a.mobility == b.mobility
                && a.moves.map(\.from) == b.moves.map(\.from) && a.moves.map(\.to) == b.moves.map(\.to)
                && a.strengthAdded == b.strengthAdded && a.before == b.before && a.after == b.after
        }
    }

    public struct Change: Equatable {
        public var moves: [Move] = []
        public var adds: [Add] = []
        public var weeks: [Week] = []
        public init() {}
        public var isEmpty: Bool { moves.isEmpty && adds.isEmpty }
        public var mobilityCount: Int { adds.filter { $0.draft.sport == "mobility" }.count }
        public var strengthAdded: Int { adds.filter { $0.draft.sport == "strength" }.count }
    }

    /* What one tap wrote: how many of each. */
    public struct Done: Equatable {
        public let mobility: Int
        public let moved: Int
        public let strength: Int
        public init(mobility: Int, moved: Int, strength: Int) {
            self.mobility = mobility; self.moved = moved; self.strength = strength
        }
    }

    static func isRaceWeek(_ w: PlanWeek) -> Bool { normalise(w.tag).contains("race week") }

    static func untouchable(_ s: Workout) -> Bool {
        !s.results.isEmpty || s.logged || s.missed || s.pending != nil || s.pendingMove != nil
    }

    /* The session as a draft on another day: 30 min, its own words, without "(single weekly session)". */
    static func strengthDraft(_ s: Workout, day: String, mapping: Mapping) -> SessionDraft {
        var title = s.title
        if let r = title.range(of: singleWords, options: .caseInsensitive) {
            title.removeSubrange(r)
            title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return SessionDraft(dayKey: day, sport: "strength", title: title, minutes: minutes,
                            intensity: s.planned.intensity, purpose: s.planned.description, isKey: s.isKey)
    }

    static func plannedMinutes(_ s: Workout, _ mapping: Mapping) -> Double {
        (Plan.plannedSeconds(s, mapping) ?? 0) / 60
    }

    public static func plan(weeks: [PlanWeek], sessions: [Workout], changes: [PlanChange], mapping: Mapping,
                            from start: String) -> Change {
        var out = Change()
        let ours = changes.filter { isOurs($0.why) && !$0.undone }
        let addedOnce = Set(ours.filter { $0.kind == "add" }.map(\.key))
        let movedOnce = Set(ours.filter { $0.kind == "edit" }.map(\.key))
        let keys = Set(sessions.map(\.key))
        let sorted = weeks.sorted { $0.monday < $1.monday }
        // Nothing after race week; a plan without one goes to its last week.
        let lastMonday = sorted.first(where: isRaceWeek).map { PlanView.weekStart($0.monday) }
            ?? sorted.last.map { PlanView.weekStart($0.monday) }
        guard let lastMonday else { return out }

        var lastSecond: Workout?   // the plan's last second strength session of a week, so far
        for w in sorted {
            let monday = PlanView.weekStart(w.monday)
            if monday > lastMonday { break }
            let days = (0..<7).map { PlanView.addDays(monday, $0) }
            let inWeek = sessions.filter { days.contains($0.dayKey) }
            let strength = inWeek.filter { $0.discipline.id == "strength" }.sorted { ($0.dayKey, $0.row) < ($1.dayKey, $1.row) }
            defer { if strength.count >= 2 { lastSecond = strength[1] } }
            if PlanView.addDays(monday, 6) < start { continue }

            var week = Week(number: w.number, monday: monday)
            week.before = inWeek.filter { $0.discipline.id != "rest" }.reduce(0) { $0 + plannedMinutes($1, mapping) }
            var added = 0.0

            for offset in mobilityOffsets {
                let day = PlanView.addDays(monday, offset)
                let key = mobilityKey(day)
                guard day >= start, !keys.contains(key), !addedOnce.contains(key) else { continue }
                if inWeek.contains(where: { $0.dayKey == day && $0.discipline.id == "mobility" }) { continue }
                out.adds.append(Add(key: key, draft: SessionDraft(dayKey: day, sport: "mobility", title: mobilityTitle,
                                                                  minutes: minutes, intensity: mobilityIntensity,
                                                                  purpose: mobilityPurpose)))
                week.mobility.append(day)
                added += minutes
            }

            if !strength.isEmpty && !isRaceWeek(w) {
                let targets = strengthOffsets.map { PlanView.addDays(monday, $0) }
                let onTarget = strength.filter { targets.contains($0.dayKey) }
                var movable = strength.filter {
                    !targets.contains($0.dayKey) && $0.dayKey >= start && !untouchable($0) && !movedOnce.contains($0.key)
                }
                let staying = strength.count - onTarget.count - movable.count
                let free = targets.filter { t in t >= start && !onTarget.contains { $0.dayKey == t } }
                let need = max(0, 2 - onTarget.count - staying)
                let light = (movable + onTarget).first { normalise($0.title).contains("light") }
                // One more beside a session that stays: the later day, so the two are apart.
                let chosen = staying > 0 ? Array(free.suffix(need)) : Array(free.prefix(need))
                for t in chosen {
                    if !movable.isEmpty {
                        let s = movable.removeFirst()
                        let d = strengthDraft(s, day: t, mapping: mapping)
                        out.moves.append(Move(key: s.key, from: s.dayKey, draft: d))
                        week.moves.append((from: s.dayKey, to: t))
                        added += minutes - plannedMinutes(s, mapping)
                    } else {
                        let key = strengthKey(t)
                        guard !keys.contains(key), !addedOnce.contains(key) else { continue }
                        guard let model = light ?? lastSecond ?? strength.first else { continue }
                        out.adds.append(Add(key: key, draft: strengthDraft(model, day: t, mapping: mapping)))
                        week.strengthAdded.append(t)
                        added += minutes
                    }
                }
            }

            guard !week.mobility.isEmpty || !week.moves.isEmpty || !week.strengthAdded.isEmpty else { continue }
            week.before = week.before.rounded()
            week.after = (week.before + added).rounded()
            out.weeks.append(week)
        }
        return out
    }

    /* Writes the change into the book, all of it or none. Returns the changes' ids. */
    @discardableResult
    public static func apply(_ c: Change, to book: inout PlanBook, why: String = MobilityStrength.why(),
                             now: Date = Date()) throws -> [String] {
        var copy = book
        var ids: [String] = []
        for m in c.moves {
            guard let was = copy.session(m.key) else { throw BookError.noSession(m.key) }
            if let change = try copy.change(m.key, to: m.draft, why: why, now: now) {
                ids.append(change.id)
                if m.draft.dayKey != was.dayKey {
                    let from = copy.moves[was.key]?.from ?? was.dayKey
                    copy.moves[was.key] = MoveRecord(from: from, to: m.draft.dayKey, disciplineId: was.discipline.id, at: now)
                }
            }
        }
        for a in c.adds {
            let before = copy.changes.count
            try copy.add(a.draft, why: why, fixedKey: a.key, now: now)
            if copy.changes.count > before, let id = copy.changes.last?.id { ids.append(id) }
        }
        book = copy
        return ids
    }

    /*
     * The changes one Undo of a round takes back: not undone yet, still the
     * newest change to their session, and nothing logged on it since.
     */
    public static func undoable(_ changes: [PlanChange], book: PlanBook) -> [PlanChange] {
        changes.filter { c in
            guard isOurs(c.why), !c.undone, book.canUndo(c.id) else { return false }
            guard let s = book.session(c.key) else { return c.kind != "add" }
            return !untouchable(s)
        }
    }

    /* Undo a whole round, newest first, all or none. Returns how many were taken back. */
    @discardableResult
    public static func undo(batch: String, in book: inout PlanBook, now: Date = Date()) throws -> Int {
        let list = undoable(book.changes.filter { MobilityStrength.batch(of: $0.why) == batch }, book: book)
        var copy = book
        for c in list.reversed() { try copy.undo(c.id, now: now) }
        book = copy
        return list.count
    }
}
