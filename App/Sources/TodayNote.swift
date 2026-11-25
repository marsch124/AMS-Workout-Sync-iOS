import SwiftUI
import Security
import WorkoutCore

/*
 * Round 28, "todaynote": today's session, told to AMS Deck Mate and PARAGON, and the one safe answer back
 * ("done"). The content and the guard are in Core (TodayNoteMaker, DoneFromOutside, tested); this file is the
 * two places the note is put and the hook that keeps it fresh. Nothing here ever moves, edits or removes a
 * session: the only thing a link can do is log today's planned session as planned, through the same function
 * the "Done as planned" button calls.
 *
 * Channels (see round-28/today-note-contract.md):
 *  1. A Keychain item of its own, on every device: service "ams.training.today", account "v1", the same access
 *     group as the neighbour notes. Written by this app only.
 *  2. On the Mac (this is the iPad app there) a file today-note.json in the app's own Application Support folder.
 * Every failure is silent.
 */

enum TodayNoteKeychain {
    static let service = "ams.training.today"
    static let account = "v1"
    static let group = "D24ENP83QQ.com.schabbauer.AMSWorkoutSync"

    private static var match: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: group]
    }

    @discardableResult
    static func write(_ data: Data) -> Bool {
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = match
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

@MainActor
final class TodayNotePublisher {
    static let shared = TodayNotePublisher()
    private var last: TodayNote?

    /* The file's name inside the app's Application Support folder (Mac only). */
    static let fileName = "today-note.json"

    static func note(_ store: Store) -> TodayNote? {
        guard store.phase == .ready, let mapping = store.mapping else { return nil }
        let monday = PlanView.weekStart(store.today)
        let hours = PlanOverview.hours(store.displayed, mapping, from: monday, to: PlanView.addDays(monday, 6))
        return TodayNoteMaker.make(briefs: store.briefs, today: store.today, canLog: store.canLog, planReady: true,
                                   weekDoneSeconds: hours.done, weekPlannedSeconds: hours.planned)
    }

    /* `force`: the app came to the front, so the moment of writing is renewed even when nothing changed. */
    func publish(_ store: Store, force: Bool = false) {
        guard let note = Self.note(store) else { return }
        if !force, let last, TodayNoteMaker.sameContent(last, note) { return }
        guard let data = TodayNoteMaker.encoded(note) else { return }
        last = note
        TodayNoteKeychain.write(data)
        if ProcessInfo.processInfo.isiOSAppOnMac, let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            try? data.write(to: dir.appendingPathComponent(Self.fileName), options: .atomic)
        }
    }
}

/*
 * The hook, chained once inside the shared link hook (both roots): rewrites the note when the plan changes, the
 * day changes, a log is made, and when the app comes to the front; and answers amsworkoutsync://done/<key>.
 */
struct TodayNoteHook: ViewModifier {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    let open: (SystemTarget) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { TodayNotePublisher.shared.publish(store, force: true) }
            .onChange(of: phase) { _, p in if p == .active { TodayNotePublisher.shared.publish(store, force: true) } }
            .onReceive(store.objectWillChange.debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
                TodayNotePublisher.shared.publish(store)
            }
            .onOpenURL { url in
                guard let key = SystemLink.doneKey(host: url.host, path: url.path) else { return }
                Task { await done(key) }
            }
    }

    /* The app opens on the session in every case; the session is logged only when the guard in Core says so. */
    private func done(_ key: String) async {
        // A cold start: give the plan a moment to load; never guess without it.
        var waited = 0
        while !(store.phase == .ready && store.view != nil), waited < 20 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            waited += 1
        }
        let verdict = DoneFromOutside.verdict(briefs: store.briefs, key: key, today: store.today,
                                              canLog: store.canLog, planReady: store.phase == .ready && store.view != nil)
        if case .log(let brief) = verdict, let workout = store.workout(brief.key) {
            store.logAsPlanned(workout)
            TodayNotePublisher.shared.publish(store)
        }
        if verdict == .openOnly(.unknownSession) || verdict == .openOnly(.planNotReady) { open(.today) } else { open(.session(key)) }
    }
}

/* Settings: one plain line saying what the app tells Deck Mate and PARAGON. */
struct TodayNoteSettingsRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading(text: "Your two neighbour apps")
            SettingsRow(title: "Today's session is shared",
                        sub: "This app also tells Deck Mate and PARAGON today's session: its sport, length and whether it is done, and this week's hours. Nothing else. Deck Mate may log today's session as done, only as planned, and only when you press its key.")
                .accessibilityIdentifier("settings-today-note")
        }
    }
}
