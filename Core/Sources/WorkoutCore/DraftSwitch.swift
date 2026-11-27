import Foundation

/*
 * "Switch to this plan" (round 30, pick 1): the draft becomes his plan from
 * a Monday he picks — in one save, with one Undo.
 *
 *   The day ...... a Monday after today and after every session that must
 *                  stay: anything logged, missed or waiting, any test, race
 *                  or race rehearsal. So nothing done, past, tested or raced
 *                  is ever touched.
 *   Taken out .... his plan's sessions from that day on (none of them done:
 *                  the day guarantees it), each as an ordinary removal that
 *                  the Undo brings back.
 *   Added ........ the draft's sessions from that day on, each with a fixed
 *                  name ("App!np<batch>-<n>"), so the whole switch is found
 *                  again by its names and is never added twice.
 *   Weeks ........ the draft's weeks from that day on join the plan's weeks
 *                  (phase and heading), so every view shows the new blocks,
 *                  easy weeks and test weeks as it shows his own.
 *   Changes ...... one line in Changes to the plan for the whole switch (the
 *                  removals keep their own lines, as removals always do);
 *                  hundreds of "added" lines would push his earlier changes
 *                  out of the list.
 */
public struct SwitchRecord: Codable, Equatable {
    public var batch: String
    public var from: String
    public var at: Date
    public var raceName: String
    public var added: Int
    public var removed: Int
    public var addedMondays: [String]
    public var replacedWeeks: [PlanWeek]

    public init(batch: String, from: String, at: Date, raceName: String, added: Int, removed: Int,
                addedMondays: [String], replacedWeeks: [PlanWeek]) {
        self.batch = batch; self.from = from; self.at = at; self.raceName = raceName; self.added = added
        self.removed = removed; self.addedMondays = addedMondays; self.replacedWeeks = replacedWeeks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batch = try c.decode(String.self, forKey: .batch)
        from = (try? c.decodeIfPresent(String.self, forKey: .from)).flatMap { $0 } ?? ""
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)).flatMap { $0 } ?? Date(timeIntervalSince1970: 0)
        raceName = (try? c.decodeIfPresent(String.self, forKey: .raceName)).flatMap { $0 } ?? ""
        added = (try? c.decodeIfPresent(Int.self, forKey: .added)).flatMap { $0 } ?? 0
        removed = (try? c.decodeIfPresent(Int.self, forKey: .removed)).flatMap { $0 } ?? 0
        addedMondays = (try? c.decodeIfPresent([String].self, forKey: .addedMondays)).flatMap { $0 } ?? []
        replacedWeeks = (try? c.decodeIfPresent([PlanWeek].self, forKey: .replacedWeeks)).flatMap { $0 } ?? []
    }

    enum CodingKeys: String, CodingKey { case batch, from, at, raceName, added, removed, addedMondays, replacedWeeks }
}

public enum DraftSwitchError: Error, LocalizedError, Equatable {
    case notAMonday
    case tooEarly(String)
    case nothingToAdd
    case alreadyIn
    case newerSwitch

    public var errorDescription: String? {
        switch self {
        case .notAMonday: return "The new plan starts on a Monday. Nothing was changed."
        case .tooEarly(let day): return "Your plan has sessions that must stay until then: the new plan can start from \(day). Nothing was changed."
        case .nothingToAdd: return "The draft has no sessions from that day on. Nothing was changed."
        case .alreadyIn: return "This draft is already your plan from that day. Nothing was changed."
        case .newerSwitch: return "A newer switch is still in your plan: undo that one first. Nothing was changed."
        }
    }
}

public enum DraftSwitch {
    public static let whyStart = "New plan: "
    public static let summaryKind = "newplan"

    public static func why(race: String, batch: String) -> String { whyStart + race + " #" + batch }
    public static func isOurs(_ why: String) -> Bool { why.hasPrefix(whyStart) && why.contains(" #") }
    public static func batch(of why: String) -> String? {
        guard isOurs(why), let r = why.range(of: " #", options: .backwards) else { return nil }
        return String(why[r.upperBound...])
    }
    /* The reason line as he reads it. */
    public static func shownWhy(_ why: String) -> String {
        guard isOurs(why), let r = why.range(of: " #", options: .backwards) else { return why }
        return String(why[..<r.lowerBound])
    }
    public static func newBatch() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    /*
     * Round 30 safety: the same draft switched from the same Monday gets the same mark on every
     * device, so a switch tapped on two devices before they meet is one set of sessions when the
     * plans join (the same fixed names), never two. Another draft or another Monday: another mark.
     */
    public static func batch(for draft: [MadeWeek], from: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        func eat(_ s: String) {
            for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
            h ^= 0x1f; h = h &* 0x100000001b3
        }
        eat(from)
        for m in draft.flatMap(\.sessions) where m.day >= from {
            eat(m.day); eat(m.sport); eat(m.title); eat(String(m.minutes)); eat(m.zone); eat(m.purpose); eat(m.key ? "1" : "0")
        }
        let hex = String(h, radix: 16)
        return String((String(repeating: "0", count: max(0, 16 - hex.count)) + hex).prefix(10))
    }
    public static func keyPrefix(_ batch: String) -> String { PlanBook.appSheet + "!np" + batch + "-" }
    public static func summaryKey(_ batch: String) -> String { "planmaker:" + batch }

    /* A session that must stay where it is: logged, missed or waiting, a test, a race or a race rehearsal. */
    public static func mustStay(_ s: Workout) -> Bool { LayOut.isProtected(s) }

    /* The first Monday the new plan may start on: after today and after every session that must stay. */
    public static func firstAllowed(sessions: [Workout], today: String) -> String {
        let last = sessions.filter(mustStay).map(\.dayKey).max() ?? today
        return PlanMaker.monday(onOrAfter: PlanView.addDays(max(last, today), 1))
    }

    /* The Mondays he may pick: from the first allowed (and not before the draft) to the draft's race week. */
    public static func days(draft: [MadeWeek], sessions: [Workout], today: String) -> [String] {
        guard let first = draft.first?.monday else { return [] }
        let last = draft.last(where: { $0.block == .raceWeek })?.monday ?? draft.last?.monday ?? first
        var day = max(first, firstAllowed(sessions: sessions, today: today))
        var out: [String] = []
        while day <= last {
            out.append(day)
            day = PlanView.addDays(day, 7)
        }
        return out
    }

    /* Counted the way every screen counts sessions: a rest day is not a session (its row goes and comes all the same). */
    public struct Preview: Equatable, Sendable {
        public let from: String
        /* The draft's sessions added. */
        public let added: Int
        /* The draft's sessions before that day, left out. */
        public let leftOut: Int
        /* His plan's sessions from that day on, taken out. */
        public let takenOut: Int
    }

    public static func preview(sessions: [Workout], draft: [MadeWeek], from: String) -> Preview {
        let all = draft.flatMap(\.training)
        return Preview(from: from, added: all.filter { $0.day >= from }.count, leftOut: all.filter { $0.day < from }.count,
                       takenOut: sessions.filter { $0.dayKey >= from && $0.discipline.id != "rest" }.count)
    }

    /* The plan week number of a Monday, counted the way the plan counts its weeks (week 1's Monday on). */
    static func number(of monday: String, weeks: [PlanWeek], fallback: Int) -> Int {
        let start = weeks.first { $0.number == 1 }?.monday
            ?? weeks.min { $0.monday < $1.monday }.map { PlanView.addDays($0.monday, -7 * ($0.number - 1)) }
        guard let start else { return fallback }
        return RuleBook.daysBetween(PlanView.weekStart(start), monday) / 7 + 1
    }

    /*
     * The switch, written into the book: all of it or none. Returns what the
     * Undo needs to put the weeks back (kept on the shelf by the caller).
     */
    public static func apply(draft: [MadeWeek], from: String, raceName: String, to book: inout PlanBook,
                             today: String, batch: String? = nil, now: Date = Date()) throws -> SwitchRecord {
        guard PlanView.weekStart(from) == from else { throw DraftSwitchError.notAMonday }
        let allowed = firstAllowed(sessions: book.sessions, today: today)
        guard from >= allowed else { throw DraftSwitchError.tooEarly(allowed) }
        let batch = batch ?? DraftSwitch.batch(for: draft, from: from)
        // Already standing (tapped twice, or switched on another device and met here): never a second time.
        guard !book.changes.contains(where: { $0.kind == summaryKind && $0.key == summaryKey(batch) && !$0.undone }) else {
            throw DraftSwitchError.alreadyIn
        }
        let adding = draft.flatMap(\.sessions).filter { $0.day >= from }
        guard !adding.isEmpty else { throw DraftSwitchError.nothingToAdd }

        var copy = book
        let before = copy.changes
        let reason = DraftSwitch.why(race: raceName, batch: batch)

        // 1. His plan's sessions from that day on (none must stay: the day says so).
        let going = copy.sessions.filter { $0.dayKey >= from }.map(\.key)
        for key in going { try copy.remove(key, why: reason, now: now) }

        // 2. The weeks: the draft's phase and heading from that day on.
        var replaced: [PlanWeek] = []
        var added: [String] = []
        for w in draft where w.monday >= from {
            if let i = copy.weeks.firstIndex(where: { PlanView.weekStart($0.monday) == w.monday }) {
                replaced.append(copy.weeks[i])
                copy.weeks[i] = PlanWeek(number: copy.weeks[i].number, monday: copy.weeks[i].monday, phase: w.phase, tag: w.tag)
            } else {
                let n = number(of: w.monday, weeks: copy.weeks, fallback: w.number)
                copy.weeks.append(PlanWeek(number: n, monday: w.monday, phase: w.phase, tag: w.tag))
                added.append(w.monday)
            }
        }
        copy.weeks.sort { $0.monday < $1.monday }

        // 3. The draft's sessions, each with its fixed name (the weeks are in, so each takes its week's phase).
        let prefix = keyPrefix(batch)
        for (n, m) in adding.enumerated() {
            try copy.add(m.draft, why: reason, fixedKey: prefix + String(n + 1), now: now)
        }

        // 4. One line for the whole switch; the removals keep theirs. Counted as every screen counts: rest days are not sessions.
        let removals = copy.changes.filter { $0.why == reason && $0.kind == "remove" }
        let addedCount = adding.filter { $0.sport != "rest" }.count
        let goneCount = book.sessions.filter { $0.dayKey >= from && $0.discipline.id != "rest" }.count
        let summary = PlanChange(at: now, kind: summaryKind, key: summaryKey(batch), title: whyStart + raceName,
                                 before: goneCount == 0 ? "" : "\(goneCount) sessions from \(PlanBook.day(from)) taken out",
                                 after: "\(addedCount) sessions from \(PlanBook.day(from))",
                                 why: reason, undo: nil, afterDay: from)
        copy.changes = before + removals + [summary]
        book = copy
        return SwitchRecord(batch: batch, from: from, at: now, raceName: raceName, added: addedCount,
                            removed: goneCount, addedMondays: added, replacedWeeks: replaced)
    }

    /* The newest switch still standing, if any. */
    public static func latest(in book: PlanBook) -> PlanChange? {
        book.changes.last { $0.kind == summaryKind && !$0.undone }
    }

    /* Sessions of a switch logged since: the Undo leaves them in the plan. */
    public static func loggedSince(batch: String, in book: PlanBook) -> Int {
        let prefix = keyPrefix(batch)
        return book.sessions.filter { $0.key.hasPrefix(prefix) && MobilityStrength.untouchable($0) }.count
    }

    /*
     * One Undo for the whole switch, all or none: the sessions it added go
     * (those logged since stay), the sessions it took out come back, the
     * weeks go back to how they were. Returns how many sessions changed.
     */
    @discardableResult
    public static func undo(batch: String, record: SwitchRecord?, in book: inout PlanBook, now: Date = Date()) throws -> Int {
        var copy = book
        guard let line = copy.changes.last(where: { $0.kind == summaryKind && $0.key == summaryKey(batch) && !$0.undone }) else {
            throw BookError.nothingToUndo
        }
        // Only the newest switch still standing: an older one would bring its sessions back under the newer plan.
        if let newest = latest(in: copy), newest.key != line.key { throw DraftSwitchError.newerSwitch }
        let from = record?.batch == batch ? record!.from : (line.afterDay ?? "")
        var n = 0

        // 1. What the switch added goes, as an undone addition goes; a session logged since stays.
        let prefix = keyPrefix(batch)
        for key in copy.sessions.filter({ $0.key.hasPrefix(prefix) && !MobilityStrength.untouchable($0) }).map(\.key) {
            copy.sessions.removeAll { $0.key == key }
            copy.removed[key] = now
            copy.stamps[key] = now
            n += 1
        }

        // 2. What it took out comes back.
        for c in copy.changes.filter({ $0.why == line.why && $0.kind == "remove" && !$0.undone }).reversed() where copy.canUndo(c.id) {
            try copy.undo(c.id, now: now)
            n += 1
        }

        // 3. The weeks: the ones it replaced come back, the ones it added go (unless a session still stands in them).
        let busy = Set(copy.sessions.map { PlanView.weekStart($0.dayKey) })
        if let record, record.batch == batch {
            for w in record.replacedWeeks {
                if let i = copy.weeks.firstIndex(where: { $0.monday == w.monday }) { copy.weeks[i] = w }
            }
            let added = Set(record.addedMondays)
            copy.weeks.removeAll { added.contains($0.monday) && !busy.contains($0.monday) }
        } else if !from.isEmpty {
            copy.weeks.removeAll { $0.monday >= from && !busy.contains($0.monday) }
        }

        // 4. The line says it is undone — every line of this switch (one per device that made it).
        for i in copy.changes.indices where copy.changes[i].kind == summaryKind && copy.changes[i].key == line.key {
            copy.changes[i].undone = true
        }
        book = copy
        return n
    }
}

/* The changes of one batch made by this lane's rules, for the one entry in Changes to the plan. */
public enum PlanMakerBatch {
    /* "switch:<batch>" for a new plan, "layout:<batch>" for a lay-out to the week shape; nil for anything else. */
    public static func of(_ why: String) -> String? {
        if let b = DraftSwitch.batch(of: why) { return "switch:" + b }
        if let b = LayOut.batch(of: why) { return "layout:" + b }
        return nil
    }
}
