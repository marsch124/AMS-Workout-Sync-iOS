import Foundation

/*
 * Getting logged sessions into the workbook in Dropbox: the queue and sync()
 * from js/sync.js.
 *
 * The rules are the web app's, and each exists because of something that went
 * wrong or nearly did:
 *
 *   - Nothing reaches the workbook until it is queued, and nothing leaves the
 *     queue until Dropbox has accepted the upload (invariant 6).
 *   - Always start from the copy that is in Dropbox right now, never a copy
 *     the phone read earlier.
 *   - A queued entry names a row, and a row is not a stable identity: the
 *     session is checked to still be the one that was logged before anything
 *     is written into it (findWorkoutFor).
 *   - One entry that cannot be written is recorded and kept; it never blocks
 *     the entries behind it.
 *   - The bytes about to be uploaded are opened and read again first. A
 *     workbook that does not read back, or has fewer sessions than it had,
 *     is never uploaded.
 *   - The upload carries the revision that was downloaded. If the file changed
 *     in between, Dropbox refuses, and the sync starts once more from the new
 *     copy with the queue intact.
 *
 * The network is behind a protocol so the whole path can be run on the Mac
 * against files on disk — including a conflict — before it is run against
 * Dropbox.
 */

public struct QueuedEntry: Codable, Identifiable, Equatable {
    public let id: String
    public let workoutKey: String
    public let sheet: String
    public let row: Int
    public let dayKey: String
    public let disciplineId: String
    public let title: String
    public var entry: LogEntry
    /* An extra belongs to no row; when set, everything above is blank. */
    public var extra: ExtraEntry?
    public let createdAt: Date
    public var attempts: Int = 0
    public var lastError: String?

    public init(extra: ExtraEntry, now: Date = Date()) {
        id = UUID().uuidString
        workoutKey = ""; sheet = ""; row = 0; dayKey = extra.date; disciplineId = ""; title = ""
        entry = LogEntry()
        self.extra = extra
        createdAt = now
    }

    public init(workout: Workout, entry: LogEntry, now: Date = Date()) {
        id = UUID().uuidString
        workoutKey = workout.key
        sheet = workout.sheet
        row = workout.row
        dayKey = workout.dayKey
        disciplineId = workout.discipline.id
        title = workout.title
        self.entry = entry
        createdAt = now
    }

    /* An entry as it was stored, for tests and for entries a device no longer has a Workout for. */
    public init(workoutKey: String, sheet: String, row: Int, dayKey: String, disciplineId: String, title: String,
                entry: LogEntry, now: Date = Date()) {
        id = UUID().uuidString
        self.workoutKey = workoutKey
        self.sheet = sheet
        self.row = row
        self.dayKey = dayKey
        self.disciplineId = disciplineId
        self.title = title
        self.entry = entry
        createdAt = now
    }

    public static func == (a: QueuedEntry, b: QueuedEntry) -> Bool { a.id == b.id && a.attempts == b.attempts }
}

extension LogEntry: Equatable {
    public static func == (a: LogEntry, b: LogEntry) -> Bool {
        (try? JSONEncoder().encode(a)) == (try? JSONEncoder().encode(b))
    }
}

public struct RemoteFile {
    public let data: Data
    public let rev: String
    public let name: String
    public init(data: Data, rev: String, name: String) {
        self.data = data
        self.rev = rev
        self.name = name
    }
}

public enum RemoteError: Error { case conflict }

public protocol Remote {
    func download(_ path: String) async throws -> RemoteFile
    /* Must refuse with RemoteError.conflict when the file is no longer at `rev`. */
    func upload(_ path: String, _ data: Data, rev: String) async throws -> RemoteFile
}

public enum SyncError: LocalizedError {
    case noLayout, unreadable(String), noSheets, sessionsLost(Int, Int), noSession(String), nothingToWrite, extrasSheetTaken
    case noExtraRow(String)

    public var errorDescription: String? {
        switch self {
        case .noLayout:
            return "The layout of this workbook could not be worked out."
        case .unreadable(let why):
            return "The app built a workbook it could not read back, so nothing was uploaded and your logging is still waiting. (\(why))"
        case .noSheets:
            return "The app built a workbook with no sheets in it, so nothing was uploaded and your logging is still waiting."
        case .sessionsLost(let after, let before):
            return "The workbook the app built has \(after) sessions where the one it read had \(before). Nothing was uploaded and your logging is still waiting."
        case .noSession(let title):
            return "The session this was logged against (\"\(title.prefix(40))\") is no longer in the workbook, or has been changed into a different one. Nothing was written; log it again against the row you want."
        case .nothingToWrite:
            return "This entry had nothing that could be written to the Extras sheet."
        case .extrasSheetTaken:
            return "There is already a sheet called \"Extras\" that is not this app’s, and no free name to use instead."
        case .noExtraRow(let label):
            return "The \(label.lowercased()) you adjusted is no longer on the Extras sheet — its row may have been removed or rewritten in Excel. Nothing was written; the correction is still waiting."
        }
    }
}

public struct SyncResult {
    public var written: [String] = []                 // entry ids now in Dropbox
    public var dropped: [String] = []                 // entries with nothing mappable, removed
    public var failed: [String: String] = [:]         // entry id -> why
    public var uploaded: RemoteFile?                  // the workbook as Dropbox now holds it
}

public enum Sync {
    // MARK: which row an entry belongs to

    static func normaliseTitle(_ text: String) -> String {
        let spaced = text.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return jsTrim(spaced)
    }

    static func titlesAgree(_ a: String, _ b: String) -> Bool {
        let x = normaliseTitle(a)
        let y = normaliseTitle(b)
        if x.isEmpty || y.isEmpty { return false }
        if x == y { return true }
        if x.hasPrefix(y) || y.hasPrefix(x) { return true }
        // slice(0, 20) counts UTF-16 units, as JavaScript does.
        return Array(x.utf16.prefix(20)) == Array(y.utf16.prefix(20))
    }

    static func stillTheSameSession(_ w: Workout, _ e: QueuedEntry) -> Bool {
        if !e.disciplineId.isEmpty && w.discipline.id != e.disciplineId { return false }
        if e.dayKey.isEmpty && e.title.isEmpty { return true }
        return w.dayKey == e.dayKey || titlesAgree(w.title, e.title)
    }

    static let nearbyDays = 7.0

    static func withinAWeek(_ w: Workout, _ e: QueuedEntry) -> Bool {
        if e.dayKey.isEmpty { return true }
        guard let a = parseDayKey(w.dayKey), let b = parseDayKey(e.dayKey) else { return false }
        return abs(a.timeIntervalSince(b)) <= nearbyDays * 86400
    }

    /*
     * The row is checked before it is used. The discipline must still match;
     * then either the date or the wording must — rewording a session keeps its
     * date, moving it keeps its wording. A session changed in all three ways is
     * a different session, and nothing is written.
     */
    public static func findWorkout(for e: QueuedEntry, in plan: [Workout]) -> Workout? {
        let here = e.sheet.isEmpty ? plan : plan.filter { $0.sheet == e.sheet }

        if let same = here.first(where: { $0.key == e.workoutKey }), stillTheSameSession(same, e) { return same }

        // And only nearby: a plan repeats sessions word for word, so wording
        // alone found the same test seven weeks away (web app v1.72.1, the same rule).
        let sameSession = here.filter { stillTheSameSession($0, e) && withinAWeek($0, e) }
        if sameSession.isEmpty { return nil }
        if sameSession.count == 1 { return sameSession[0] }

        let byTitle = sameSession.filter { titlesAgree($0.title, e.title) }
        let pool = byTitle.isEmpty ? sameSession : byTitle
        let untouched = pool.filter { !$0.loggedInSheet }
        let choose = untouched.isEmpty ? pool : untouched

        var best: Workout?
        for w in choose {
            guard let current = best else { best = w; continue }
            if abs(w.row - e.row) < abs(current.row - e.row) { best = w }
        }
        return best
    }

    // MARK: what the screen shows before the sync

    /* Every queued entry belonging to a session, in queue order. As matchEntries in the web app. */
    static func entries(for w: Workout, in queue: [QueuedEntry]) -> [QueuedEntry] {
        let queue = queue.filter { $0.extra == nil }
        let byKey = queue.filter { $0.workoutKey == w.key }
        if !byKey.isEmpty { return byKey }
        return queue.filter { $0.dayKey == w.dayKey && $0.disciplineId == w.discipline.id && $0.sheet == w.sheet }
    }

    /*
     * The plan with the queue laid over it, so what was just logged or moved
     * shows straight away rather than after the sync. A queued move and a
     * queued record are kept apart: a move never hides that a session is done
     * (web app v1.72.0). Nothing here is written anywhere.
     */
    public static func overlay(_ plan: [Workout], _ queue: [QueuedEntry]) -> [Workout] {
        var out = plan.map { w -> Workout in
            var w = w
            w.logged = w.loggedInSheet
            w.pending = nil
            w.pendingMove = nil
            let mine = entries(for: w, in: queue)
            if let move = mine.last(where: { $0.entry.moveTo != nil }), let to = move.entry.moveTo, let date = parseDayKey(to) {
                w = Workout(key: w.key, sheet: w.sheet, row: w.row, rows: w.rows, date: date, dayKey: to,
                            disciplineRaw: w.disciplineRaw, discipline: w.discipline, title: w.title, phase: w.phase,
                            sections: w.sections, planned: w.planned, results: w.results, loggedInSheet: w.loggedInSheet,
                            missed: w.missed, logged: w.logged, pending: nil, pendingMove: to)
            }
            if let record = mine.last(where: { $0.entry.moveTo == nil }) {
                w.pending = record.entry
                w.logged = true
                w.missed = record.entry.missed
            }
            return w
        }
        out.sort { ($0.date, $0.row) < ($1.date, $1.row) }
        return out
    }

    /*
     * The sessions offered under "Or swap it with": nearby, not rest, not
     * done (in the sheet or waiting), nearest first and the one still ahead
     * first on a tie — web app v1.71.2, the lesson of 14 September.
     */
    public static func swapCandidates(for w: Workout, in shown: [Workout]) -> [(workout: Workout, gap: Int)] {
        guard let here = parseDayKey(w.dayKey) else { return [] }
        // Stable, as the web app's sort is: equal gaps keep plan order.
        return shown.enumerated()
            .filter { $0.element.key != w.key && $0.element.discipline.id != "rest" && !$0.element.logged }
            .compactMap { pair -> (Workout, Int, Int)? in
                guard let d = parseDayKey(pair.element.dayKey) else { return nil }
                return (pair.element, Int((d.timeIntervalSince(here) / 86400).rounded()), pair.offset)
            }
            .filter { abs($0.1) <= 10 }
            .sorted { a, b in
                if abs(a.1) != abs(b.1) { return abs(a.1) < abs(b.1) }
                if a.1 != b.1 { return a.1 > b.1 }
                return a.2 < b.2
            }
            .prefix(12)
            .map { (workout: $0.0, gap: $0.1) }
    }

    // MARK: applying the queue

    /*
     * The queue written into a workbook, in memory. Returns the bytes to upload
     * (nil when nothing was written) and what happened to each entry.
     */
    public static func apply(_ queue: [QueuedEntry], to data: Data, now: Date = Date()) throws -> (bytes: Data?, result: SyncResult) {
        let workbook = try Workbook(data: data)
        guard let mapping = try Plan.mapping(for: workbook) else { throw SyncError.noLayout }
        let plan = Plan.build(workbook, mapping)
        var result = SyncResult()

        for queued in queue {
            do {
                if let extra = queued.extra {
                    /*
                     * A correction to an extra already written goes into its own
                     * row, found by its reference: never appended, or adjusting a
                     * walk would leave two of it. The sheet is not created here —
                     * if there is none, the row this names is gone and saying so
                     * is better than writing the correction somewhere new.
                     */
                    if let target = extra.editing {
                        let name = try Extras.sheetName(for: workbook)
                        guard workbook.findSheet(name) != nil,
                              let sheet = try? workbook.readSheet(name),
                              let row = Extras.findRow(sheet, target) else {
                            throw SyncError.noExtraRow(Extras.activity(extra.activity).label)
                        }
                        let names = (try? learnWeekdayNames(try workbook.readSheet(mapping.sheets[0]), mapping)) ?? [:]
                        let edits = Extras.buildEdits(sheet, extra, row: row, weekdayNames: names)
                        if edits.isEmpty { result.dropped.append(queued.id); continue }
                        try workbook.writeCells(name, edits)
                        result.written.append(queued.id)
                        continue
                    }
                    // Appending is not idempotent the way writing to a known row
                    // is, so a replay must not add the same thing twice.
                    let name = try Extras.ensureSheet(workbook)
                    let sheet = try workbook.readSheet(name)
                    if Extras.alreadyRecorded(sheet, extra) { result.written.append(queued.id); continue }
                    let names = (try? learnWeekdayNames(try workbook.readSheet(mapping.sheets[0]), mapping)) ?? [:]
                    let built = Extras.buildEdits(sheet, extra, weekdayNames: names)
                    if built.edits.isEmpty { throw SyncError.nothingToWrite }
                    try workbook.writeCells(name, built.edits)
                    result.written.append(queued.id)
                    continue
                }
                guard let workout = findWorkout(for: queued, in: plan) else { throw SyncError.noSession(queued.title) }
                var entry = queued.entry
                if entry.moveTo != nil && entry.weekdayNames == nil {
                    entry.weekdayNames = learnWeekdayNames(try workbook.readSheet(workout.sheet), mapping)
                }
                if !entry.missed && entry.moveTo == nil && entry.completedAt == nil { entry.completedAt = now }
                if entry.missed && entry.completedAt == nil { entry.completedAt = now }
                let edits = Plan.buildEdits(workout, entry, mapping)
                if edits.isEmpty {
                    result.dropped.append(queued.id)
                    continue
                }
                try workbook.writeCells(workout.sheet, edits)
                result.written.append(queued.id)
            } catch {
                result.failed[queued.id] = error.localizedDescription
            }
        }

        if result.written.isEmpty { return (nil, result) }
        let bytes = try workbook.save()
        try verify(bytes, sessionsBefore: plan.count)
        return (bytes, result)
    }

    /* Never hand Dropbox a file that cannot be read back. */
    public static func verify(_ bytes: Data, sessionsBefore: Int) throws {
        let check: Workbook
        do { check = try Workbook(data: bytes) } catch { throw SyncError.unreadable(error.localizedDescription) }
        if check.sheets.isEmpty { throw SyncError.noSheets }
        guard let mapping = try? Plan.mapping(for: check) else { throw SyncError.unreadable("no layout") }
        let after = Plan.build(check, mapping)
        if after.count < sessionsBefore { throw SyncError.sessionsLost(after.count, sessionsBefore) }
    }

    // MARK: the whole round trip

    public static func run(_ queue: [QueuedEntry], path: String, remote: Remote, now: Date = Date()) async throws -> SyncResult {
        var retried = false
        while true {
            let file = try await remote.download(path)
            let (bytes, result) = try apply(queue, to: file.data, now: now)
            guard let bytes else { return result }
            do {
                var done = result
                done.uploaded = try await remote.upload(path, bytes, rev: file.rev)
                return done
            } catch RemoteError.conflict where !retried {
                // Someone saved the file while we were working. Start again on
                // the newer copy — the queue is still intact.
                retried = true
            }
        }
    }
}
