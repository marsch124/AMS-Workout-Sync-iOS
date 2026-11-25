import Foundation
import SwiftUI
import Combine
import WorkoutCore

/*
 * The app's side of the rule book: it builds what the engine reads from the
 * plan, the morning answers and his own taps; asks for a card when Today
 * appears, after the morning answer and after a session is logged; keeps
 * every card and his answer in suggestions.json; and writes a card he takes
 * into the plan through the Store, so it lands in "Changes to the plan" with
 * a why-line and one Undo.
 *
 * The app suggests, he decides: nothing in the plan moves without his tap.
 * One card a day at most, and only once the plan lives in this app. Cards
 * are made on the iPhone only: the log is kept on each device, and two
 * devices each making their own card would make two.
 *
 * A log or week-cap file that cannot be read means nothing is shown — never
 * a guess — and the file is left exactly as it was.
 */
@MainActor
final class SuggestionKeeper: ObservableObject {
    static let shared = SuggestionKeeper()

    /* The words he reads when a card no longer fits, and when its notes cannot be read. */
    static let staleWords = "The plan has changed since this suggestion, so it was put away."
    static let unreadableWords = "The suggestions\u{2019} own notes could not be read, so suggestions are resting. Your plan is untouched."
    static let goneWords = "This change is no longer in your plan."
    static let changedAgainWords = "This session was changed again since, so nothing was undone."

    /* One calm grey line where the card was, for the rest of the day. */
    struct Notice: Equatable {
        let day: String
        let text: String
        let id: String
    }

    @Published private(set) var keep = SuggestionKeep()
    /* False when suggestions.json is there but cannot be read: then nothing is shown or written. */
    @Published private(set) var readable = true
    @Published private(set) var notice: Notice?

    private weak var store: Store?
    private var bag: Set<AnyCancellable> = []
    private var loggedToday: Int?
    /* weekCap[w] of the plan as taken in, frozen once per plan (its taken-in moment beside it). */
    private var caps: [Int: Int]?
    private var capsFor: Double?
    @Published private(set) var capsUnreadable = false
    /* The engine's view of the plan, kept per plan version: rebuilt only when the plan changes. */
    private var cached: (key: String, input: RuleBookInput)?
    /* The last check asked, so Today appearing again with nothing new runs nothing. */
    private var lastCheck: String?
    /* A tap on "Take it" being written: a second one meanwhile is ignored. */
    private var taking = false

    private var supportURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    private var fileURL: URL { supportURL.appendingPathComponent("suggestions.json") }
    private var capsURL: URL { supportURL.appendingPathComponent("rulebook-caps.json") }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_RESET"] != nil {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: capsURL)
        }
        #endif
        if let data = try? Data(contentsOf: fileURL) {
            if let kept = try? SuggestionKeep.decoded(data) { keep = kept } else { readable = false }
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            readable = false
        }
    }

    /* Once, from the root view. */
    func attach(_ store: Store) {
        guard self.store !== store else { return }
        self.store = store
        store.$book
            .sink { [weak self] book in
                // Published before it is set: read the new value, ask a moment later.
                guard let self, let book else { return }
                let today = store.today
                let count = book.sessions.filter { $0.dayKey == today && $0.logged }.count
                let before = self.loggedToday
                self.loggedToday = count
                if let before, count > before {
                    DispatchQueue.main.async { self.check(.afterSession) }
                } else if before == nil {
                    // The plan has just been read: Today is on screen.
                    DispatchQueue.main.async { self.todayAppeared() }
                }
            }
            .store(in: &bag)
        Diary.shared.$feel
            .dropFirst()
            .sink { [weak self] feel in
                guard let self, let store = self.store, feel.answer(on: store.today) != nil else { return }
                DispatchQueue.main.async { self.check(.morning) }
            }
            .store(in: &bag)
        // Back to the front in the morning with Today already open: it does not "appear" again.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.todayAppeared() }
            .store(in: &bag)
    }

    var today: String { store?.today ?? PlanView.todayKey() }

    /* The notes read, both of them. */
    var notesReadable: Bool { readable && !capsUnreadable }

    // MARK: when a card may be made and shown

    /* The plan lives here, the switch is on, the file reads. */
    var planReady: Bool {
        guard readable, keep.isOn, let store else { return false }
        return store.canChangePlan
    }

    /* Cards: the same, and on the iPhone. */
    var cardsOn: Bool {
        #if DEBUG
        if debugMode != nil { return readable }
        #endif
        return planReady && Device.isPhone
    }

    /* No card at all while paused or resting after an illness. */
    private var quiet: Bool { ladder.step == .paused || ladder.step == .rest }

    /* The card waiting for his answer. */
    var card: SuggestionEntry? { cardsOn && !quiet ? keep.openEntry(on: today) : nil }

    /* A card taken today: "Changed — Undo" in its place until the day ends. */
    var changed: SuggestionEntry? { cardsOn ? keep.changedEntry(on: today) : nil }

    /* The calm line where a card was put away or could not be undone, today only. */
    var todaysNotice: Notice? { notice.flatMap { $0.day == today ? $0 : nil } }

    /* Today appeared: the morning check runs once he has answered, or from 07:00; Sunday evening is the plan review's. */
    func todayAppeared() {
        #if DEBUG
        debugSeed()
        #endif
        let hour = Calendar.current.component(.hour, from: Date())
        let sunday = utc.component(.weekday, from: parseDayKey(today) ?? Date()) == 1
        if sunday && hour >= 18 {
            check(.evening)
        } else if Diary.shared.feel.answer(on: today) != nil || hour >= 7 {
            check(.morning)
        } else {
            revalidate()
        }
    }

    /* A version of the plan that changes with every change and every log (the book's own marks). */
    private func version(_ book: PlanBook) -> String {
        let newest = book.stamps.values.max()?.timeIntervalSince1970 ?? 0
        return "\(book.origin.takenAt.timeIntervalSince1970)|\(book.changes.count)|\(book.stamps.count)|\(newest)|\(book.sessions.count)|\(book.extras.count)"
    }

    func check(_ moment: RBMoment) {
        guard cardsOn, planReady, let store, let book = store.book else { return }
        let key = [moment.rawValue, today, version(book), String(describing: Diary.shared.feel.answer(on: today)),
                   String(describing: keep.health), "\(keep.hurtDays.count)|\(keep.entries.count)|\(keep.isOn)",
                   String(describing: keep.settings), "\(Diary.shared.found.count)"].joined(separator: "#")
        guard key != lastCheck else { return }
        lastCheck = key
        let was = keep
        belongToPlan(book)
        keep.closeStale(today: today)
        revalidate(save: false)
        if keep.openEntry(on: today) == nil, keep.mayShowNew(on: today) || keep.mayShowNew(on: today, trigger: .section5),
           let input = input(moment), let s = RuleBook.suggest(input) {
            if keep.add(SuggestionEntry(s, input: input), today: today) { askClaude(s, input: input) }
        }
        if keep != was { save() }
    }

    // MARK: Claude's pick (Settings → Claude)

    /*
     * Right after the rule book has made a card, and only when Claude is on and
     * has a key: ask it to pick from that SAME menu. The card is shown at once
     * with the rule book's own pick; the answer, if a valid one comes back while
     * the card is still open and unchanged, replaces it. Any failure leaves the
     * card as it is. The ask is written into Claude's own log by the client.
     */
    private func askClaude(_ s: Suggestion, input: RuleBookInput) {
        let client = ClaudeClient.shared
        guard client.isOn, s.review == nil, !quiet, let book = store?.book,
              let asked = keep.askable(on: today, ladder: ladder.step), asked.id == s.record.id,
              asked.record.choices == s.record.choices else { return }
        keep.markAsked(asked.id)
        let context = ClaudeContext.make(from: input)
        let planVersion = version(book)
        // Started on the main actor, so the answer is handled there too.
        Task { @MainActor [weak self] in
            let answer = await client.pick(for: s, context: context)
            self?.claudeAnswered(answer, to: asked, planVersion: planVersion)
        }
    }

    /* Used only if nothing moved meanwhile: same day, same plan, same card, no pause. */
    private func claudeAnswered(_ answer: ClaudeAnswer?, to asked: SuggestionEntry, planVersion: String) {
        guard readable, cardsOn, !quiet, ladder.step == .none, let answer, let book = store?.book,
              version(book) == planVersion, let input = input(.afterSession) else { return }
        if keep.applyClaude(answer, to: asked, on: today, input: input) { save() }
    }

    /* A new plan taken in: these notes start a fresh log (his answers and taps stay). */
    private func belongToPlan(_ book: PlanBook) {
        if keep.belong(to: book.origin.takenAt.timeIntervalSince1970) { cached = nil }
    }

    /*
     * The open card, checked against the plan as it is now (app back to the
     * front, the plan changed): one that no longer fits is put away quietly.
     */
    func revalidate(save shouldSave: Bool = true) {
        guard readable, let entry = keep.openEntry(on: today), !entry.isReview, entry.record.choice(0)?.isEmpty == false,
              let input = input(.afterSession) else { return }
        guard !SuggestionApply.fits(entry, choice: 0, input: input) else { return }
        keep.putAway(entry.id, .planChanged, on: today)
        if shouldSave { save() }
    }

    // MARK: what the engine reads

    func input(_ moment: RBMoment) -> RuleBookInput? {
        guard let store, let book = store.book, store.canChangePlan else { return nil }
        let key = version(book) + "|" + store.today + "|" + String(describing: keep.settings) + "|\(Diary.shared.found.count)"
        var base: RuleBookInput
        if let cached, cached.key == key {
            base = cached.input
        } else {
            guard let frozen = frozenCaps(book, today: store.today) else { return nil }
            base = RuleBook.input(book: book, extras: watchHikes(book), today: store.today,
                                  weekCaps: RuleBook.weekCaps(frozen: frozen, book: book, today: store.today),
                                  importDay: PlanView.todayKey(book.origin.takenAt), settings: keep.settings)
            cached = (key, base)
        }
        base.feel = Diary.shared.feel
        base.moment = moment
        base.log = keep.log
        base.health = keep.health
        base.hurtDays = keep.hurtDays
        return base
    }

    /*
     * Hikes and walks of 30 minutes or more from the watch, as the Load card
     * already keeps them, so a hiking week is not read as days off. One he
     * wrote in as an extra that day already counts and is not counted twice.
     */
    private func watchHikes(_ book: PlanBook) -> [RBExtra] {
        let written = Set(book.extras.filter { ["hike", "walk"].contains($0.activity) }
            .compactMap { parseDayKey($0.date).flatMap(dayKey) })
        return Diary.shared.found.filter { ["hike", "walk"].contains($0.sport) && $0.minutes >= 30 && !written.contains($0.dayKey) }
            .map { RBExtra(day: $0.dayKey, activity: "hike", minutes: Int($0.minutes.rounded()), countsAsTraining: true) }
    }

    private struct CapsFile: Codable {
        var takenAt: Double
        var caps: [String: Int]
    }

    /* The caps of the plan as taken in, frozen once per plan; a new plan freezes afresh. */
    private func frozenCaps(_ book: PlanBook, today: String) -> [Int: Int]? {
        let stamp = book.origin.takenAt.timeIntervalSince1970
        if let caps, capsFor == stamp { return caps }
        if capsUnreadable { return nil }
        if let data = try? Data(contentsOf: capsURL) {
            if let file = try? JSONDecoder().decode(CapsFile.self, from: data) {
                if file.takenAt == stamp {
                    caps = Dictionary(uniqueKeysWithValues: file.caps.compactMap { k, v in Int(k).map { ($0, v) } })
                    capsFor = stamp
                    return caps
                }
                // Another plan's caps: freeze this one's below.
            } else if (try? JSONDecoder().decode([String: Int].self, from: data)) == nil {
                capsUnreadable = true
                return nil
            }
        } else if FileManager.default.fileExists(atPath: capsURL.path) {
            capsUnreadable = true
            return nil
        }
        let fresh = RuleBook.takenInCaps(book, today: today)
        let file = CapsFile(takenAt: stamp, caps: Dictionary(uniqueKeysWithValues: fresh.map { (String($0.key), $0.value) }))
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: capsURL, options: .atomic)
        } catch {
            return nil
        }
        caps = fresh
        capsFor = stamp
        return fresh
    }

    @discardableResult
    private func save() -> Bool {
        guard readable, let data = try? keep.encoded() else { return false }
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: his answer

    /* "Take it" (0) or one of the other choices (1, 2). */
    func take(_ index: Int) {
        guard !taking, readable, let entry = card, let moves = entry.record.choice(index), let store, let book = store.book else { return }
        taking = true
        defer { taking = false }
        guard !moves.isEmpty else {
            keep.answer(entry.id, .took(index), on: today)
            save()
            return
        }
        let line = headline(entry, index)
        guard let input = input(.afterSession), SuggestionApply.fits(entry, choice: index, input: input),
              !SuggestionApply.alreadyInPlan(entry, headline: line, book: book) else {
            putAway(entry)
            return
        }
        let before = keep
        var logged = false
        let made = store.applySuggestion(moves, input: input, why: SuggestionApply.why(line)) { ids in
            // The log first: a plan changed by a card the log does not know of could be taken again.
            keep.answer(entry.id, .took(index), on: today, changeIDs: ids)
            logged = save()
            if !logged { keep = before }
            return logged
        }
        if made == nil, logged {
            // The plan could not be saved: the card is open again, as it was.
            keep.unanswer(entry.id)
            save()
        } else if made?.isEmpty == true {
            putAway(entry)
        }
    }

    /* Nothing written: the card goes, with one calm grey line in its place. */
    private func putAway(_ entry: SuggestionEntry) {
        keep.putAway(entry.id, .planChanged, on: today)
        save()
        notice = Notice(day: today, text: Self.staleWords, id: "suggestion-stale")
    }

    func keepPlan() {
        guard readable, let entry = card else { return }
        keep.answer(entry.id, .keptPlan, on: today)
        save()
    }

    func undo() {
        guard readable, let entry = changed, let store else { return }
        if !entry.changeIDs.isEmpty {
            guard let book = store.book else { return }
            let live = SuggestionApply.liveIDs(entry.changeIDs, in: book)
            if live.isEmpty {
                // Put back already (Changes to the plan, a safety copy, another device): nothing to undo.
                keep.undo(entry.id)
                save()
                notice = Notice(day: today, text: Self.goneWords, id: "suggestion-gone")
                return
            }
            guard live.count == entry.changeIDs.count, live.allSatisfy({ book.canUndo($0) }),
                  store.undoSuggestion(entry.changeIDs) else {
                notice = Notice(day: today, text: Self.changedAgainWords, id: "suggestion-undo-refused")
                return
            }
        }
        keep.undo(entry.id)
        save()
    }

    func headline(_ e: SuggestionEntry, _ index: Int) -> String {
        index == 0 ? e.headline : (e.otherHeadlines.indices.contains(index - 1) ? e.otherHeadlines[index - 1] : e.headline)
    }

    // MARK: stop sign and illness (spec section 5)

    var ladder: RBLadderState {
        let input = RuleBookInput(sessions: [], weeks: [], planStart: today, weekCaps: [:], today: today,
                                  health: keep.health, settings: keep.settings)
        return RuleBook.ladderStep(input)
    }

    var paused: Bool { ladder.step == .paused }

    /* The one grey line on Today while a pause or the illness steps are on (where the plan lives in the app). */
    var ladderStatus: String? {
        guard readable, store?.canChangePlan == true else { return nil }
        return RuleBookWords.ladderStatus(ladder, today: today)
    }

    /* Opening the Stop sign pauses at once, as its words say; any open card is put away. */
    func openedStopSign() {
        guard readable, !paused else { return }
        keep.health.stopSignSince = today
        keep.health.doctorSeenOn = nil
        keep.putAwayOpen(.paused, on: today)
        save()
    }

    /* "Opened by mistake": only the day it was opened. The cards it put away come back. */
    var mayUndoStopSign: Bool { readable && paused && keep.health.stopSignSince == today }

    func stopSignByMistake() {
        guard mayUndoStopSign else { return }
        keep.health.stopSignSince = nil
        reopenPaused()
        save()
    }

    private func reopenPaused() {
        for e in keep.entries where e.record.answer == .paused && e.record.answeredOn == today { keep.unanswer(e.id) }
    }

    func doctorSeen() {
        guard readable else { return }
        keep.health.doctorSeenOn = today
        save()
        check(.morning)
    }

    func ill(_ kind: RBIllness) {
        guard readable else { return }
        keep.health.illSince = today
        keep.health.illness = kind
        keep.health.symptomFreeSince = nil
        keep.health.stillNotRight = []
        keep.putAwayOpen(.paused, on: today)
        save()
        check(.morning)
    }

    /* "I tapped this by mistake": only while no day has passed since he said he was ill. */
    var mayUndoIll: Bool { readable && keep.health.illSince == today }

    func illByMistake() {
        guard mayUndoIll else { return }
        keep.health.illSince = nil
        keep.health.illness = nil
        keep.health.symptomFreeSince = nil
        keep.health.stillNotRight = []
        // A card the illness made today goes too; one it put away comes back.
        for e in keep.entries where e.record.trigger == .section5 && e.record.day == today && e.record.answer == nil {
            keep.putAway(e.id, .paused, on: today)
        }
        reopenPaused()
        save()
    }

    func symptomFree(since day: String) {
        guard readable, keep.health.illSince != nil else { return }
        keep.health.symptomFreeSince = max(day, keep.health.illSince ?? day)
        save()
        check(.morning)
    }

    func stillNotRight() {
        guard readable else { return }
        if !keep.health.stillNotRight.contains(today) { keep.health.stillNotRight.append(today) }
        save()
        check(.morning)
    }

    // MARK: "Something hurts?"

    /* Offered once, under "How hard was it?", for a session logged today or yesterday. */
    func asksHurts(_ w: Workout) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_HURTS"] != nil { return !keep.wasAskedHurts(w.key) }
        #endif
        guard planReady, keep.settings.somethingHurtsTap, w.logged, w.discipline.id != "rest",
              w.dayKey <= today, w.dayKey >= PlanView.addDays(today, -1) else { return false }
        return !keep.wasAskedHurts(w.key)
    }

    func hurts(_ place: String?, session: String) {
        guard readable else { return }
        keep.hurts(place, session: session, on: today)
        save()
        if let place, SuggestionKeep.markingPlaces.contains(place) { check(.afterSession) }
    }

    // MARK: the grey line for his own changes

    /* His own move of a session to another day: one calm statement, or nil. The week board may call this too. */
    func note(forMoving key: String, to day: String) -> String? {
        guard planReady, let input = input(.afterSession) else { return nil }
        return SuggestionApply.note(moving: key, to: day, input: input)
    }

    /* His own change on the Change page (key nil: a new session). */
    func note(forChanging key: String?, to draft: SessionDraft) -> String? {
        guard planReady, let input = input(.afterSession) else { return nil }
        return SuggestionApply.note(changing: key, to: draft, input: input)
    }

    // MARK: Settings

    func set(on: Bool, settings: RuleBookSettings) {
        guard readable else { return }
        keep.on = on
        keep.settings = settings
        save()
    }

    /*
     * "Start the notes afresh", after he said yes: the unreadable notes are
     * put aside (never deleted) and new ones begun. The plan is not touched.
     */
    func startAfresh() {
        let stamp = Int(Date().timeIntervalSince1970)
        let fm = FileManager.default
        for (url, damaged) in [(fileURL, !readable), (capsURL, capsUnreadable)] where damaged && fm.fileExists(atPath: url.path) {
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
            try? fm.moveItem(at: url, to: aside)
        }
        if !readable { keep = SuggestionKeep() }
        readable = true
        capsUnreadable = false
        caps = nil; capsFor = nil; cached = nil; lastCheck = nil
        save()
    }

    // MARK: pictures (DEBUG)

    #if DEBUG
    var debugMode: String? { ProcessInfo.processInfo.environment["AMSWS_SUGGEST"] }
    var debugShowsOthers: Bool { debugMode == "other" }
    private var debugSeeded = false

    /*
     * AMSWS_SUGGEST=card|other|changed: a card on Today, made by the real
     * engine from an invented situation (two poor mornings on the plan as it
     * is); a fixed sample when the engine stays silent.
     */
    private func debugSeed() {
        guard !debugSeeded, let mode = debugMode, let store, store.book != nil else { return }
        debugSeeded = true
        keep.entries.removeAll { $0.record.day == today }
        var entry: SuggestionEntry?
        if var input = input(.morning) {
            input.feel.set(.tired, on: PlanView.addDays(today, -1))
            input.feel.set(.bad, on: today)
            input.log = []
            if let s = RuleBook.suggest(input) { entry = SuggestionEntry(s, input: input) }
        }
        let card = entry ?? Self.sample(today)
        keep.add(card, today: today)
        save()
        if mode == "changed" { take(0) }
    }

    static func sample(_ day: String) -> SuggestionEntry {
        let record = SuggestionRecord(day: day, trigger: .t1, step: 1, key: "sample", headline: "Thu run: 40 → 30 min, easy",
                                      why: RuleBookWords.whyPoorMornings, choices: [[], [], []], tried: [], sessions: [],
                                      closesOn: day)
        return SuggestionEntry(record: record, otherHeadlines: ["Thu run → easy", "Thu run: 40 min → rest"])
    }

    /* AMSWS_SUGGEST_LOG=1: three invented rows for the Settings page. */
    func debugSeedLog() {
        guard !keep.entries.contains(where: { $0.record.key.hasPrefix("sample-log") }) else { return }
        func row(_ back: Int, _ headline: String, _ why: String, _ others: [String], _ answer: RBAnswer?) -> SuggestionEntry {
            let day = PlanView.addDays(today, -back)
            let record = SuggestionRecord(day: day, trigger: .t1, step: 1, key: "sample-log-\(back)", headline: headline, why: why,
                                          choices: Array(repeating: [], count: others.count + 1), tried: [], sessions: [],
                                          closesOn: day, answer: answer, answeredOn: answer == nil ? nil : day)
            return SuggestionEntry(record: record, otherHeadlines: others)
        }
        keep.entries.insert(contentsOf: [
            row(12, "Mon swim: 45 → 30 min, easy", RuleBookWords.whyBigWeek(ratio: 1.5), [], .keptPlan),
            row(8, "Wed run: 55 min → rest", RuleBookWords.whyPoorMornings, ["Wed run: 55 → 40 min, easy"], .took(1)),
            row(3, "Thu run → row, same minutes, easy", RuleBookWords.whyHurts, [], .took(0))
        ], at: 0)
    }
    #endif
}
