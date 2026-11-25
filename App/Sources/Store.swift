import Foundation
import SwiftUI
import Combine
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

    /*
     * Where the plan lives. Until 2.0 always the workbook in Dropbox; once he
     * has tapped the switch, a book in this app (plan.json), and Dropbox is
     * no longer read or written.
     */
    enum Home: String { case excel, app }
    @Published private(set) var home: Home = .excel
    @Published private(set) var book: PlanBook?
    /* The workbook taken in and counted, waiting for his tap. Nothing is saved until then. */
    @Published private(set) var incoming: PlanImport?
    @Published private(set) var takingIn = false
    @Published private(set) var goingBack = false
    @Published private(set) var homeProblem: String?
    @Published private(set) var switchedAt: Date? = UserDefaults.standard.object(forKey: "plan.switchedAt") as? Date
    private var incomingBytes: Data?
    private let homeKey = "plan.home"

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

    /*
     * The waiting log, read as forgivingly as it can be.
     *
     * It used to be one `try?`: a file that would not decode left the queue
     * empty and said nothing, so everything he had logged and not yet sent
     * was gone without a word. Now a single bad entry loses only itself, and
     * a file that cannot be read at all is kept beside the queue rather than
     * thrown away (2026-09-30).
     */
    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueURL), !data.isEmpty else { return }
        if let saved = try? JSONDecoder().decode([QueuedEntry].self, from: data) {
            queue = saved
            return
        }
        var recovered: [QueuedEntry] = []
        if let items = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            for item in items {
                if let bytes = try? JSONSerialization.data(withJSONObject: item),
                   let one = try? JSONDecoder().decode(QueuedEntry.self, from: bytes) {
                    recovered.append(one)
                }
            }
        }
        queue = recovered
        let kept = queueURL.deletingLastPathComponent().appendingPathComponent("queue-unreadable.json")
        try? FileManager.default.removeItem(at: kept)
        try? FileManager.default.copyItem(at: queueURL, to: kept)
        lastProblem = recovered.isEmpty
            ? "The waiting log on this phone could not be read. Nothing has been thrown away — it is kept as queue-unreadable.json."
            : "Part of the waiting log could not be read; \(recovered.count) of it was recovered. The original is kept as queue-unreadable.json."
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
        // The iPhone alone keeps the Training calendar: it lives in iCloud's calendars and shows on the
        // iPad and the Mac already. Written by all three, every event would be there three times.
        guard Device.isPhone, let mapping else { return }
        TrainingCalendar.shared.sync(displayed, mapping: mapping, today: today)
    }

    /* The meeting point with iCloud (2.1). Made on first use; its changes redraw whatever shows the store. */
    private var cloudWatch: AnyCancellable?
    private(set) lazy var cloud: PlanCloud = {
        let made = PlanCloud(store: self)
        cloudWatch = made.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        return made
    }()

    init() {
        open()
        // iCloud is looked for once the plan here is open; never before, never instead.
        Diary.shared.onChange = { [weak self] in self?.cloud.localChanged() }
        ShelfStore.shared.onChange = { [weak self] in self?.cloud.localChanged() }
        Task { @MainActor [weak self] in self?.cloud.start() }
    }

    private func open() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_RESET"] != nil {
            try? FileManager.default.removeItem(at: queueURL)
            UserDefaults.standard.removeObject(forKey: "moveLog")
            UserDefaults.standard.removeObject(forKey: "moveLog.inBook")
            UserDefaults.standard.removeObject(forKey: PlanCloud.joinedKey)
            UserDefaults.standard.removeObject(forKey: PlanCloud.joinedAtKey)
            try? FileManager.default.removeItem(at: beforeICloudURL)
            // A screen test with a stand-in iCloud starts with nothing of a plan at all, whatever ran before it.
            if ProcessInfo.processInfo.environment["AMSWS_FAKE_CLOUD"] != nil {
                try? FileManager.default.removeItem(at: cacheURL)
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                UserDefaults.standard.removeObject(forKey: "dropboxPath")
                if ProcessInfo.processInfo.environment["AMSWS_FAKE_PATH"] == nil { dropboxPath = nil }
            }
            HealthMark.forgetAll()
            UserDefaults.standard.removeObject(forKey: "health.asked")
            UserDefaults.standard.removeObject(forKey: "health.enabled")
            for url in [bookURL, originalURL, backupsURL] { try? FileManager.default.removeItem(at: url) }
            UserDefaults.standard.removeObject(forKey: homeKey)
            UserDefaults.standard.removeObject(forKey: "plan.switchedAt")
            switchedAt = nil
        }
        #endif
        loadQueue()
        fileName = UserDefaults.standard.string(forKey: nameKey) ?? ""
        readAt = UserDefaults.standard.object(forKey: readAtKey) as? Date
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["AMSWS_FILE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            fileName = URL(fileURLWithPath: path).lastPathComponent
            // AMSWS_HOME=app: the same file, but taken in — the app as the plan's home.
            if ProcessInfo.processInfo.environment["AMSWS_HOME"] == "app",
               let taken = try? PlanImport.read(data, fileName: fileName, today: today) {
                home = .app
                switchedAt = switchedAt ?? Date()
                try? data.write(to: originalURL, options: .atomic)
                publish(taken.book)
                return
            }
            parse(data, cached: false)
            return
        }
        #endif
        if UserDefaults.standard.string(forKey: homeKey) == Home.app.rawValue {
            // The flag decides. A plan that lives here is never quietly swapped
            // for an old copy of the Excel file: he would log into the wrong plan.
            home = .app
            let raw = try? Data(contentsOf: bookURL)
            if var saved = raw.flatMap({ try? PlanBook.decoded($0) }) {
                // A plan written by 2.1 (format 1) is copied aside untouched, once, before anything saves over it.
                let untouched = raw.map { (CloudFiles.formatNumber($0) ?? 1) < 2 } ?? false
                let keptAside = !untouched || keepFormat1(raw!)
                var carried = carryIntoBook(&saved)
                // No copy (no room): the plan opens, and nothing is saved over the old file at opening.
                if !keptAside { carried = false }
                publish(saved)
                // The move log and the workbook's mark go into the book once (2.1); the flag only after it is on disk.
                if !carried || save(saved) { UserDefaults.standard.set(true, forKey: "moveLog.inBook") }
                // Anything still waiting from before the app was last closed is written in now.
                if !queue.isEmpty { writeHere() }
                return
            }
            if let rescued = newestSafetyCopy() {
                let aside = supportURL.appendingPathComponent("plan-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: bookURL, to: aside)
                try? rescued.data.write(to: bookURL, options: .atomic)
                publish(rescued.book)
                lastProblem = "The plan in this app could not be opened, so the safety copy of \(rescued.day) was put back. Anything you changed after that day is missing. The file that would not open is kept."
                return
            }
            let why = "The plan kept in this app could not be opened, and there is no safety copy on this phone. Nothing was changed. The spreadsheet copies in Files and in Dropbox still hold your plan."
            lastProblem = why
            phase = .failed(why)
            return
        }
        if let data = try? Data(contentsOf: cacheURL) {
            parse(data, cached: true)
        }
    }

    /* plan-format1.json beside the plan: the 2.1 file as it was, kept for good. False only if it could not be written. */
    private func keepFormat1(_ data: Data) -> Bool {
        let to = supportURL.appendingPathComponent("plan-format1.json")
        if FileManager.default.fileExists(atPath: to.path) { return true }
        return (try? data.write(to: to, options: .atomic)) != nil
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
        // Coming to the front is a meeting with iCloud too (it does nothing where iCloud is off).
        cloud.start()
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_FILE"] != nil { return }
        #endif
        // The plan lives here: there is nothing elsewhere to read. Coming to
        // the front is a good moment to send a copy that is still owed.
        if home == .app { copyToDropboxNow(); return }
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
        // A reading of the Excel file that was still on its way when the plan
        // moved in must not be laid over the plan that lives here now.
        if home == .app { return }
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
        // While the plan is being written back into Excel nothing may change under it.
        if home == .app { return !goingBack && book != nil }
        // An iPad or Mac never held the Excel plan: what it logged there would be lost when it takes
        // iCloud's plan (2.4.1, within moments). Only the iPhone logs into the workbook.
        return Device.isPhone && dropboxPath != nil && Dropbox.shared.isConnected
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

    /*
     * "How hard was it?" — one tap, 1 to 10, into the plan's own Effort
     * column: the same box the log form calls Effort, so nothing new is added
     * to the workbook. Whatever is still waiting for this session travels
     * with it, because the screens show the last waiting entry and a bare
     * number would hide the length just logged.
     */
    func setEffort(_ workout: Workout, _ score: Int) {
        guard canLog, (1...10).contains(score) else { return }
        var entry = LogEntry()
        if let waiting = workout.pending, !waiting.missed { entry = waiting }
        entry.rpe = String(score)
        log(workout, entry)
    }

    /* The same answer for an extra workout: only its Effort box is written. */
    func setEffort(extra: ExtraSummary, _ score: Int) {
        guard canLog, (1...10).contains(score) else { return }
        func number(_ s: String) -> Double? {
            let n = jsParseFloat(s.replacingOccurrences(of: ",", with: "."))
            return n.isNaN ? nil : n
        }
        var entry = extra.ref.isEmpty ? ExtraEntry(date: extra.dayKey, activity: extra.activity)
                                      : ExtraEntry(date: extra.dayKey, activity: extra.activity, ref: extra.ref)
        entry.what = extra.what
        entry.minutes = extra.minutes
        entry.isTraining = extra.isTraining
        entry.distance = number(extra.distance)
        entry.avgHr = number(extra.avgHr)
        entry.notes = extra.notes
        entry.effort = Double(score)
        editExtra(extra, entry, fields: [ExtraField.effort])
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
        // Since 2.1 the move log of a plan that lives here is part of the plan, so every device reads the same.
        if home == .app, var book {
            book.moves = moves
            save(book)
            return
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
        /* Fitness and fatigue, a day at a time, from the first day of the
           plan to today. Empty when the sheet has no threshold heart rate
           to weigh a session against. */
        let form: [Effort.Form]
    }

    /* Derived here and now from the plan already in memory; nothing cached, nothing written. */
    var progress: Progress? {
        guard let mapping, let view else { return nil }
        let plan = displayed
        let today = self.today
        return Progress(
            summary: Stats.summarise(plan, moves: moves, movesSince: movesSince, today: today, mapping: mapping),
            trends: Stats.trends(Stats.trendRows(plan, mapping)),
            load: Stats.load(Stats.loadRows(plan, mapping), weekStarts: Stats.completedWeekStarts(12, today: today),
                             endExclusive: PlanView.weekStart(today)),
            road: Stats.road(view.visible, today: today, mapping: mapping),
            form: form(plan, view: view, mapping: mapping, today: today))
    }

    /*
     * The two curves. Without a threshold heart rate in the sheet there is
     * nothing to weigh a session against, so nothing is drawn rather than
     * something invented.
     */
    private func form(_ plan: [Workout], view: PlanView, mapping: Mapping, today: String) -> [Effort.Form] {
        guard let lthr = zones?.lthr, let first = plan.first?.dayKey else { return [] }
        let costs = Effort.dailyCost(plan, extras: view.extras, mapping: mapping, lthr: lthr)
        guard !costs.isEmpty else { return [] }
        let from = min(first, costs.keys.min() ?? first)
        return Effort.form(dailyCost: costs, from: from, to: today)
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
        if home == .app { writeHere(); return }
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

    // MARK: - the plan's home in this app (2.0)

    private var supportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    private var bookURL: URL { supportURL.appendingPathComponent("plan.json") }
    /* The workbook exactly as it stood at the switch: the base of every spreadsheet copy, and the road back. */
    private var originalURL: URL { supportURL.appendingPathComponent("plan-original.xlsx") }
    private var backupsURL: URL { supportURL.appendingPathComponent("backups", isDirectory: true) }
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var planLivesHere: Bool { home == .app }

    /* How the plan in iCloud stands on this device; the side list and Settings show it as a dot with its words. */
    @Published var syncStatus: SyncStatus = .off
    /* For three weeks after the switch Excel can become the home again. */
    var canGoBackUntil: Date? { switchedAt.map { $0.addingTimeInterval(21 * 86400) } }
    private var goBackWindowOpen: Bool { home == .app && Device.isPhone && (canGoBackUntil.map { $0 > Date() } ?? false) }
    /* Closed once an iPad or Mac uses the plan too (for good, not only while their files are in view):
       going back would leave them with a plan nobody writes. */
    var canGoBack: Bool { goBackWindowOpen && dropboxPath != nil && Dropbox.shared.isConnected && !planIsShared && cloudChecked }
    var goBackClosed: Bool { goBackWindowOpen && planIsShared }
    /* Not yet known whether an iPad or Mac uses the plan: iCloud not found, or no meeting finished since the app opened. */
    var goBackWaits: Bool { goBackWindowOpen && !planIsShared && !cloudChecked }
    private var cloudChecked: Bool { cloud.root != nil && cloud.lastMet != nil }

    /* Counts every plan put on screen, so a meeting can tell the plan changed while it was joining. */
    private(set) var bookVersion = 0

    private func publish(_ book: PlanBook) {
        bookVersion += 1
        if home == .app { moves = book.moves }
        self.book = book
        plan = book.sessions
        extras = book.extras
        zones = book.zones
        mapping = book.mapping
        fromCache = false
        phase = .ready
        calendarChanged()
    }

    /*
     * On disk first, then on screen — and on screen only if it is on disk.
     * A change the phone could not keep must not look kept: he would train on
     * and lose it at the next launch. The day's first save keeps yesterday's
     * book as a safety copy.
     */
    @discardableResult
    private func save(_ book: PlanBook) -> Bool {
        if book.isFromNewerApp {
            lastProblem = BookError.newerApp.localizedDescription
            return false
        }
        // Every change is marked here, by difference with what was there, so no other place has to
        // remember it — the marks are what decide, when two devices meet, which change is the newer.
        let book = book.stamped(after: self.book ?? book)
        do {
            let data = try book.encoded()
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            keepSafetyCopy()
            try data.write(to: bookURL, options: .atomic)
        } catch {
            lastProblem = "That could not be saved on this phone (\(error.localizedDescription)). Nothing was changed. Free some space and try again."
            return false
        }
        publish(book)
        keepWeeklySpreadsheet(book)
        copyToDropboxSoon()
        cloud.localChanged()
        return true
    }

    private func keepSafetyCopy() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bookURL.path) else { return }
        let copy = backupsURL.appendingPathComponent("plan-\(PlanView.todayKey()).json")
        if fm.fileExists(atPath: copy.path) { return }
        try? fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        try? fm.copyItem(at: bookURL, to: copy)
        let all = ((try? fm.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("plan-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in all.dropLast(30) { try? fm.removeItem(at: old) }
    }

    /* The newest safety copy that still opens: by the moment it was made, as the list orders them
       ("plan-<day>-before-0912" is newer than the start-of-day "plan-<day>", though it sorts before it by name). */
    private func newestSafetyCopy() -> (book: PlanBook, data: Data, day: String)? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? [])
            .filter { $0.hasPrefix("plan-") && $0.hasSuffix(".json") }
            .sorted {
                let a = Store.copyMoment(String($0.dropFirst(5).dropLast(5))), b = Store.copyMoment(String($1.dropFirst(5).dropLast(5)))
                return a != b ? a > b : $0 > $1
            }
        for name in names {
            if let data = try? Data(contentsOf: backupsURL.appendingPathComponent(name)),
               let book = try? PlanBook.decoded(data) {
                return (book, data, String(name.dropFirst(5).dropLast(5)))
            }
        }
        return nil
    }

    /* How many days have a safety copy, and the newest one's day. */
    var safetyCopies: (count: Int, newest: String?) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? [])
            .filter { $0.hasPrefix("plan-") && $0.hasSuffix(".json") }.sorted()
        return (names.count, names.last.map { String($0.dropFirst(5).dropLast(5)) })
    }

    /*
     * Everything waiting is written into the book at once: there is no
     * elsewhere to send it. The waiting list is cleared only after the book
     * is safely on disk; if it is not, every entry stays and nothing is lost.
     */
    private func writeHere() {
        guard var book, !queue.isEmpty else { return }
        var kept: [QueuedEntry] = []
        for var entry in queue {
            do {
                _ = try book.apply(entry)
            } catch {
                entry.attempts += 1
                entry.lastError = error.localizedDescription
                kept.append(entry)
            }
        }
        guard save(book) else { return }
        queue = kept
        saveQueue()
        lastProblem = kept.isEmpty ? nil : "Some logging could not be written — see Settings."
    }

    // MARK: taking the workbook in

    /* Read the workbook afresh, take it in and count both sides. Nothing is saved: he looks first. */
    func takePlanIn() {
        guard !takingIn else { return }
        if !queue.isEmpty {
            homeProblem = "\(queue.count) entr\(queue.count == 1 ? "y is" : "ies are") still waiting for Dropbox. Send \(queue.count == 1 ? "it" : "them") first."
            return
        }
        takingIn = true
        homeProblem = nil
        Task {
            defer { self.takingIn = false }
            do {
                let fresh = try await self.freshWorkbook()
                self.incoming = try PlanImport.read(fresh.data, fileName: fresh.name, today: self.today)
                self.incomingBytes = fresh.data
            } catch {
                self.homeProblem = "The plan could not be taken in just now: \(error.localizedDescription)"
            }
        }
    }

    private func freshWorkbook() async throws -> (data: Data, name: String) {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["AMSWS_FILE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return (data, URL(fileURLWithPath: path).lastPathComponent)
        }
        #endif
        if let path = dropboxPath, Dropbox.shared.isConnected {
            let file = try await Dropbox.shared.download(path)
            rev = file.rev
            return (file.data, file.name.isEmpty ? fileName : file.name)
        }
        if dropboxPath != nil {
            // The plan is in Dropbox and Dropbox cannot be reached: an older
            // copy kept on the phone is not the plan, and is not taken in.
            throw NSError(domain: "AMSWorkoutSync", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Dropbox is not connected. Connect it in Settings, so the newest Excel file is taken in."])
        }
        if let data = try? Data(contentsOf: cacheURL) { return (data, fileName) }
        throw NSError(domain: "AMSWorkoutSync", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "There is no Excel file to take in yet."])
    }

    func cancelTakingIn() {
        incoming = nil
        incomingBytes = nil
        homeProblem = nil
    }

    @Published private(set) var switching = false

    /*
     * The switch. Only on a proof that matches, and only by his tap — and
     * only if the Excel file is still the one that was counted: it is read
     * once more at the tap, and if it has changed (something logged since,
     * or edited on the Mac) it is counted again and shown again instead.
     */
    func makeAppTheHome() {
        guard !switching, let taken = incoming, taken.proof.matches, let bytes = incomingBytes, queue.isEmpty else { return }
        switching = true
        homeProblem = nil
        Task {
            defer { self.switching = false }
            do {
                let fresh = try await self.freshWorkbook()
                guard self.queue.isEmpty else {
                    self.homeProblem = "Something was logged meanwhile and is still on its way to Dropbox. Wait a moment and start again."
                    return
                }
                if fresh.data != bytes {
                    self.incoming = try PlanImport.read(fresh.data, fileName: fresh.name, today: self.today)
                    self.incomingBytes = fresh.data
                    self.homeProblem = "The Excel file changed after it was counted, so it has been counted again. Look at the counts and tap once more."
                    return
                }
            } catch {
                self.homeProblem = "The Excel file could not be read once more just now (\(error.localizedDescription)). Nothing was changed."
                return
            }
            self.finishSwitch(taken, bytes)
        }
    }

    private func finishSwitch(_ taken: PlanImport, _ bytes: Data) {
        let fm = FileManager.default
        var book = taken.book
        book.origin.originalHash = PlanCloud.hash(bytes)
        let carried = carryMoves(&book)
        do {
            try fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
            // A plan already kept here (one that would not open, or from an
            // earlier move) is put aside, never written over.
            if fm.fileExists(atPath: bookURL.path) {
                try? fm.moveItem(at: bookURL, to: supportURL.appendingPathComponent("plan-before-\(Int(Date().timeIntervalSince1970)).json"))
            }
            try bytes.write(to: originalURL, options: .atomic)
            try book.encoded().write(to: bookURL, options: .atomic)
        } catch {
            homeProblem = "The plan could not be saved on this phone: \(error.localizedDescription) Nothing was changed."
            return
        }
        let now = Date()
        UserDefaults.standard.set(Home.app.rawValue, forKey: homeKey)
        UserDefaults.standard.set(now, forKey: "plan.switchedAt")
        switchedAt = now
        home = .app
        incoming = nil
        incomingBytes = nil
        lastProblem = nil
        if carried || UserDefaults.standard.data(forKey: "moveLog") == nil { UserDefaults.standard.set(true, forKey: "moveLog.inBook") }
        publish(book)
        keepWeeklySpreadsheet(book, force: true)
        copyToDropboxSoon()
        cloud.localChanged()
    }

    /*
     * The road back, for three weeks: the plan as it is now is written into
     * the workbook it came from and put back in Dropbox, and Excel is the
     * home again. Refused if the file in Dropbox is no longer the one that
     * was taken in — then two plans have grown apart and choosing between
     * them is his to do, not the app's.
     */
    func goBackToExcel() {
        guard canGoBack, !goingBack, let book, let path = dropboxPath,
              let original = try? Data(contentsOf: originalURL) else { return }
        goingBack = true
        homeProblem = nil
        let startedAt = bookVersion
        Task {
            defer { self.goingBack = false }
            do {
                let bytes = try PlanExport.workbook(book, template: original)
                let there = try await Dropbox.shared.download(path)
                // A meeting landed while the workbook was fetched: the Excel file is not touched with a plan that is no longer the one here.
                guard self.bookVersion == startedAt else {
                    self.homeProblem = "The plan changed while it was being written back. Nothing was switched; try again."
                    return
                }
                // Already written back by an earlier try that was cut short: only the switch is left to do.
                let alreadyThere = there.data == bytes
                guard alreadyThere || there.data == original else {
                    self.homeProblem = "The Excel file in Dropbox changed after the plan moved into the app. Going back would overwrite it, so nothing was done."
                    return
                }
                let uploaded = alreadyThere ? RemoteFile(data: bytes, rev: there.rev, name: there.name)
                                            : try await Dropbox.shared.upload(path, bytes, rev: there.rev)
                guard self.book == book else {
                    self.homeProblem = "The plan changed while it was being written back. Nothing was switched; try again."
                    return
                }
                let aside = self.supportURL.appendingPathComponent("plan-left-\(PlanView.todayKey()).json")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: self.bookURL, to: aside)
                UserDefaults.standard.set(Home.excel.rawValue, forKey: self.homeKey)
                self.home = .excel
                self.book = nil
                await self.cloud.planLeftTheApp()
                self.rev = uploaded.rev
                self.parse(uploaded.data, cached: false)
            } catch {
                self.homeProblem = "Going back did not work just now: \(error.localizedDescription) The plan still lives in this app. Nothing was changed."
            }
        }
    }

    // MARK: a spreadsheet copy

    /* The plan as it is now, as a workbook in the app's own folder in Files. Returns where it is. */
    func spreadsheetCopy() -> URL? {
        guard let book, let original = try? Data(contentsOf: originalURL) else { return nil }
        do {
            let bytes = try PlanExport.workbook(book, template: original)
            let url = documentsURL.appendingPathComponent("Triathlon plan \(PlanView.todayKey()).xlsx")
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            try bytes.write(to: url, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: "plan.lastSpreadsheet")
            return url
        } catch {
            lastProblem = error.localizedDescription
            return nil
        }
    }

    var lastSpreadsheetCopy: Date? { UserDefaults.standard.object(forKey: "plan.lastSpreadsheet") as? Date }

    /* Once a week by itself; the newest eight are kept. */
    private func keepWeeklySpreadsheet(_ book: PlanBook, force: Bool = false) {
        if !force, let last = lastSpreadsheetCopy, Date().timeIntervalSince(last) < 7 * 86400 { return }
        guard spreadsheetCopy() != nil else { return }
        let fm = FileManager.default
        let all = ((try? fm.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Triathlon plan ") && $0.pathExtension == "xlsx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in all.dropLast(8) { try? fm.removeItem(at: old) }
    }

    // MARK: a copy outside this phone

    /*
     * While Dropbox is still connected, the plan is also kept there as a
     * spreadsheet beside the workbook it came from — a copy outside this
     * phone, so a lost or broken phone does not take the plan with it. The
     * app writes it and never reads it; the original workbook is not touched.
     */
    @Published private(set) var copiedToDropboxAt: Date? = UserDefaults.standard.object(forKey: "plan.lastDropboxCopy") as? Date
    @Published private(set) var dropboxCopyProblem: String?
    private var copyOwed = UserDefaults.standard.bool(forKey: "plan.copyOwed") {
        didSet { UserDefaults.standard.set(copyOwed, forKey: "plan.copyOwed") }
    }
    private var copying = false

    static let dropboxCopyName = "Triathlon plan from the app.xlsx"

    var dropboxCopyPath: String? {
        guard let path = dropboxPath, let slash = path.lastIndex(of: "/") else { return nil }
        return String(path[..<slash]) + "/" + Store.dropboxCopyName
    }

    /* A little after the last change, so a burst of taps makes one copy. */
    private func copyToDropboxSoon() {
        copyOwed = true
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            self.copyToDropboxNow()
        }
    }

    func copyToDropboxNow() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_FILE"] != nil { return }
        #endif
        // The iPhone alone writes the spreadsheet copy to Dropbox: from three devices it would be overwritten in turns.
        guard Device.isPhone, home == .app, copyOwed, !copying, let book, let target = dropboxCopyPath, Dropbox.shared.isConnected,
              let original = try? Data(contentsOf: originalURL) else { return }
        copying = true
        copyOwed = false
        Task {
            defer { self.copying = false }
            do {
                let bytes = try PlanExport.workbook(book, template: original)
                try await Dropbox.shared.uploadCopy(target, bytes)
                let now = Date()
                self.copiedToDropboxAt = now
                UserDefaults.standard.set(now, forKey: "plan.lastDropboxCopy")
                self.dropboxCopyProblem = nil
            } catch {
                // Still owed: tried again the next time the app comes to the front.
                self.copyOwed = true
                self.dropboxCopyProblem = error.localizedDescription
            }
        }
    }

    // MARK: tests and zones

    /* The test blocks, in order. Empty until the plan lives here. */
    var tests: [TestResult] { book?.tests ?? [] }

    /* A test's numbers entered in the app; the zones follow the last numbers there are. */
    @discardableResult
    func recordTest(_ test: TestResult) -> Bool {
        guard var book else { return false }
        book.record(test)
        return save(book)
    }

    // MARK: putting a safety copy back

    /*
     * Every safety copy, newest first, by a name the list understands:
     *   "2026-11-25"                 the plan at the start of that day (plan-2026-11-25.json)
     *   "2026-11-25-before-0912"     just before a copy was put back at 09:12
     *   "before-merge-2026-11-25-091200-from-mac-took"   before a meeting with iCloud took something out
     *   "other-plan-2026-11-25-091200"                   the plan put aside when he chose the other of two
     */
    var safetyCopyDays: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? []
        var ids: [String] = []
        for name in names where name.hasSuffix(".json") {
            let bare = String(name.dropLast(5))
            if name.hasPrefix("plan-") { ids.append(String(bare.dropFirst(5))) }
            else if name.hasPrefix("before-merge-") && name.hasSuffix("-took.json") { ids.append(bare) }
            else if name.hasPrefix("other-plan-") { ids.append(bare) }
        }
        return ids.sorted { Store.copyMoment($0) != Store.copyMoment($1) ? Store.copyMoment($0) > Store.copyMoment($1) : $0 > $1 }
    }

    /* "yyyy-MM-dd-HHmmss" of a safety copy's name, for the order of the list. */
    static func copyMoment(_ id: String) -> String {
        for prefix in ["before-merge-", "other-plan-"] where id.hasPrefix(prefix) { return String(id.dropFirst(prefix.count).prefix(17)) }
        if let r = id.range(of: "-before-") { return String(id[..<r.lowerBound]) + "-" + String(id[r.upperBound...]).prefix(4) + "00" }
        return String(id.prefix(10)) + "-000000"
    }

    private func copyURL(_ id: String) -> URL {
        id.hasPrefix("before-merge-") || id.hasPrefix("other-plan-")
            ? backupsURL.appendingPathComponent(id + ".json")
            : backupsURL.appendingPathComponent("plan-\(id).json")
    }

    /* What a safety copy holds, for the list: nil if it will not open. */
    func safetyCopySummary(_ day: String) -> (sessions: Int, done: Int, changes: Int)? {
        guard let data = try? Data(contentsOf: copyURL(day)),
              let copy = try? PlanBook.decoded(data) else { return nil }
        let done = copy.sessions.filter { $0.discipline.id != "rest" && $0.loggedInSheet && !$0.missed }.count
        return (copy.trainingCount, done, copy.changes.count)
    }

    /* Another device has met this plan in iCloud (now or ever): a copy put back then keeps what was logged since. */
    var planIsShared: Bool { UserDefaults.standard.bool(forKey: PlanCloud.sharedKey) || cloud.otherDevicesUsePlan }

    /*
     * The plan as it was at the start of that day, put back. The plan as it
     * is now is kept beside it first (plan-before-restore-…), so putting a
     * copy back can itself be put right.
     *
     * Not shared: the whole copy, marked as a change made now. Shared with
     * other devices: only the plan's own side goes back (days, words,
     * lengths, which sessions are in it) and what he logged since the copy
     * stays — else putting an old copy back on one device would take those
     * logs out on every device (PlanBook.putBack).
     */
    @discardableResult
    func restoreSafetyCopy(_ day: String) -> Bool {
        guard home == .app, !goingBack else {
            lastProblem = "A safety copy can be put back only while the plan lives in this app. Nothing was changed."
            return false
        }
        guard let old = (try? Data(contentsOf: copyURL(day))).flatMap({ try? PlanBook.decoded($0) }),
              !old.isFromNewerApp else {
            lastProblem = "That safety copy could not be opened. Nothing was changed."
            return false
        }
        let current = book ?? old
        let copy: PlanBook
        if !BookMerge.samePlan(old, current) {
            // The other of two plans: put back whole, with its own marks; iCloud then asks which plan to keep.
            copy = old
        } else if planIsShared, let kept = PlanBook.putBack(old, over: current) {
            copy = kept
        } else {
            // Marked as a change made now, so on the other devices it wins over what came after the copy —
            // which is what putting it back means. What it takes out gets a removed mark the same way.
            copy = old.stamped(after: current)
        }
        guard let data = try? copy.encoded() else {
            lastProblem = "That safety copy could not be opened. Nothing was changed."
            return false
        }
        let fm = FileManager.default
        // The plan as it is now goes into the list of safety copies too, under
        // today's day and the time, so putting the wrong copy back can be put
        // right from the same page. (Today's own copy is filed first if this is
        // the day's first change.)
        keepSafetyCopy()
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX"); clock.dateFormat = "HHmm"
        let aside = backupsURL.appendingPathComponent("plan-\(PlanView.todayKey())-before-\(clock.string(from: Date())).json")
        do {
            try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            if fm.fileExists(atPath: bookURL.path) {
                if fm.fileExists(atPath: aside.path) { try fm.removeItem(at: aside) }
                try fm.copyItem(at: bookURL, to: aside)
            }
            try data.write(to: bookURL, options: .atomic)
        } catch {
            lastProblem = "The safety copy could not be put back (\(error.localizedDescription)). Nothing was changed."
            return false
        }
        publish(copy)
        // Logging that was still waiting never reached the plan, so it is in no
        // copy: it is written into the plan that was put back, not thrown away.
        if !queue.isEmpty { writeHere() }
        keepWeeklySpreadsheet(copy)
        copyToDropboxSoon()
        cloud.localChanged()
        return true
    }

#if DEBUG
    /* Picture switch (AMSWS_FAKE_DONE): every planned session before today is logged as done, a little short of its plan; every sixth is marked missed. Once. */
    func debugSeedDone() {
        guard queue.isEmpty, let mapping else { return }
        var n = 0
        for w in displayed where w.dayKey < today && w.discipline.id != "rest" && !w.logged {
            guard let seconds = Plan.plannedSeconds(w, mapping), seconds > 0 else { continue }
            n += 1
            var e = LogEntry()
            if n % 6 == 0 { e.missed = true } else {
                e.actualDuration = String(Int(seconds / 60 * (n % 3 == 0 ? 1.1 : 0.95)))
                let km: Double? = ["run": 8.0, "bike": 42.0, "swim": 1.5].first(where: { w.discipline.id.lowercased().contains($0.key) })?.value
                if let km { e.actualDistance = String(mapping.units.distance == "m" ? km * 1000 : km) }
                e.avgHr = String(132 + n % 9); e.rpe = String(4 + n % 3)
            }
            queue.append(QueuedEntry(workout: w, entry: e))
        }
    }
#endif

#if DEBUG
    /* Picture and screen-test switch only: make sure two safety copies exist (the plan as it is, filed under the two days before today). */
    func debugSeedSafetyCopies() {
        let fm = FileManager.default
        let onDisk = fm.fileExists(atPath: bookURL.path)
        // Picture mode keeps the plan in memory only: then the copies are written from it.
        guard onDisk || book != nil, safetyCopyDays.count < 2 else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let now = f.date(from: today) else { return }
        try? fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        for back in 1...2 {
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: now) else { continue }
            let copy = backupsURL.appendingPathComponent("plan-\(f.string(from: d)).json")
            guard !fm.fileExists(atPath: copy.path) else { continue }
            if onDisk { try? fm.copyItem(at: bookURL, to: copy) }
            else if let data = try? book?.encoded() { try? data.write(to: copy) }
        }
    }
#endif

    // MARK: iCloud (2.1)

    /* What this device does when it meets iCloud. */
    enum CloudRole {
        /* The plan lives here: it meets iCloud's plan (the book and the version on screen). */
        case member(PlanBook, Int)
        /* No plan at all on this device: it takes iCloud's, without asking — there is nothing to lose. */
        case empty
        /* The plan lives in Excel here: nothing of the plan is shared; the move-in page offers iCloud's. */
        case excel
        /* Moving in, going back, or a plan here that would not open: the plan waits. */
        case busy
    }

    var cloudRole: CloudRole {
        if takingIn || switching || goingBack { return .busy }
        if home == .app {
            guard let book, !book.isFromNewerApp else { return .busy }
            return .member(book, bookVersion)
        }
        return hasNoPlanAtAll ? .empty : .excel
    }

    /* Nothing of a plan on this device: no book, no workbook read or chosen, nothing waiting. */
    var hasNoPlanAtAll: Bool {
        book == nil && plan.isEmpty && queue.isEmpty && dropboxPath == nil
            && UserDefaults.standard.data(forKey: bookmarkKey) == nil
            && !FileManager.default.fileExists(atPath: cacheURL.path)
            && !FileManager.default.fileExists(atPath: bookURL.path)
    }

    var beforeICloudURL: URL { supportURL.appendingPathComponent("Before iCloud", isDirectory: true) }
    var originalFileURL: URL { originalURL }
    var hasOriginal: Bool { FileManager.default.fileExists(atPath: originalURL.path) }

    private static func stampNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    /*
     * Before this device meets iCloud for the first time: the plan, the diary
     * and anything waiting, copied into "Before iCloud" and never pruned. False
     * only if a file that exists could not be copied (no room): then iCloud
     * waits rather than go ahead without it.
     */
    func keepBeforeICloud() -> Bool {
        let fm = FileManager.default
        let stamp = Store.stampNow()
        do {
            try fm.createDirectory(at: beforeICloudURL, withIntermediateDirectories: true)
            for (from, name) in [(bookURL, "plan"), (supportURL.appendingPathComponent("diary.json"), "diary"), (queueURL, "waiting"), (supportURL.appendingPathComponent("shelf.json"), "shelf")] {
                guard fm.fileExists(atPath: from.path) else { continue }
                try fm.copyItem(at: from, to: beforeICloudURL.appendingPathComponent("\(name)-\(stamp).json"))
            }
            return true
        } catch {
            return false
        }
    }

    /* The plan copy from before iCloud, for "Copy from before iCloud" on the iCloud page. */
    var beforeICloudCopy: URL? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: beforeICloudURL.path)) ?? [])
            .filter { $0.hasPrefix("plan-") && $0.hasSuffix(".json") }.sorted()
        return names.first.map { beforeICloudURL.appendingPathComponent($0) }
    }

    /* A file from iCloud that could not be read: its bytes are kept here before anything is written over it. */
    func parkFromICloud(_ data: Data, name: String) {
        let folder = supportURL.appendingPathComponent("From iCloud unreadable", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent("\(Store.stampNow()) \(name)"), options: .atomic)
    }

    /* A whole plan kept among the safety copies (the one not chosen of two), so it can be put back from the app. Never pruned. */
    func keepAside(_ book: PlanBook, as name: String, tail: String) {
        try? FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        try? book.encoded().write(to: backupsURL.appendingPathComponent("\(name)-\(Store.stampNow())-\(tail).json"), options: .atomic)
    }

    /*
     * Before a plan joined with iCloud's replaces the one here: a copy of the
     * one here. Newest 20 kept; the copies from meetings that took something
     * away from this device ("-took") are counted apart, so twenty quiet
     * meetings cannot push them out.
     */
    private func keepBeforeMerge(took: Bool, from: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bookURL.path) else { return true }
        do {
            try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            // "-from-mac-took": whose changes came in, for the words in the list of safety copies.
            let who = from.replacingOccurrences(of: "your ", with: "").replacingOccurrences(of: " ", with: "_").lowercased()
            let name = "before-merge-\(Store.stampNow())\(took ? "-from-\(who)-took" : "").json"
            let to = backupsURL.appendingPathComponent(name)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: bookURL, to: to)
        } catch {
            return false
        }
        let all = ((try? fm.contentsOfDirectory(atPath: backupsURL.path)) ?? []).filter { $0.hasPrefix("before-merge-") }.sorted()
        for group in [all.filter { $0.hasSuffix("-took.json") }, all.filter { !$0.hasSuffix("-took.json") }] {
            for old in group.dropLast(20) { try? fm.removeItem(at: backupsURL.appendingPathComponent(old)) }
        }
        return true
    }

    /*
     * The plan joined with iCloud's, put in place here — only if the plan here
     * is still the one that was joined (else the meeting joins again), and
     * only after a safety copy. On disk first, then on screen. Not marked:
     * its marks came with it.
     */
    func takeFromCloud(_ joined: PlanBook, takenAway: [String], version: Int, from: String) -> Bool {
        guard home == .app, version == bookVersion, !joined.isFromNewerApp, !goingBack else { return false }
        keepSafetyCopy()
        guard keepBeforeMerge(took: !takenAway.isEmpty, from: from) else {
            lastProblem = "No room for a safety copy, so the plan from your other devices was not put in place. Nothing was changed."
            return false
        }
        do {
            try joined.encoded().write(to: bookURL, options: .atomic)
        } catch {
            lastProblem = "The plan from your other devices could not be saved on this \(Device.word) (\(error.localizedDescription)). Nothing was changed."
            return false
        }
        publish(joined)
        // Logging that could not be written before (its session may have come back) is tried again.
        if !queue.isEmpty { writeHere() }
        keepWeeklySpreadsheet(joined)
        copyToDropboxSoon()
        return true
    }

    /* A device with no plan of its own takes iCloud's. */
    func adoptFromCloud(_ cloudBook: PlanBook) -> Bool {
        guard hasNoPlanAtAll, !cloudBook.isFromNewerApp else { return false }
        return makeHome(cloudBook)
    }

    /*
     * An iPad or Mac that only shows an old workbook: iCloud's plan becomes the
     * plan here, exactly as on the iPhone's move-in page (anything waiting is
     * written into it). The workbook's copy on this device is left where it is.
     */
    func adoptOverOldWorkbook(_ cloudBook: PlanBook) -> Bool {
        guard PlanMeeting.takesCloudPlanOverWorkbook(isPhone: Device.isPhone, cloudHasPlan: true) else { return false }
        return useCloudPlan(cloudBook)
    }

    /* The iPhone on Excel, on the move-in page: iCloud's plan becomes the plan here; what waits is written into it. */
    func useCloudPlan(_ cloudBook: PlanBook) -> Bool {
        guard home == .excel, !takingIn, !switching, !cloudBook.isFromNewerApp else { return false }
        homeProblem = nil
        incoming = nil
        incomingBytes = nil
        var book = cloudBook
        let carried = carryMoves(&book)
        guard makeHome(book) else { return false }
        if carried { UserDefaults.standard.set(true, forKey: "moveLog.inBook") }
        if !queue.isEmpty { writeHere() }
        return true
    }

    /* He chose iCloud's plan over the one here (TwoPlansView); the one here was kept aside first. */
    func replaceWithCloudPlan(_ cloudBook: PlanBook) -> Bool {
        guard home == .app, !cloudBook.isFromNewerApp else { return false }
        let fm = FileManager.default
        if fm.fileExists(atPath: originalURL.path) {
            try? fm.createDirectory(at: beforeICloudURL, withIntermediateDirectories: true)
            try? fm.moveItem(at: originalURL, to: beforeICloudURL.appendingPathComponent("other-plan-original-\(Store.stampNow()).xlsx"))
        }
        return makeHome(cloudBook)
    }

    private func makeHome(_ book: PlanBook) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
            if fm.fileExists(atPath: bookURL.path) {
                keepSafetyCopy()
                try? fm.moveItem(at: bookURL, to: supportURL.appendingPathComponent("plan-before-\(Int(Date().timeIntervalSince1970)).json"))
            }
            try book.encoded().write(to: bookURL, options: .atomic)
        } catch {
            homeProblem = "The plan from iCloud could not be saved on this \(Device.word): \(error.localizedDescription) Nothing was changed."
            return false
        }
        UserDefaults.standard.set(Home.app.rawValue, forKey: homeKey)
        let at = book.origin.takenAt
        UserDefaults.standard.set(at, forKey: "plan.switchedAt")
        switchedAt = at
        home = .app
        lastProblem = nil
        publish(book)
        return true
    }

    /* The frozen workbook, fetched from iCloud by a device that did not make the switch. */
    func saveOriginal(_ data: Data) {
        guard !FileManager.default.fileExists(atPath: originalURL.path) else { return }
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try? data.write(to: originalURL, options: .atomic)
    }

    /* The move log of the Excel days goes into the book: a move the book does not know yet. */
    private func carryMoves(_ book: inout PlanBook) -> Bool {
        guard !UserDefaults.standard.bool(forKey: "moveLog.inBook"),
              let data = UserDefaults.standard.data(forKey: "moveLog"),
              let old = try? JSONDecoder().decode([String: MoveRecord].self, from: data) else { return false }
        var changed = false
        for (key, move) in old where book.moves[key] == nil {
            book.moves[key] = move
            changed = true
        }
        return changed
    }

    /* Once, on opening a plan that lives here: the move log, and the mark of the workbook it came from. */
    private func carryIntoBook(_ book: inout PlanBook) -> Bool {
        var changed = carryMoves(&book)
        if book.origin.originalHash == nil, let data = try? Data(contentsOf: originalURL) {
            book.origin.originalHash = PlanCloud.hash(data)
            changed = true
        }
        return changed
    }

    // MARK: changing the plan itself

    /* Several sessions added in one go — one save, so it is all of them or none. Returns how many. */
    @discardableResult
    func addSessions(_ drafts: [SessionDraft], why: String) -> Int {
        guard var book, !drafts.isEmpty else { return 0 }
        do {
            // The Thursday rides have one name per week on every device: added on two at once, they are one ride.
            for draft in drafts {
                try book.add(draft, why: why, fixedKey: why == ThursdayRides.why ? ThursdayRides.key(for: draft) : nil)
            }
            return save(book) ? drafts.count : 0
        } catch {
            lastProblem = error.localizedDescription
            return 0
        }
    }


    /* Sessions can be changed, added and taken out only once the plan lives here. */
    var canChangePlan: Bool { home == .app && book != nil && !goingBack }

    func draft(of key: String) -> SessionDraft? { book?.draft(of: key) }

    /* Newest first. */
    var planChanges: [PlanChange] { (book?.changes ?? []).reversed() }

    /* Only the newest change to a session can be undone. */
    func canUndo(_ id: String) -> Bool { book?.canUndo(id) ?? false }

    @discardableResult
    func changeSession(_ key: String, to draft: SessionDraft) -> PlanChange? {
        guard var book, let was = book.session(key) else { return nil }
        do {
            guard let change = try book.change(key, to: draft) else { return nil }
            guard save(book) else { return nil }
            if draft.dayKey != was.dayKey { rememberMove(was, to: draft.dayKey) }
            return change
        } catch {
            lastProblem = error.localizedDescription
            return nil
        }
    }

    /* A session dragged to another day on the week board: the same change as the Change page makes, with only the day new. */
    @discardableResult
    func moveSession(_ key: String, to day: String) -> PlanChange? {
        guard var draft = draft(of: key), draft.dayKey != day else { return nil }
        draft.dayKey = day
        return changeSession(key, to: draft)
    }

    @discardableResult
    func addSession(_ draft: SessionDraft) -> Workout? {
        guard var book else { return nil }
        do {
            let made = try book.add(draft)
            return save(book) ? made : nil
        } catch {
            lastProblem = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func removeSession(_ key: String) -> PlanChange? {
        guard var book else { return nil }
        do {
            let change = try book.remove(key)
            return save(book) ? change : nil
        } catch {
            lastProblem = error.localizedDescription
            return nil
        }
    }

    func undoChange(_ id: String) {
        guard var book else { return }
        do {
            try book.undo(id)
            save(book)
        } catch {
            lastProblem = error.localizedDescription
        }
    }

    // MARK: a suggestion he took (rule book)

    /*
     * A taken card's moves, written as ordinary changes with one why-line, in
     * one save. `first` hears the changes' ids before the plan is written and
     * may stop it (the suggestion log must be saved first). Returns the ids,
     * [] when nothing would change (nothing is written then), nil when stopped.
     */
    func applySuggestion(_ moves: [Move], input: RuleBookInput, why: String, first: ([String]) -> Bool) -> [String]? {
        guard canChangePlan, var book else { return nil }
        do {
            let ids = try SuggestionApply.take(moves, input: input, to: &book, why: why)
            guard !ids.isEmpty else { return [] }
            guard first(ids) else { return nil }
            return save(book) ? ids : nil
        } catch {
            lastProblem = error.localizedDescription
            return nil
        }
    }

    /* One Undo for the whole card. */
    func undoSuggestion(_ ids: [String]) -> Bool {
        guard var book else { return false }
        do {
            try SuggestionApply.undo(ids, in: &book)
            return save(book)
        } catch {
            lastProblem = error.localizedDescription
            return false
        }
    }
}
