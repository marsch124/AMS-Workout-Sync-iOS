import SwiftUI
import Security
import WorkoutCore

/*
 * The notes between this app, AMS Workouts and AMS Magic Morning (25 November
 * 2026): one small piece of JSON in one shared Keychain item, on this phone only.
 * The rules live in Core (NeighbourRules); this file is the Keychain, the
 * "which app is installed" question, and what the screens ask.
 *
 * Every failure is silent: the app then behaves as if there were no notes. It
 * never writes over a note it cannot read, and never by itself logs a session.
 */

/* The shared item. The access group is passed in full, as the neighbours list it in their entitlements. */
enum NeighbourKeychain {
    static let service = "ams.training.notes"
    static let account = "v1"
    static let group = "D24ENP83QQ.com.schabbauer.AMSWorkoutSync"

    enum Read { case missing, found(Data), failed }

    private static var match: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: group]
    }

    static func read() -> Read {
        var query = match
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &out) {
        case errSecSuccess: return (out as? Data).map(Read.found) ?? .failed
        case errSecItemNotFound: return .missing
        default: return .failed
        }
    }

    @discardableResult
    static func write(_ data: Data) -> Bool {
        let change = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, change as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = match
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

@MainActor
final class Neighbours: ObservableObject {
    static let shared = Neighbours()

    /* What the notes say now; nil when there are none or they cannot be read. */
    @Published private(set) var notes: NeighbourNotes?
    /* Strength sessions logged from a note: the session's key, and the note's id. */
    @Published private(set) var loggedFrom: [String: String] = [:]
    private(set) var today = PlanView.todayKey()

    private let loggedKey = "neighbour.loggedFrom"
    private let fake: Bool

    init() {
        var pretend = false
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        pretend = env["AMSWS_FAKE_NOTES"] != nil
        if let day = env["AMSWS_TODAY"] { today = day }
        if env["AMSWS_RESET"] != nil { UserDefaults.standard.removeObject(forKey: loggedKey) }
        #endif
        fake = pretend
        loggedFrom = (UserDefaults.standard.dictionary(forKey: loggedKey) as? [String: String]) ?? [:]
        if fake { notes = Self.invented(today: today) }
    }

    // MARK: the other apps

    private func installed(_ scheme: String) -> Bool {
        if fake { return true }
        guard let url = URL(string: scheme + "://open") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    var workoutsInstalled: Bool { installed("amsworkouts") }
    var morningInstalled: Bool { installed("amsmorning") }

    func openWorkouts() {
        guard let url = URL(string: "amsworkouts://open") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: reading and writing

    private static let takenOverKey = "neighbour.feelTakenOverDay"

    /* When the app comes to the front (and when Today appears): read, take over this morning's answer, hand on his own. */
    func cameToFront(today day: String) {
        today = day
        if !fake {
            switch NeighbourKeychain.read() {
            case .found(let data): notes = NeighbourNotes.decode(data)
            default: notes = nil
            }
        }
        let own = Diary.shared.feel.answer(on: day)
        // The marker says which day's answer in the diary came from the notes, not from this app.
        // An answer he gave in this app on another device may have replaced it since (a merge leaves no "from"): that one stays.
        let marked = UserDefaults.standard.string(forKey: Self.takenOverKey) == day && Diary.shared.feelFrom[day] != nil
        let sameAsTheirs = own != nil && notes?.feel?.day == day && notes?.feel?.from != "training"
            && notes?.feel?.value == own?.rawValue
        if let taken = NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: own, today: day,
                                                   ownAnswerWasTakenOver: marked || sameAsTheirs) {
            // Marked with the note's own time, not now: an answer he gave later in this app on another device stays newer.
            Diary.shared.setFeel(taken, on: day, from: notes?.feel?.from, at: NeighbourRules.takenOverMoment(notes?.feel))
            UserDefaults.standard.set(day, forKey: Self.takenOverKey)
        } else if sameAsTheirs {
            UserDefaults.standard.set(day, forKey: Self.takenOverKey)
            if let from = notes?.feel?.from { Diary.shared.noteFeelFrom(from, on: day) }
        } else if let own, Diary.shared.feelFrom[day] == nil {
            // An answer that reached this device through iCloud from another app is not handed on as this app's own.
            writeFeel(own, day: day)
        }
    }

    /* His own answer, into the notes when there is none for today (read, change, write). */
    func writeFeel(_ feel: Feel, day: String) {
        if fake {
            if let out = NeighbourRules.writingFeel(notes: notes, own: feel, today: day) { notes = out }
            return
        }
        let current: NeighbourNotes?
        switch NeighbourKeychain.read() {
        case .missing: current = nil
        case .found(let data):
            guard let decoded = NeighbourNotes.decode(data) else { return }   // broken or newer: left alone
            current = decoded
        case .failed: return
        }
        guard let out = NeighbourRules.writingFeel(notes: current, own: feel, today: day),
              let data = out.encoded(), data.count < 8000, NeighbourKeychain.write(data) else { return }
        notes = out
    }

    // MARK: what the screens ask

    /* "from Magic Morning" when today's answer in the diary is the one another app gave. */
    func feelSource(today day: String, answer: Feel?) -> String? {
        guard let answer else { return nil }
        // This device's own note first; without one (an iPad or Mac that got the answer through iCloud) what the diary carries.
        let from = (notes?.feel).flatMap { $0.day == day && $0.value == answer.rawValue && $0.from != "training" ? $0.from : nil }
            ?? Diary.shared.feelFrom[day]
        switch from {
        case "morning": return "Magic Morning"
        case "workouts": return "Workout Companion"
        default: return nil
        }
    }

    /* A feel of today is waiting in the notes: the question is not asked. */
    func hasFeel(today day: String) -> Bool {
        NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: nil, today: day) != nil
    }

    enum Strength: Equatable {
        case offer(NeighbourDone)
        case logged
    }

    /*
     * The grey line under a mobility or strength session: "Ticked from …" once a neighbour's note logged it
     * (2.16: read from the log itself, so iPad and Mac show it too; a log of an earlier version is known by
     * the note id this iPhone kept). Strength still to do, with a note it could not be ticked from (no
     * minutes, no planned length): the note's line and "Log it", for the first one of the day still to do.
     */
    func strength(for w: Workout, among day: [Workout]) -> Strength? {
        guard w.discipline.id == "mobility" || w.discipline.id == "strength" else { return nil }
        if w.state == .done {
            if NeighbourRules.tickedFrom(w) != nil { return .logged }
            return loggedFrom[w.key] != nil ? .logged : nil
        }
        guard w.discipline.id == "strength" else { return nil }
        guard w.state == .todo,
              day.first(where: { $0.discipline.id == "strength" && $0.state == .todo })?.key == w.key,
              let note = NeighbourRules.strengthNote(for: w.dayKey, in: notes, used: Set(loggedFrom.values)) else { return nil }
        return .offer(note)
    }

    /* He tapped "Log it": the minutes and effort go in through the ordinary logging, once. */
    func logIt(_ w: Workout, _ note: NeighbourDone, store: Store) {
        guard store.canLog, let id = note.id else { return }
        var entry = LogEntry()
        var minutes = note.minutes ?? 0
        if minutes <= 0, let mapping = store.mapping, let s = Plan.plannedSeconds(w, mapping), s > 0 { minutes = Int((s / 60).rounded()) }
        guard minutes > 0 else { return }
        entry.actualDuration = String(minutes)
        if let e = note.effort, (1...10).contains(e) { entry.rpe = String(e) }
        entry.tickedFrom = NeighbourRules.tickSource(note)
        store.log(w, entry)
        loggedFrom[w.key] = id
        UserDefaults.standard.set(loggedFrom, forKey: loggedKey)
    }

    /*
     * 2.15: a planned mobility session still to do, on a morning he stretched in Magic Morning, is ticked
     * by itself with the stretch's minutes (the planned length when the note has none) — today and the
     * days before, as far back as the notes go, each note once.
     * 2.16: a planned strength session the same way from a finished Workout Companion workout, with its
     * minutes and its effort. iPhone only: the notes live there; the log, with where it came from,
     * reaches the iPad and the Mac through iCloud like any other.
     */
    func tickFromNeighbours(store: Store) {
        guard store.canLog else { return }
        let day = store.today
        let oldest = PlanView.addDays(day, -(NeighbourRules.keepDays - 1))
        let sessions = store.displayed
        func todo(_ sport: String) -> [(key: String, day: String)] {
            sessions.filter {
                $0.discipline.id == sport && !$0.logged && !$0.missed && !store.isWaiting($0.key)
                    && $0.dayKey <= day && $0.dayKey >= oldest
            }.map { (key: $0.key, day: $0.dayKey) }
        }
        let mobility = todo("mobility"), strength = todo("strength")
        guard !mobility.isEmpty || !strength.isEmpty else { return }
        let used = Set(loggedFrom.values)
        let ticks = NeighbourRules.mobilityTicks(todo: mobility, notes: notes, used: used, today: day)
            + NeighbourRules.strengthTicks(todo: strength, notes: notes, used: used, today: day)
        var changed = false
        for t in ticks {
            guard let w = sessions.first(where: { $0.key == t.key }), let id = t.note.id else { continue }
            var minutes = t.note.minutes ?? 0
            if minutes <= 0, let mapping = store.mapping, let s = Plan.plannedSeconds(w, mapping), s > 0 { minutes = Int((s / 60).rounded()) }
            guard minutes > 0 else { continue }
            var entry = LogEntry()
            entry.actualDuration = String(minutes)
            if w.discipline.id == "strength", let e = t.note.effort, (1...10).contains(e) { entry.rpe = String(e) }
            entry.tickedFrom = NeighbourRules.tickSource(t.note)
            store.log(w, entry)
            loggedFrom[w.key] = id
            changed = true
        }
        if changed { UserDefaults.standard.set(loggedFrom, forKey: loggedKey) }
    }

    /* "Stretching: 4 of the last 7 mornings"; nil when there is no stretch note at all. */
    var stretchLine: String? {
        guard let n = NeighbourRules.stretchMornings(in: notes, lastDays: 7, today: today) else { return nil }
        return "Stretching: \(n) of the last 7 mornings"
    }

    // MARK: pictures (DEBUG: AMSWS_FAKE_NOTES=1)

    /* Invented notes for a picture: today's feel from Magic Morning, a strength note for today, four stretch mornings. */
    private static func invented(today: String) -> NeighbourNotes {
        let parts = today.split(separator: "-").compactMap { Int($0) }
        var at = ""
        if parts.count == 3, let d = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 7, minute: 40)) {
            at = ISO8601DateFormatter().string(from: d)
        }
        var done = [NeighbourDone(id: "FAKE-STRENGTH", day: today, kind: "strength", title: "Strength A", minutes: 35, effort: 6, at: at, from: "workouts")]
        for (i, back) in [0, 1, 3, 5].enumerated() {
            done.append(NeighbourDone(id: "FAKE-STRETCH-\(i)", day: PlanView.addDays(today, -back), kind: "stretch",
                                      title: "Morning stretch", minutes: 12, from: "morning"))
        }
        return NeighbourNotes(feel: NeighbourFeel(day: today, value: Feel.good.rawValue, at: at, from: "morning"), done: done)
    }
}

/* "Ticked from Workout Companion" / "Ticked from Magic Morning"; or, when a strength note could not tick by itself, "Done in Workout Companion at 07:40 · 35 min" with one small green "Log it". */
struct NeighbourDoneLine: View {
    @EnvironmentObject var store: Store
    let workout: Workout
    let state: Neighbours.Strength

    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.footnote).foregroundStyle(Theme.secondary)
                .accessibilityIdentifier("neighbour-done")
            if case .offer(let note) = state {
                Button("Log it") { Neighbours.shared.logIt(workout, note, store: store) }
                    .settingsButton(tint: Theme.today, filled: true)
                    .accessibilityIdentifier("neighbour-log")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var text: String {
        switch state {
        case .offer(let note): return NeighbourRules.doneLine(note)
        case .logged:
            return NeighbourRules.tickedLine(from: NeighbourRules.tickedFrom(workout))
                ?? NeighbourRules.tickedLine(from: workout.discipline.id == "mobility" ? "morning" : "workouts") ?? ""
        }
    }
}
