import Foundation
import SwiftUI
import WorkoutCore

/*
 * Where the plan comes from, and the copy kept on the phone.
 *
 * Stage 1 opens the workbook through the Files app — Dropbox's own provider —
 * rather than signing in to Dropbox. That means no login to set up, and the
 * app holds permission for the one file he picked and nothing else. It also
 * means it cannot write even by accident: nothing here ever opens the file for
 * writing.
 *
 * The file is remembered as a bookmark and read again whenever the app comes
 * to the front. What was last read successfully is kept in Application
 * Support, so the plan still opens on a plane.
 */
@MainActor
final class Store: ObservableObject {
    enum Phase: Equatable { case empty, loading, ready, failed(String) }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var plan: [Workout] = []
    @Published private(set) var mapping: Mapping?
    @Published private(set) var fileName: String = ""
    @Published private(set) var readAt: Date?
    @Published private(set) var fromCache = false
    @Published private(set) var lastProblem: String?
    /* The Dropbox revision last read — what an upload will have to match. */
    @Published private(set) var rev: String?
    @Published var dropboxPath: String? = ProcessInfo.processInfo.environment["AMSWS_FAKE_PATH"] ?? UserDefaults.standard.string(forKey: "dropboxPath") {
        didSet { UserDefaults.standard.set(dropboxPath, forKey: "dropboxPath") }
    }

    /* Logged on this phone and not yet in Dropbox. Kept on disk: it is the only copy. */
    @Published private(set) var queue: [QueuedEntry] = []
    @Published private(set) var syncing = false

    private let bookmarkKey = "workbookBookmark"
    private let nameKey = "workbookName"
    private let readAtKey = "workbookReadAt"

    /* The "today" everything is measured from. Fixed by a launch argument in
       DEBUG so a screenshot of a given day can be taken on any day. */
    let todayOverride: String? = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_TODAY"]
        #else
        return nil
        #endif
    }()

    var today: String { todayOverride ?? PlanView.todayKey() }

    /* The plan as shown: the sheet with the queue laid over it. */
    var displayed: [Workout] { Sync.overlay(plan, queue) }
    var view: PlanView? { mapping.map { PlanView(plan: displayed, mapping: $0, extras: allExtras) } }

    @Published private(set) var extras: [ExtraRecord] = []
    /* The Test Results & Zones sheet, for what a session's Z2 means. */
    @Published private(set) var zones: Zones?

    /*
     * Waiting on this phone first, then the sheet's rows — newest first.
     *
     * A correction still waiting is not a row of its own: it is laid over the
     * row it corrects, the way the queue is laid over the plan, so the screen
     * shows what was just typed rather than what the sheet still says — and
     * shows it once rather than twice.
     */
    var allExtras: [ExtraSummary] {
        let corrections = queue.compactMap { q -> ExtraEntry? in
            guard let x = q.extra, x.editing != nil else { return nil }
            return x
        }
        let waiting = queue.compactMap { q -> ExtraSummary? in
            guard let x = q.extra, x.editing == nil else { return nil }
            return Store.summary(id: q.id, of: x, pending: true)
        }.reversed()
        let saved = extras.map { r -> ExtraSummary in
            // The queue is replayed in order, so the last correction is the one
            // the sheet will end up carrying.
            if let corrected = corrections.last(where: { $0.editing?.id == r.id }) {
                return Store.summary(id: r.id, of: corrected, pending: true)
            }
            return ExtraSummary(id: r.id, dayKey: r.date, activity: r.activity, label: r.label, what: r.what,
                                minutes: r.minutes, isTraining: r.isTraining, pending: false,
                                distance: r.distance, avgHr: r.avgHr, effort: r.effort, notes: r.notes, ref: r.ref)
        }
        return waiting + saved
    }

    /* A queued extra as the screens see it; a number reads as the sheet would hold it. */
    private static func summary(id: String, of x: ExtraEntry, pending: Bool) -> ExtraSummary {
        func text(_ n: Double?) -> String { n.map(jsNumberString) ?? "" }
        return ExtraSummary(id: id, dayKey: x.date, activity: x.activity, label: Extras.activity(x.activity).label,
                            what: x.what, minutes: x.minutes, isTraining: x.isTraining, pending: pending,
                            distance: text(x.distance), avgHr: text(x.avgHr), effort: text(x.effort),
                            notes: x.notes, ref: x.ref)
    }

    func logExtra(_ entry: ExtraEntry) {
        guard canLog else { return }
        queue.append(QueuedEntry(extra: entry))
        saveQueue()
        syncNow()
    }

    /*
     * Changing an extra that is already saved.
     *
     * Where it goes depends on where the extra is. One still waiting on this
     * phone has not been written anywhere, so the waiting entry simply becomes
     * what it now says — there is no row yet to correct, and queueing a
     * correction behind it would write the first version and then mend it. One
     * already on the Extras sheet gets a correction of its own, naming its row
     * and the columns that changed.
     *
     * A second correction to the same row replaces the first rather than
     * joining the queue behind it: both would find that row by what it says,
     * and the first write is about to change exactly that.
     *
     * Photographs hang on the day, the activity and the length (invariant 9),
     * so any of those three moving takes the key they hang on with it. They
     * are carried over here, in the same step, or correcting a walk would
     * quietly leave its pictures behind.
     */
    func editExtra(_ original: ExtraSummary, _ entry: ExtraEntry, fields: [String]) {
        guard canLog, !fields.isEmpty else { return }
        let was = PhotoOwner(extra: original)
        var entry = entry

        if let i = queue.firstIndex(where: { $0.id == original.id && $0.extra?.editing == nil }) {
            entry.ref = queue[i].extra?.ref ?? entry.ref
            entry.editing = nil
            queue[i].extra = entry
        } else if let i = queue.firstIndex(where: { $0.extra?.editing?.id == original.id }),
                  var target = queue[i].extra?.editing {
            target.fields = Array(Set(target.fields).union(fields))
            entry.ref = queue[i].extra?.ref ?? entry.ref
            entry.editing = target
            queue[i].extra = entry
        } else {
            if !original.ref.isEmpty { entry.ref = original.ref }
            entry.editing = ExtraTarget(id: original.id, ref: original.ref, date: original.dayKey,
                                        label: original.label, minutes: original.minutes, fields: fields)
            queue.append(QueuedEntry(extra: entry))
        }
        saveQueue()
        PhotoStore.shared.reassign(from: was, to: PhotoOwner(extra: Store.summary(id: original.id, of: entry, pending: true)))
        syncNow()
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workbook.xlsx")
    }

    private var queueURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("queue.json")
    }

    private func saveQueue() {
        do {
            try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(queue).write(to: queueURL, options: .atomic)
        } catch {
            lastProblem = "Could not save the waiting log on this phone: \(error.localizedDescription)"
        }
        calendarChanged()
    }

    /* The Calendar app follows the plan as shown: the sheet with the queue laid over it. */
    func calendarChanged() {
        guard let mapping else { return }
        TrainingCalendar.shared.sync(displayed, mapping: mapping, today: today)
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_RESET"] != nil {
            try? FileManager.default.removeItem(at: queueURL)
            UserDefaults.standard.removeObject(forKey: "moveLog")
            HealthMark.forgetAll()
        }
        #endif
        if let data = try? Data(contentsOf: queueURL), let saved = try? JSONDecoder().decode([QueuedEntry].self, from: data) {
            queue = saved
        }
        fileName = UserDefaults.standard.string(forKey: nameKey) ?? ""
        readAt = UserDefaults.standard.object(forKey: readAtKey) as? Date
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["AMSWS_FILE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            fileName = URL(fileURLWithPath: path).lastPathComponent
            parse(data, cached: false)
            return
        }
        #endif
        if let data = try? Data(contentsOf: cacheURL) {
            parse(data, cached: true)
        }
    }

    var hasWorkbook: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil || dropboxPath != nil || !plan.isEmpty }

    /* A plan picked inside the app from his Dropbox, read through the API. */
    func chooseDropbox(_ file: DropboxFile) {
        // The displayed path, not path_lower: an upload re-cases the file's
        // name to the path it was sent to, and "Workout Sync TEST.xlsx" came
        // back from the first phone sync as "workout sync test.xlsx".
        dropboxPath = file.path
        fileName = file.name
        UserDefaults.standard.set(file.name, forKey: nameKey)
        refresh()
    }

    /* The file picked in the Files app. */
    func choose(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
            fileName = url.lastPathComponent
        } catch {
            lastProblem = "The app could not remember that file: \(error.localizedDescription)"
        }
        refresh()
    }

    /* Read the workbook again from wherever it lives. */
    func refresh() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_FILE"] != nil { return }
        #endif
        if let path = dropboxPath, Dropbox.shared.isConnected {
            if !queue.isEmpty { syncNow(); return }
            if plan.isEmpty { phase = .loading }
            Task {
                do {
                    let file = try await Dropbox.shared.download(path)
                    self.rev = file.rev
                    if !file.name.isEmpty { self.fileName = file.name }
                    self.parse(file.data, cached: false)
                } catch {
                    self.lastProblem = "Could not read the plan from Dropbox just now: \(error.localizedDescription)"
                    if self.plan.isEmpty { self.phase = .failed(self.lastProblem!) }
                }
            }
            return
        }
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        if plan.isEmpty { phase = .loading }

        Task.detached(priority: .userInitiated) { [bookmarkKey] in
            var stale = false
            let result: Result<Data, Error>
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                }
                // Coordinated, so the Dropbox provider hands over its current
                // copy rather than whatever it last downloaded.
                var coordinationError: NSError?
                var read: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { real in
                    read = Result { try Data(contentsOf: real) }
                }
                if let coordinationError { throw coordinationError }
                result = read
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                switch result {
                case .success(let data):
                    self.parse(data, cached: false)
                case .failure(let error):
                    self.lastProblem = "Could not read the workbook just now: \(error.localizedDescription)"
                    if self.plan.isEmpty { self.phase = .failed(self.lastProblem!) }
                }
            }
        }
    }

    private func parse(_ data: Data, cached: Bool) {
        do {
            let workbook = try Workbook(data: data)
            guard let mapping = try Plan.mapping(for: workbook) else {
                throw NSError(domain: "AMSWorkoutSync", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Nothing in this workbook looks like a training plan."])
            }
            self.plan = Plan.build(workbook, mapping)
            self.extras = Extras.read(workbook)
            self.zones = Zones.read(workbook)
            self.mapping = mapping
            self.fromCache = cached
            self.phase = .ready
            calendarChanged()
            if !cached {
                lastProblem = nil
                readAt = Date()
                UserDefaults.standard.set(readAt, forKey: readAtKey)
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            lastProblem = error.localizedDescription
            if plan.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    func workout(_ key: String) -> Workout? { displayed.first { $0.key == key } }

    // MARK: logging

    var canLog: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_SHOW_BUTTONS"] != nil { return true }
        #endif
        return dropboxPath != nil && Dropbox.shared.isConnected
    }

    func isWaiting(_ key: String) -> Bool { queue.contains { $0.workoutKey == key } }

    /*
     * One tap: the planned length as the actual one, and nothing else — so
     * exactly the duration and the done marker are written, as in the web
     * app's logAsPlanned. Queued first, then sent.
     */
    func logAsPlanned(_ workout: Workout) {
        guard canLog, let mapping, let seconds = Plan.plannedSeconds(workout, mapping), seconds > 0 else { return }
        var entry = LogEntry()
        entry.actualDuration = String(Int((seconds / 60 + 0.5).rounded(.down)))
        queue.append(QueuedEntry(workout: workout, entry: entry))
        saveQueue()
        syncNow()
    }

    /* Anything from the log form. Queued first, then sent; only what changed is in it. */
    func log(_ workout: Workout, _ entry: LogEntry) {
        guard canLog else { return }
        queue.append(QueuedEntry(workout: workout, entry: entry))
        saveQueue()
        syncNow()
    }

    /* A session that did not happen: the marker and a note, nothing else. */
    func markMissed(_ workout: Workout, note: String) {
        var entry = LogEntry()
        entry.missed = true
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { entry.notes = trimmed }
        log(workout, entry)
    }

    /*
     * The move log: the one thing this app remembers that the workbook does
     * not. Rescheduling overwrites the date, so the sheet keeps no memory of a
     * move; Progress needs it for "moved rather than lost". Kept on this
     * phone, keyed by the session, believed only while the sport still
     * matches the row (web app v1.40.0 rules).
     */
    @Published private(set) var moves: [String: MoveRecord] = {
        guard let data = UserDefaults.standard.data(forKey: "moveLog"),
              let saved = try? JSONDecoder().decode([String: MoveRecord].self, from: data) else { return [:] }
        return saved
    }()
    var movesSince: Date? { moves.values.map(\.at).min() }

    private func rememberMove(_ workout: Workout, to dayKey: String) {
        let existing = moves[workout.key]
        // A session moved twice is one move from where the plan first put it.
        let from = existing?.from ?? workout.dayKey
        moves[workout.key] = MoveRecord(from: from, to: dayKey, disciplineId: workout.discipline.id, at: Date())
        if moves.count > 600 {
            for key in moves.sorted { $0.value.at < $1.value.at }.prefix(moves.count - 600).map(\.key) { moves[key] = nil }
        }
        if let data = try? JSONEncoder().encode(moves) { UserDefaults.standard.set(data, forKey: "moveLog") }
    }

    /* Only the date is rewritten; the weekday beside it is learned from the sheet at sync time. */
    func move(_ workout: Workout, to dayKey: String) {
        guard dayKey != workout.dayKey, canLog else { return }
        var entry = LogEntry()
        entry.moveTo = dayKey
        log(workout, entry)
        rememberMove(workout, to: dayKey)
    }

    /* Two moves, both days read before either is queued. */
    func swap(_ a: Workout, _ b: Workout) {
        let aDay = a.dayKey
        let bDay = b.dayKey
        guard aDay != bDay, canLog else { return }
        var first = LogEntry(); first.moveTo = bDay
        var second = LogEntry(); second.moveTo = aDay
        queue.append(QueuedEntry(workout: a, entry: first))
        queue.append(QueuedEntry(workout: b, entry: second))
        saveQueue()
        rememberMove(a, to: bDay)
        rememberMove(b, to: aDay)
        syncNow()
    }

    // MARK: progress

    struct Progress {
        let summary: Stats.Summary
        let trends: [Stats.Trend]
        let load: Stats.Load
        let road: Stats.Road?
    }

    /* Derived here and now from the plan already in memory; nothing cached, nothing written. */
    var progress: Progress? {
        guard let mapping, let view else { return nil }
        let plan = displayed
        let today = self.today
        return Progress(
            summary: Stats.summarise(plan, moves: moves, movesSince: movesSince, today: today, mapping: mapping),
            trends: Stats.trends(Stats.trendRows(plan, mapping)),
            load: Stats.load(Stats.loadRows(plan, mapping), weekStarts: Stats.recentWeekStarts(12, today: today),
                             endExclusive: PlanView.addDays(PlanView.weekStart(today), 7)),
            road: Stats.road(view.visible, today: today, mapping: mapping))
    }

    /* Text for the warning once the oldest waiting entry is a full day old; nil below that. */
    var waitedTooLong: String? {
        guard let oldest = queue.map(\.createdAt).min() else { return nil }
        let hours = Date().timeIntervalSince(oldest) / 3600
        guard hours >= 24 else { return nil }
        let count = queue.count
        let age = hours >= 48 ? "\(Int(hours / 24)) days" : "a day"
        let reason = queue.compactMap(\.lastError).last ?? lastProblem ?? "The phone may have been offline, or Dropbox unreachable."
        return "\(count) entr\(count == 1 ? "y has" : "ies have") waited \(age). \(reason)"
    }

    func discard(_ id: String) {
        queue.removeAll { $0.id == id }
        saveQueue()
    }

    func syncNow() {
        guard !syncing, !queue.isEmpty, let path = dropboxPath, Dropbox.shared.isConnected else { return }
        syncing = true
        let snapshot = queue
        Task {
            defer { self.syncing = false }
            do {
                let result = try await Sync.run(snapshot, path: path, remote: DropboxRemote())
                let gone = Set(result.written + result.dropped)
                self.queue.removeAll { gone.contains($0.id) }
                for i in self.queue.indices {
                    if let why = result.failed[self.queue[i].id] {
                        self.queue[i].attempts += 1
                        self.queue[i].lastError = why
                    }
                }
                self.saveQueue()
                if let uploaded = result.uploaded {
                    self.rev = uploaded.rev
                    self.parse(uploaded.data, cached: false)
                }
                self.lastProblem = result.failed.isEmpty ? nil : "Some logging could not be written — see Settings."
            } catch RemoteError.conflict {
                self.lastProblem = "The plan kept changing in Dropbox while sending. Your logging is still waiting; try again in a moment."
            } catch {
                self.lastProblem = "Could not send your logging just now: \(error.localizedDescription) It is still waiting on this phone."
            }
        }
    }
}
