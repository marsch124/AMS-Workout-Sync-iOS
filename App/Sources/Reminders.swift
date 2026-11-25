import SwiftUI
import UserNotifications
import Combine
import WorkoutCore

/*
 * Reminders (round 28): local notifications only. No server, no push. Every one
 * is worked out on this device from the plan (Core's `Reminders.schedule`) and
 * laid with iOS; they are worked out again whenever the plan or a pause changes
 * and whenever the app comes to the front.
 *
 * The switches and times are kept per device (UserDefaults): the iPhone, the
 * iPad and the Mac each have their own. A later round may move them behind
 * `ReminderSettingsStore` to a synced place; nothing else knows where they live.
 *
 * The missed-session question's three buttons call the very functions the
 * in-app buttons call (`Store.markMissed`, `Store.move`): no new way to write
 * the plan. They open the app first (foreground actions) so the plan is loaded;
 * if it is not loaded in a few seconds, or the action is not safe any more, the
 * app opens on that session instead and he taps there.
 */

/* Where the switches live. One small door, so a synced store can replace it. */
protocol ReminderSettingsStore {
    func load() -> ReminderSettings
    func save(_ settings: ReminderSettings)
    var closedCardWeek: String? { get nonmutating set }
}

struct DeviceReminderSettings: ReminderSettingsStore {
    private let key = "reminders.settings"
    func load() -> ReminderSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(ReminderSettings.self, from: data) else { return ReminderSettings() }
        return s
    }
    func save(_ settings: ReminderSettings) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: key) }
    }
    var closedCardWeek: String? {
        get { UserDefaults.standard.string(forKey: "reminders.closedCardWeek") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "reminders.closedCardWeek") }
    }
}

@MainActor
final class ReminderCentre: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderCentre()

    private let door: ReminderSettingsStore = DeviceReminderSettings()
    private let center = UNUserNotificationCenter.current()

    @Published private(set) var settings: ReminderSettings
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var closedCardWeek: String?

    private weak var store: Store?
    private var bag: Set<AnyCancellable> = []
    private var planning: Task<Void, Never>?
    /* The session whose log form the next opening of its page shows (from "It is done"). */
    private var logFormKey: String?

    private override init() {
        settings = door.load()
        closedCardWeek = door.closedCardWeek
        super.init()
    }

    // MARK: start

    /* Called once at launch: the buttons under a notification and who answers them. */
    func start() {
        center.delegate = self
        func action(_ a: ReminderAction) -> UNNotificationAction {
            UNNotificationAction(identifier: a.rawValue, title: a.title, options: [.foreground])
        }
        let withMove = UNNotificationCategory(identifier: "reminder-missed-move",
                                              actions: [action(.skip), action(.moveToToday), action(.itIsDone)],
                                              intentIdentifiers: [], options: [])
        let withoutMove = UNNotificationCategory(identifier: "reminder-missed",
                                                 actions: [action(.skip), action(.itIsDone)],
                                                 intentIdentifiers: [], options: [])
        center.setNotificationCategories([withMove, withoutMove])
        Task { await refreshStatus() }
    }

    func attach(_ store: Store) {
        guard self.store !== store else { return }
        self.store = store
        bag.removeAll()
        store.objectWillChange.merge(with: SuggestionKeeper.shared.objectWillChange)
            .debounce(for: .seconds(1.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.replan() }
            .store(in: &bag)
        replan()
    }

    // MARK: his switches

    func apply(_ new: ReminderSettings) {
        let firstOn = !settings.anyOn && new.anyOn
        settings = new
        door.save(new)
        if firstOn { Task { await askPermission() } }
        replan()
    }

    func closeCard(_ monday: String) {
        closedCardWeek = monday
        door.closedCardWeek = monday
    }

    /* Only when the first reminder is switched on: iOS asks once; a refusal is shown calmly on the page. */
    func askPermission() async {
        await refreshStatus()
        guard status == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshStatus()
        replan()
    }

    func askForPermissionNow() { Task { await askPermission() } }

    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
    }

    var refused: Bool { status == .denied }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    func sendTest() {
        Task {
            await refreshStatus()
            if status == .notDetermined { await askPermission() }
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            let c = UNMutableNotificationContent()
            c.title = "Training"
            c.body = "This is a test. Your reminders will look like this."
            c.sound = .default
            c.userInfo = ["kind": "test"]
            let request = UNNotificationRequest(identifier: "reminder-test-now", content: c,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
            try? await center.add(request)
        }
    }

    // MARK: what is laid with iOS

    /* The plan's sessions as the rule sees them. */
    func sessions(_ store: Store) -> [ReminderSession] {
        guard let view = store.view else { return [] }
        let keeper = SuggestionKeeper.shared
        let today = store.today
        return view.visible.map { w in
            var allowed = true
            // Only the sessions a missed question can be about need the rule book's word.
            if w.dayKey >= PlanView.addDays(today, -1), w.dayKey <= today, !w.logged, !w.missed {
                allowed = store.canLog && keeper.note(forMoving: w.key, to: PlanView.addDays(w.dayKey, 1)) == nil
            }
            return ReminderSession(key: w.key, dayKey: w.dayKey, disciplineId: w.discipline.id, sport: w.discipline.label,
                                   title: w.title, intensity: w.planned.intensity,
                                   seconds: Plan.plannedSeconds(w, view.mapping), done: w.logged, missed: w.missed,
                                   moveToTodayAllowed: allowed)
        }
    }

    var paused: Bool {
        let keeper = SuggestionKeeper.shared
        guard keeper.readable else { return false }
        return PauseShare.stopOn(keeper.keep.health) || PauseShare.illOn(keeper.keep.health)
    }

    func replan() {
        planning?.cancel()
        planning = Task { [weak self] in
            guard let self else { return }
            await self.refreshStatus()
            let pending = await self.center.pendingNotificationRequests()
            let old = pending.map(\.identifier).filter { $0.hasPrefix(Reminders.idPrefix) && $0 != "reminder-test-now" }
            self.center.removePendingNotificationRequests(withIdentifiers: old)
            guard !Task.isCancelled, let store = self.store, store.phase == .ready,
                  self.status == .authorized || self.status == .provisional || self.status == .ephemeral else { return }
            let now = Date()
            let c = Calendar.current.dateComponents([.hour, .minute], from: now)
            let list = Reminders.schedule(sessions: self.sessions(store), today: store.today,
                                          nowMinutes: (c.hour ?? 0) * 60 + (c.minute ?? 0),
                                          settings: self.settings, paused: self.paused)
            for r in list {
                guard let day = parseDayKey(r.day) else { continue }
                // The day key is a UTC date; its calendar parts are read as written.
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
                var d = utc.dateComponents([.year, .month, .day], from: day)
                d.hour = r.minutes / 60; d.minute = r.minutes % 60
                let content = UNMutableNotificationContent()
                content.title = r.title
                content.body = r.body
                content.sound = .default
                content.userInfo = ["kind": r.kind.rawValue, "key": r.sessionKey ?? ""]
                if r.kind == .missed {
                    content.categoryIdentifier = r.actions.contains(.moveToToday) ? "reminder-missed-move" : "reminder-missed"
                }
                let trigger = UNCalendarNotificationTrigger(dateMatching: d, repeats: false)
                try? await self.center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: the card on Today

    /* The week the card shows now, or nil: not on, not the time, or put away until next Sunday. */
    func cardWeek(today: String, now: Date = Date()) -> String? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let monday = Reminders.cardWeek(today: today, nowMinutes: (c.hour ?? 0) * 60 + (c.minute ?? 0), settings: settings),
              closedCardWeek != monday else { return nil }
        return monday
    }

    func card(monday: String, store: Store) -> SundayCard? {
        let weeks = (store.book?.weeks ?? []).map { ReminderWeek(monday: $0.monday, phase: $0.phase, isEasy: $0.isEasy, isTest: $0.isTest) }
        var list = weeks
        if !list.contains(where: { $0.monday == monday }), let w = store.view?.visible.first(where: { $0.dayKey >= monday && $0.dayKey <= PlanView.addDays(monday, 6) }) {
            // A plan read from Excel has no weeks of its own: the sessions' phase word stands in, with no E or T.
            list.append(ReminderWeek(monday: monday, phase: w.phase))
        }
        return Reminders.card(monday: monday, sessions: sessions(store), weeks: list)
    }

    // MARK: opening and answering

    /* "amsworkoutsync://session?key=…&log=1": the app opens on that session (RootView's one hook). */
    static func sessionURL(_ key: String, log: Bool) -> URL? {
        var c = URLComponents(); c.scheme = "amsworkoutsync"; c.host = "session"
        c.queryItems = [URLQueryItem(name: "key", value: key)] + (log ? [URLQueryItem(name: "log", value: "1")] : [])
        return c.url
    }

    /* From the URL: the session's key, and the log form is asked for when `log=1`. */
    func sessionKey(from url: URL) -> String? {
        guard url.host == "session",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let key = items.first(where: { $0.name == "key" })?.value, !key.isEmpty else { return nil }
        if items.contains(where: { $0.name == "log" && $0.value == "1" }) { logFormKey = key }
        return key
    }

    /* SessionView asks once when it appears: true if "It is done" brought him here. */
    func takeLogForm(for key: String) -> Bool {
        guard logFormKey == key else { return false }
        logFormKey = nil
        return true
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        // Cold start: the app's own screens are not up yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { UIApplication.shared.open(url) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? ""
        let key = info["key"] as? String ?? ""
        let action = response.actionIdentifier
        await MainActor.run { self.answer(kind: kind, key: key, action: action) }
    }

    private func answer(kind: String, key: String, action: String) {
        let today = URL(string: "amsworkoutsync://today")
        guard kind == ReminderKind.missed.rawValue, !key.isEmpty else { open(today); return }
        let session = Self.sessionURL(key, log: false)
        switch ReminderAction(rawValue: action) {
        case .itIsDone:
            open(Self.sessionURL(key, log: true))
        case .skip:
            Task { [weak self] in
                guard let self, let w = await self.openSession(key) else { self?.open(session); return }
                self.store?.markMissed(w, note: "")         // the same function as the Missed button
                self.open(today)
            }
        case .moveToToday:
            Task { [weak self] in
                guard let self, let store = self.store, let w = await self.openSession(key),
                      w.dayKey < store.today,
                      SuggestionKeeper.shared.note(forMoving: key, to: store.today) == nil else { self?.open(session); return }
                store.move(w, to: store.today)               // the same function as the Move button
                self.open(today)
            }
        case .none:
            open(session)                                    // a tap on the notification itself
        }
    }

    /* The session, once the plan is loaded (up to ~8 seconds) and still neither logged nor missed; else nil. */
    private func openSession(_ key: String) async -> Workout? {
        for _ in 0..<32 {
            if let store, store.phase == .ready, store.canLog, let w = store.workout(key) {
                return (w.logged || w.missed) ? nil : w
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }
}
