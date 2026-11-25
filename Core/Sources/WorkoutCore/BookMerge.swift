import Foundation

/*
 * Two copies of the plan, met in one.
 *
 * The iPhone, the iPad and the Mac each keep the plan as a PlanBook and each
 * may change it while the others are away. When they meet, this joins the
 * copies. What it must never do is lose something he logged, so every rule
 * here errs towards keeping:
 *
 *   - A session is two things with two marks: its plan side (the day, the
 *     sport, the words, the length) and its log side (what he recorded). Each
 *     side goes to the copy that changed it last, so a change of plan on one
 *     device and a log on another both survive.
 *   - Only a "removed" mark takes anything out, and a log made after the
 *     removal brings the session back.
 *   - A copy that is missing, empty or not yet downloaded is "nothing there
 *     yet", never "everything was removed" (join(…cloud: [])).
 *   - It is the same answer whichever copy is named first, and joining twice
 *     is joining once.
 *   - It refuses rather than guesses: a book from a newer app, or from a
 *     second independent import, is not merged.
 */

public enum BookMerge {
    public enum Refusal: Error, Equatable {
        /* A book from a newer app: write nothing anywhere. */
        case newerFormat(Int)
        /* Two independent imports (the plan they came from differs): he chooses. */
        case differentPlan(String, String)
    }

    /* Pure: the same either way round, the same twice over. Never removes a session or an extra without a removed mark. */
    public static func merged(_ a: PlanBook, _ b: PlanBook) throws -> PlanBook {
        try combine(a, b)
    }

    /* The iCloud file, its conflict copies and this device's own, joined in one go. At least one book. */
    public static func merged(_ books: [PlanBook]) throws -> PlanBook {
        precondition(!books.isEmpty, "nothing to merge")
        if let newer = books.map(\.format).max(), newer > PlanBook.currentFormat { throw Refusal.newerFormat(newer) }
        var out = books[0]
        if books.count == 1 { return try combine(out, out) }
        for book in books.dropFirst() { out = try combine(out, book) }
        return out
    }

    /*
     * One meeting with iCloud. `cloud` holds the iCloud file's book first (if the file is there) and then
     * every conflict copy. An empty `cloud` means "nothing there yet" — never "everything was deleted".
     */
    public static func join(local: PlanBook, cloud: [PlanBook], cloudFileThere: Bool) -> BookJoin {
        let newest = (cloud.map(\.format) + [local.format]).max() ?? local.format
        if newest > PlanBook.currentFormat {
            return BookJoin(book: local, changesLocal: false, changesCloud: false,
                            refused: .newerFormat(newest), takenAway: [])
        }
        let mine = (try? combine(local, local)) ?? local
        let joined: PlanBook
        do { joined = try merged([local] + cloud) } catch let refusal as Refusal {
            return BookJoin(book: local, changesLocal: false, changesCloud: false, refused: refusal, takenAway: [])
        } catch {
            return BookJoin(book: local, changesLocal: false, changesCloud: false, refused: nil, takenAway: [])
        }
        let theirs: PlanBook? = cloudFileThere ? cloud.first.flatMap { try? combine($0, $0) } : nil
        // Conflict copies that brought nothing new are only cleared, not written over: one that cannot be
        // removed then costs a look at each meeting, never a write.
        var out = BookJoin(book: joined,
                           changesLocal: !same(joined, mine),
                           changesCloud: theirs == nil || !same(joined, theirs!),
                           refused: nil,
                           takenAway: takenAway(from: local, to: joined))
        out.clearConflicts = cloud.count > (cloudFileThere ? 1 : 0)
        return out
    }

    /* Two books from the same move into the app (the same mapping, file and moment): only those are ever joined. */
    public static func samePlan(_ a: PlanBook, _ b: PlanBook) -> Bool {
        a.mapping.bytes == b.mapping.bytes && a.origin.fileName == b.origin.fileName && a.origin.takenAt == b.origin.takenAt
    }

    // MARK: - what a meeting takes away

    static func takenAway(from local: PlanBook, to joined: PlanBook) -> [String] {
        var out: [String] = []
        let after = Dictionary(joined.sessions.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        for w in local.sessions {
            guard let now = after[w.key] else { out.append(w.key); continue }
            if w.results.keys.contains(where: { now.results[$0] == nil }) { out.append("log:" + w.key) }
        }
        let ids = Set(joined.extras.map(\.id))
        for e in local.extras where !ids.contains(e.id) { out.append("extra:" + e.id) }
        return out.sorted()
    }

    private static func same(_ a: PlanBook, _ b: PlanBook) -> Bool {
        if let x = try? a.encoded(), let y = try? b.encoded() { return x == y }
        return a == b
    }

    // MARK: - the merge

    /* The same choice on every device: the later mark; the same mark with other words, the longer, then the larger. */
    static func aWins(_ ta: Date?, _ tb: Date?, _ ba: @autoclosure () -> Data, _ bb: @autoclosure () -> Data) -> Bool {
        let x = ta ?? .distantPast, y = tb ?? .distantPast
        if x != y { return x > y }
        let p = ba(), q = bb()
        if p.count != q.count { return p.count > q.count }
        return !p.lexicographicallyPrecedes(q) || p == q
    }

    private static func later(_ x: Date?, _ y: Date?) -> Date? {
        guard let x else { return y }
        guard let y else { return x }
        return max(x, y)
    }

    static func combine(_ a: PlanBook, _ b: PlanBook) throws -> PlanBook {
        // 1. Format.
        let newest = max(a.format, b.format)
        if newest > PlanBook.currentFormat { throw Refusal.newerFormat(newest) }

        // 2. The same plan? Two imports that were made apart are never auto-merged.
        if !samePlan(a, b) {
            let names = [a.origin.describe, b.origin.describe].sorted()
            throw Refusal.differentPlan(names[0], names[1])
        }

        // 3. Removed marks: the later time per key.
        var removed = a.removed
        for (k, t) in b.removed { removed[k] = max(removed[k] ?? t, t) }

        var changes = unionChanges(a.changes, b.changes)
        var stampsOut: [String: Date] = [:]

        // 4. Sessions.
        let ai = Dictionary(a.sessions.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        let bi = Dictionary(b.sessions.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        var sessions: [Workout] = []
        for key in Set(ai.keys).union(bi.keys) {
            let wa = ai[key], wb = bi[key]
            // A log stamp; a book with a log but no log stamp falls back to its plan stamp, one with no log has none.
            func logStamp(_ book: PlanBook, _ w: Workout) -> Date? {
                book.stamps["log:" + key] ?? (w.results.isEmpty ? nil : book.stamps[key])
            }
            var planStamp: Date?, logStampOut: Date?
            let chosen: Workout
            switch (wa, wb) {
            case let (x?, y?) where x == y:
                // The same session on both sides (the usual case): nothing to choose.
                chosen = x
                planStamp = later(a.stamps[key], b.stamps[key])
                logStampOut = later(logStamp(a, x), logStamp(b, y))
            case let (x?, y?):
                planStamp = later(a.stamps[key], b.stamps[key])
                logStampOut = later(logStamp(a, x), logStamp(b, y))
                let planA = aWins(a.stamps[key], b.stamps[key], x.planBytes, y.planBytes)
                let logA = aWins(logStamp(a, x), logStamp(b, y), x.logBytes, y.logBytes)
                let plan = planA ? x : y, log = logA ? x : y
                chosen = planA == logA ? plan : plan.withLog(of: log, a.mapping)
            case let (x?, nil):
                chosen = x; planStamp = a.stamps[key]; logStampOut = logStamp(a, x)
            case let (nil, y?):
                chosen = y; planStamp = b.stamps[key]; logStampOut = logStamp(b, y)
            default:
                continue
            }
            // Survival: a removal as late as the last thing done to it takes it out; a later log brings it back.
            // So does a log the removing device never saw: the session as it was taken out (the remove
            // line's undo) holds another log, or none — taking it out then would lose what he logged.
            let last = later(planStamp, logStampOut) ?? .distantPast
            if let r = removed[key] {
                let unseen = !chosen.results.isEmpty && neverSeen(chosen, logStampOut, key, in: changes)
                if r >= last && !unseen { continue }
                removed[key] = nil
                let after = r >= last ? "Came back: logged on another device before it was taken out"
                                      : "Came back: logged after it was taken out"
                if r < last ? (logStampOut.map { $0 > r } ?? false) : true {
                    // Already "taken back" so it never stands in the way of undoing an older change to the session.
                    var back = PlanChange(id: "back:\(key):\(PlanBook.ms(r))", at: max(logStampOut ?? r, r), kind: "back", key: key,
                                          title: chosen.title, before: "", after: after, why: "", undo: nil)
                    back.undone = true
                    changes = unionChanges(changes, [back])
                }
            }
            sessions.append(chosen)
            if let planStamp { stampsOut[key] = planStamp }
            if let logStampOut { stampsOut["log:" + key] = logStampOut }
        }
        // 5. Order: the same on every device.
        sessions.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.row != $1.row { return $0.row < $1.row }
            return $0.key < $1.key
        }

        // 6. Extras, by id.
        let ae = Dictionary(a.extras.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let be = Dictionary(b.extras.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        var extras: [ExtraRecord] = []
        for id in Set(ae.keys).union(be.keys) {
            let sk = "extra:" + id
            let chosen: ExtraRecord
            switch (ae[id], be[id]) {
            case let (x?, y?):
                chosen = x == y || aWins(a.stamps[sk], b.stamps[sk], PlanBook.bytes(x), PlanBook.bytes(y)) ? x : y
            case let (x?, nil): chosen = x
            case let (nil, y?): chosen = y
            default: continue
            }
            let stamp = later(ae[id] == nil ? nil : a.stamps[sk], be[id] == nil ? nil : b.stamps[sk])
            if let r = removed[sk] {
                if r >= (stamp ?? .distantPast) { continue }
                removed[sk] = nil
            }
            extras.append(chosen)
            if let stamp { stampsOut[sk] = stamp }
        }
        let boundary: Int
        switch (a.origin.extrasLastRow, b.origin.extrasLastRow) {
        case let (x?, y?): boundary = max(x, y)
        case let (x?, nil): boundary = x
        case let (nil, y?): boundary = y
        default: boundary = max(a.extrasBoundary, b.extrasBoundary)
        }
        extras = renumbered(extras, after: boundary)

        // 7. The change list: every line of both, once, in time order, the newest 400 (removals always).
        changes = capped(changes)

        // 8. Zones, weeks and the test results.
        let testsWinA = a.tests == b.tests || aWins(a.stamps["tests"], b.stamps["tests"], PlanBook.bytes(a.tests), PlanBook.bytes(b.tests))
        let (first, second) = testsWinA ? (a.tests, b.tests) : (b.tests, a.tests)
        let tests = first + second.filter { t in !first.contains { $0.name == t.name } }
        let zoneStampA = later(a.stamps["zones"], a.stamps["tests"]), zoneStampB = later(b.stamps["zones"], b.stamps["tests"])
        let zonesWinA = a.zones == b.zones || aWins(zoneStampA, zoneStampB, PlanBook.bytes(a.zones), PlanBook.bytes(b.zones))
        var zones = zonesWinA ? a.zones : b.zones
        // Test results of both sides count: zones follow the tests that are there now.
        if tests != (zonesWinA ? a.tests : b.tests) { zones = zones?.recalculated(from: tests) }
        let weeks = a.weeks == b.weeks || aWins(a.stamps["weeks"], b.stamps["weeks"], PlanBook.bytes(a.weeks), PlanBook.bytes(b.weeks)) ? a.weeks : b.weeks

        // 10. Moves: per session, the later one; the newest 600.
        var moves = a.moves
        for (k, m) in b.moves {
            if let have = moves[k] {
                if m == have { continue }
                if m.at != have.at ? m.at > have.at : !PlanBook.bytes(m).lexicographicallyPrecedes(PlanBook.bytes(have)) { moves[k] = m }
            } else { moves[k] = m }
        }
        if moves.count > 600 {
            let keep = moves.sorted { $0.value.at != $1.value.at ? $0.value.at > $1.value.at : $0.key < $1.key }.prefix(600)
            moves = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }

        // 11. Every other mark: the later of the two. Marks of sessions and extras that are gone live on in `removed`.
        let sessionKeys = Set(ai.keys).union(bi.keys).union(removed.keys.filter { !$0.hasPrefix("extra:") })
        for source in [a.stamps, b.stamps] {
            for (k, t) in source {
                if k.hasPrefix("extra:") || (k.hasPrefix("log:") && sessionKeys.contains(String(k.dropFirst(4)))) || sessionKeys.contains(k) { continue }
                stampsOut[k] = max(stampsOut[k] ?? t, t)
            }
        }

        var origin = a.origin
        if origin.sessions != b.origin.sessions { origin.sessions = max(a.origin.sessions, b.origin.sessions) }
        origin.extras = max(a.origin.extras, b.origin.extras)
        origin.extrasLastRow = boundary
        switch (a.origin.originalHash, b.origin.originalHash) {
        case let (x?, y?): origin.originalHash = max(x, y)
        case let (x?, nil): origin.originalHash = x
        case let (nil, y?): origin.originalHash = y
        default: break
        }

        var out = PlanBook(sessions: sessions, extras: extras, zones: zones, weeks: weeks, mapping: a.mapping, origin: origin)
        out.format = PlanBook.currentFormat
        out.tests = tests
        out.changes = changes
        out.stamps = stampsOut
        out.removed = removed
        out.counter = max(a.counter, b.counter)
        // The entries already written: both lists, oldest first (by when each was written, then A–Z, the
        // same on every device), never trimmed here — only `remember` trims, and it drops the oldest.
        var appliedAt = a.appliedAt
        for (id, t) in b.appliedAt { appliedAt[id] = max(appliedAt[id] ?? t, t) }
        let ids = Set(a.applied).union(b.applied)
        out.appliedAt = appliedAt.filter { ids.contains($0.key) }
        out.applied = ids.sorted {
            let x = appliedAt[$0] ?? .distantPast, y = appliedAt[$1] ?? .distantPast
            return x != y ? x < y : $0 < $1
        }
        out.moves = moves
        return out
    }

    // MARK: - pieces

    /*
     * A log the device that took the session out never saw: the newest remove line still standing holds
     * another log (or none), and — where the line knows when its log was made — this one is later.
     * No line at all (taken out by an undo or a safety copy): nothing says it was seen.
     */
    private static func neverSeen(_ w: Workout, _ logStamp: Date?, _ key: String, in changes: [PlanChange]) -> Bool {
        guard let line = changes.last(where: { $0.kind == "remove" && $0.key == key && !$0.undone }) else { return true }
        let seen = line.undo?.results ?? [:]
        if PlanBook.bytes(seen) == w.logBytes { return false }
        if seen.isEmpty { return true }
        guard let seenAt = line.logAt else { return true }
        return (logStamp ?? .distantPast) > seenAt
    }

    private static func unionChanges(_ a: [PlanChange], _ b: [PlanChange]) -> [PlanChange] {
        // Kept by position, not copied into a dictionary: the lists are long and each line holds a session.
        var at: [String: Int] = [:]
        var out: [PlanChange] = []
        out.reserveCapacity(a.count + b.count)
        for list in [a, b] {
            for c in list {
                guard let i = at[c.id] else { at[c.id] = out.count; out.append(c); continue }
                // The same line seen twice: taken back on either side is taken back.
                let undone = out[i].undone || c.undone
                if out[i].undone == c.undone ? out[i] == c : { var p = c; p.undone = out[i].undone; return p == out[i] }() {
                    out[i].undone = undone          // the usual case, and a cheap one
                    continue
                }
                let have = PlanBook.bytes(out[i]), new = PlanBook.bytes(c)
                if new.count > have.count || (new.count == have.count && out[i].undone == c.undone && have.lexicographicallyPrecedes(new)) {
                    out[i] = c
                }
                out[i].undone = undone
            }
        }
        out.sort { $0.at != $1.at ? $0.at < $1.at : $0.id < $1.id }
        return out
    }

    /* The newest 400; a removal is never dropped (it is the only place a taken-out session still lives). */
    private static func capped(_ changes: [PlanChange]) -> [PlanChange] {
        var over = changes.count - 400
        if over <= 0 { return changes }
        return changes.filter { c in
            if over > 0 && c.kind != "remove" { over -= 1; return false }
            return true
        }
    }

    /* Extras made in the app (they have a ref and sit beyond the workbook's last row) take the rows after it, in a fixed order. */
    private static func renumbered(_ extras: [ExtraRecord], after boundary: Int) -> [ExtraRecord] {
        let mine = extras.filter { !$0.ref.isEmpty && $0.row > boundary }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.ref < $1.ref }
        var next = boundary
        var rowOf: [String: Int] = [:]
        let mineIDs = Set(mine.map(\.id))
        let taken = Set(extras.filter { !mineIDs.contains($0.id) }.map(\.row))
        for e in mine {
            next += 1
            while taken.contains(next) { next += 1 }
            rowOf[e.id] = next
        }
        let out = extras.map { e -> ExtraRecord in
            guard let row = rowOf[e.id] else { return e }
            return ExtraRecord(row: row, date: e.date, activity: e.activity, label: e.label, what: e.what, minutes: e.minutes,
                               distance: e.distance, avgHr: e.avgHr, effort: e.effort, isTraining: e.isTraining,
                               notes: e.notes, ref: e.ref)
        }
        return out.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.row != $1.row ? $0.row > $1.row : $0.id < $1.id) }
    }
}

/// What one meeting with iCloud comes to. Pure: no disk, no iCloud.
public struct BookJoin: Equatable {
    public var book: PlanBook
    /// The joined book differs from mine: put it in place here (after a safety copy).
    public var changesLocal: Bool
    /// The iCloud file is missing, differs or had conflict copies: write the joined book there.
    public var changesCloud: Bool
    public var refused: BookMerge.Refusal?
    /// Session keys ("Weekly Schedules!7"), extras ("extra:<id>") and log boxes ("log:<session key>") that were
    /// in `local` and are not in `book`. Non-empty → a "before merge" safety copy is taken first.
    public var takenAway: [String]
    /// Conflict copies went into the join: clear them (with the write, or on their own when nothing else changed).
    public var clearConflicts = false

    public init(book: PlanBook, changesLocal: Bool, changesCloud: Bool, refused: BookMerge.Refusal?, takenAway: [String]) {
        self.book = book; self.changesLocal = changesLocal; self.changesCloud = changesCloud
        self.refused = refused; self.takenAway = takenAway
    }
}

// MARK: - marks

extension PlanBook {
    static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }
    static func date(ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /* Sorted-keys JSON, the way the book itself is written. */
    static func bytes<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return (try? encoder.encode(value)) ?? Data()
    }

    /*
     * The last row of the workbook's own extras. Nil in the book means "worked out": the highest row of an
     * extra nobody has changed since, and never less than the rows the import counted (plus the heading).
     */
    var extrasBoundary: Int {
        if let known = origin.extrasLastRow { return known }
        let untouched = extras.filter { stamps["extra:" + $0.id] == nil }.map(\.row).max() ?? 0
        return max(untouched, origin.extras + 1, 1)
    }

    /*
     * Marks by difference: every plan side, log side, extra, zones, weeks and test list that differs from
     * `old` is stamped now; what vanished gets a removed mark. A mark never goes backwards:
     * max(now, old mark + 1 ms, removed mark + 1 ms), so a clock set back cannot lose to the edit before it.
     */
    public func stamped(after old: PlanBook, now: Date = Date()) -> PlanBook {
        var book = self
        let t = PlanBook.ms(now)
        func next(_ key: String, over: [Date?]) -> Date {
            var m = t
            for d in over { if let d { m = max(m, PlanBook.ms(d) + 1) } }
            if let own = book.stamps[key] { m = max(m, PlanBook.ms(own)) }
            return PlanBook.date(ms: m)
        }
        func mark(_ key: String) {
            book.stamps[key] = next(key, over: [old.stamps[key], old.removed[key], book.removed[key]])
        }
        let oldSessions = Dictionary(old.sessions.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        let nowKeys = Set(sessions.map(\.key))
        for w in sessions {
            guard let was = oldSessions[w.key] else {
                mark(w.key)
                // A session that comes back (an undo, a safety copy) brings its log with the log's own
                // mark when it has one: an old log marked "now" would win over one logged since elsewhere.
                if !w.results.isEmpty && book.stamps["log:" + w.key] == nil { mark("log:" + w.key) }
                if let r = book.removed[w.key], let s = book.stamps[w.key], s > r { book.removed[w.key] = nil }
                continue
            }
            if w == was { continue }
            if w.planBytes != was.planBytes { mark(w.key) }
            if w.logBytes != was.logBytes { mark("log:" + w.key) }
        }
        for was in old.sessions where !nowKeys.contains(was.key) {
            var m = t
            for d in [old.stamps[was.key], old.stamps["log:" + was.key], old.removed[was.key]] { if let d { m = max(m, PlanBook.ms(d) + 1) } }
            if let own = book.removed[was.key] { m = max(m, PlanBook.ms(own)) }
            book.removed[was.key] = PlanBook.date(ms: m)
        }
        let oldExtras = Dictionary(old.extras.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let nowIDs = Set(extras.map(\.id))
        for e in extras {
            if let was = oldExtras[e.id], e == was || PlanBook.bytes(e.withRow(0)) == PlanBook.bytes(was.withRow(0)) { continue }
            mark("extra:" + e.id)
            if let r = book.removed["extra:" + e.id], let s = book.stamps["extra:" + e.id], s > r { book.removed["extra:" + e.id] = nil }
        }
        for was in old.extras where !nowIDs.contains(was.id) {
            let k = "extra:" + was.id
            var m = t
            for d in [old.stamps[k], old.removed[k]] { if let d { m = max(m, PlanBook.ms(d) + 1) } }
            if let own = book.removed[k] { m = max(m, PlanBook.ms(own)) }
            book.removed[k] = PlanBook.date(ms: m)
        }
        // Equal values first (cheap); the bytes decide only when they differ (a number that is not a number).
        if zones != old.zones && PlanBook.bytes(zones) != PlanBook.bytes(old.zones) { mark("zones") }
        if weeks != old.weeks && PlanBook.bytes(weeks) != PlanBook.bytes(old.weeks) { mark("weeks") }
        if tests != old.tests && PlanBook.bytes(tests) != PlanBook.bytes(old.tests) { mark("tests") }
        return book
    }

    /*
     * Items with no mark at all get a day in January 2001 by device rank (Mac 1, iPad 2, iPhone 3) — never
     * "now", so a copy that only just arrived cannot beat what was really changed.
     */
    public func baselined(rank: Int) -> PlanBook {
        var book = self
        let base = Date(timeIntervalSince1970: 978_307_200 + Double(max(rank, 0)) * 86_400)
        for w in sessions {
            if book.stamps[w.key] == nil { book.stamps[w.key] = base }
            if !w.results.isEmpty, book.stamps["log:" + w.key] == nil { book.stamps["log:" + w.key] = base }
        }
        for e in extras where book.stamps["extra:" + e.id] == nil { book.stamps["extra:" + e.id] = base }
        if zones != nil, book.stamps["zones"] == nil { book.stamps["zones"] = base }
        if !weeks.isEmpty, book.stamps["weeks"] == nil { book.stamps["weeks"] = base }
        if !tests.isEmpty, book.stamps["tests"] == nil { book.stamps["tests"] = base }
        return book
    }
}

extension PlanOrigin {
    var describe: String { "\(fileName) \(PlanBook.ms(takenAt))" }
}

extension Mapping {
    var bytes: Data { PlanBook.bytes(self) }
}

extension ExtraRecord {
    func withRow(_ row: Int) -> ExtraRecord {
        ExtraRecord(row: row, date: date, activity: activity, label: label, what: what, minutes: minutes,
                    distance: distance, avgHr: avgHr, effort: effort, isTraining: isTraining, notes: notes, ref: ref)
    }
}

// MARK: - putting a safety copy back while the plan is shared

extension PlanBook {
    /*
     * A safety copy put back while other devices share the plan. The plan's
     * own side goes back — the days, words and lengths, the weeks, and which
     * sessions are in the plan — and is marked as a change made now, so the
     * other devices take it too. What he logged since the copy stays: a
     * session's log is the copy's only where the copy's log mark is the later
     * one; a session logged since that the copy does not have stays in the
     * plan; extra workouts, test results and zones stay as they are now.
     * A copy of another plan (another move into the app) is not mixed in: nil.
     */
    public static func putBack(_ copy: PlanBook, over current: PlanBook, now: Date = Date()) -> PlanBook? {
        guard BookMerge.samePlan(copy, current), !copy.isFromNewerApp else { return nil }
        func logMark(_ book: PlanBook, _ w: Workout) -> Date? {
            book.stamps["log:" + w.key] ?? (w.results.isEmpty ? nil : book.stamps[w.key])
        }
        let cur = Dictionary(current.sessions.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        let old = Dictionary(copy.sessions.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
        var sessions: [Workout] = []
        for w in copy.sessions {
            guard let c = cur[w.key], c.logBytes != w.logBytes else { sessions.append(w); continue }
            // The copy's log only if it is the later one (it seldom is); else what he logged since.
            let copyLater = (logMark(copy, w) ?? .distantPast) > (logMark(current, c) ?? .distantPast)
            sessions.append(copyLater ? w : w.withLog(of: c, copy.mapping))
        }
        for w in current.sessions where old[w.key] == nil && !w.results.isEmpty {
            // Logged, and not in the copy: logged since (or the copy took it out unlogged) — it stays.
            if (logMark(current, w) ?? .distantFuture) > (copy.removed[w.key] ?? .distantPast) { sessions.append(w) }
        }
        var book = current
        for w in sessions where cur[w.key] == nil && !w.results.isEmpty {
            // Back from the copy with the copy's log: that log keeps its own (old) mark.
            book.stamps["log:" + w.key] = logMark(copy, w) ?? Date(timeIntervalSince1970: 0)
        }
        book.sessions = PlanBook.inOrder(sessions)
        book.weeks = copy.weeks
        book.counter = max(copy.counter, current.counter)
        // Marked by difference with the plan as it is now: what goes back is the newest change everywhere.
        return book.stamped(after: current, now: now)
    }
}

// MARK: - a session's two sides

private struct PlanSide: Encodable {
    let sheet: String, row: Int, rows: [Int], dayKey: String, disciplineRaw: String, title: String, phase: String
    let sections: [Section], planned: Planned, source: [String: String]?
}

extension Workout {
    /* Sorted-keys JSON of day, sport (raw), title, phase, sections, planned, source, rows. */
    public var planBytes: Data {
        PlanBook.bytes(PlanSide(sheet: sheet, row: row, rows: rows, dayKey: dayKey, disciplineRaw: disciplineRaw, title: title,
                                phase: phase, sections: sections, planned: planned, source: source))
    }

    /* Sorted-keys JSON of the results. */
    public var logBytes: Data { PlanBook.bytes(results) }

    /* This session with `other`'s results laid in; logged / missed worked out again from the mapping. */
    func withLog(of other: Workout, _ mapping: Mapping) -> Workout {
        var w = self
        w.results = other.results
        w.loggedInSheet = Plan.isLogged(w.results)
        w.logged = w.loggedInSheet
        w.missed = w.results["done"].map { normalise($0.text) == normalise(mapping.missedValue) } ?? false
        w.pending = nil
        w.pendingMove = nil
        return w
    }
}
