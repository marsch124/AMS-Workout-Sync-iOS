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
    public let createdAt: Date
    public var attempts: Int = 0
    public var lastError: String?

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
    case noLayout, unreadable(String), noSheets, sessionsLost(Int, Int), noSession(String), nothingToWrite

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
            return "This entry had nothing that could be written."
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

    /*
     * The row is checked before it is used. The discipline must still match;
     * then either the date or the wording must — rewording a session keeps its
     * date, moving it keeps its wording. A session changed in all three ways is
     * a different session, and nothing is written.
     */
    public static func findWorkout(for e: QueuedEntry, in plan: [Workout]) -> Workout? {
        let here = e.sheet.isEmpty ? plan : plan.filter { $0.sheet == e.sheet }

        if let same = here.first(where: { $0.key == e.workoutKey }), stillTheSameSession(same, e) { return same }

        let sameSession = here.filter { stillTheSameSession($0, e) }
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
