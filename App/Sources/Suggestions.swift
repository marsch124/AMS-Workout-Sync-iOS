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

    @Published private(set) var keep = SuggestionKeep()
    /* False when suggestions.json is there but cannot be read: then nothing is shown or written. */
    @Published private(set) var readable = true

    private weak var store: Store?
    private var bag: Set<AnyCancellable> = []
    private var loggedToday: Int?
    /* weekCap[w], frozen the first time it is needed and kept beside the plan. */
    private var caps: [Int: Int]?
    private var capsUnreadable = false

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

    /* The card waiting for his answer. */
    var card: SuggestionEntry? { cardsOn ? keep.openEntry(on: today) : nil }

    /* A card taken today: "Changed — Undo" in its place until the day ends. */
    var changed: SuggestionEntry? { cardsOn ? keep.changedEntry(on: today) : nil }

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
        }
    }

    func check(_ moment: RBMoment) {
        guard cardsOn, planReady else { return }
        let was = keep
        keep.closeStale(today: today)
        if keep.mayShowNew(on: today), let input = input(moment), let s = RuleBook.suggest(input) {
            keep.add(SuggestionEntry(s), today: today)
        }
        if keep != was { save() }
    }

    // MARK: what the engine reads

    func input(_ moment: RBMoment) -> RuleBookInput? {
        guard let store, let book = store.book, store.canChangePlan, let caps = frozenCaps(book, today: store.today) else { return nil }
        return RuleBook.input(book: book, feel: Diary.shared.feel, today: store.today, moment: moment, log: keep.log,
                              health: keep.health, hurtDays: keep.hurtDays, weekCaps: caps,
                              importDay: PlanView.todayKey(book.origin.takenAt), settings: keep.settings)
    }

    private func frozenCaps(_ book: PlanBook, today: String) -> [Int: Int]? {
        if let caps { return caps }
        if capsUnreadable { return nil }
        if let data = try? Data(contentsOf: capsURL) {
            guard let saved = try? JSONDecoder().decode([String: Int].self, from: data) else {
                capsUnreadable = true
                return nil
            }
            caps = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in Int(k).map { ($0, v) } })
            return caps
        }
        if FileManager.default.fileExists(atPath: capsURL.path) { capsUnreadable = true; return nil }
        // First time: the plan's own minutes per week, sessions he added himself left out.
        let made = Set(book.sessions.filter(\.madeInApp).map(\.key))
        let sessions = RuleBook.input(book: book, today: today).sessions.filter { !made.contains($0.id) }
        let fresh = RuleBook.weekCaps(sessions)
        let saved = Dictionary(uniqueKeysWithValues: fresh.map { (String($0.key), $0.value) })
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: capsURL, options: .atomic)
        } catch {
            return nil
        }
        caps = fresh
        return fresh
    }

    private func save() {
        guard readable, let data = try? keep.encoded() else { return }
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: his answer

    /* "Take it" (0) or one of the other choices (1, 2). */
    func take(_ index: Int) {
        guard let entry = card, let moves = entry.record.choice(index), let store else { return }
        var ids: [String] = []
        if !moves.isEmpty {
            guard let input = input(.afterSession),
                  let made = store.applySuggestion(moves, input: input, why: "Suggestion: " + headline(entry, index)) else { return }
            ids = made
        }
        keep.answer(entry.id, .took(index), on: today, changeIDs: ids)
        save()
    }

    func keepPlan() {
        guard let entry = card else { return }
        keep.answer(entry.id, .keptPlan, on: today)
        save()
    }

    func undo() {
        guard let entry = changed, let store else { return }
        if !entry.changeIDs.isEmpty, !store.undoSuggestion(entry.changeIDs) { return }
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

    func pause() {
        keep.health.stopSignSince = today
        keep.health.doctorSeenOn = nil
        save()
    }

    func doctorSeen() {
        keep.health.doctorSeenOn = today
        save()
        check(.morning)
    }

    func ill(_ kind: RBIllness) {
        keep.health.illSince = today
        keep.health.illness = kind
        keep.health.symptomFreeSince = nil
        keep.health.stillNotRight = []
        save()
        check(.morning)
    }

    func symptomFree(since day: String) {
        guard keep.health.illSince != nil else { return }
        keep.health.symptomFreeSince = max(day, keep.health.illSince ?? day)
        save()
        check(.morning)
    }

    func stillNotRight() {
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
        keep.hurts(place, session: session, on: today)
        save()
        if place != nil { check(.afterSession) }
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
            if let s = RuleBook.suggest(input) { entry = SuggestionEntry(s) }
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
