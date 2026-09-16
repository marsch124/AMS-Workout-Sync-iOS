import EventKit
import Foundation
import SwiftUI
import WorkoutCore

/*
 * The plan in the Calendar app: every session from today to the end of the
 * plan as an event in a calendar called Training, at the hour set here and
 * as long as it is planned to be, one after the other on a day with two —
 * the web app's calendar rules, kept. A rest day is an all-day event. A
 * session the plan gives no length to is all-day too, and does not push
 * along whatever comes after it.
 *
 * The events float: 06:00 stays 06:00 wherever the phone is, which is the
 * right answer for training. The app remembers which event is which session,
 * so a moved session moves its event, a changed row rewrites it, a session
 * that disappears takes its event with it, and nothing is written twice.
 * Days already behind are left as they were: they are the record.
 *
 * The Training calendar is the app's own. From today onwards it holds
 * exactly the plan — anything else found there is taken out — so a lost
 * memory of the events (a reinstall) cannot double them. Taking the sessions
 * out removes the calendar.
 *
 * Needs the full calendar permission: write-only access cannot see, and so
 * cannot update, the events the app made itself.
 */
@MainActor
final class TrainingCalendar: ObservableObject {
    static let shared = TrainingCalendar()

    enum Status { case notAsked, granted, denied }

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "calendar.enabled") } }
    @Published var startMinutes: Int { didSet { UserDefaults.standard.set(startMinutes, forKey: "calendar.start") } }
    @Published private(set) var status: Status
    @Published private(set) var count: Int = UserDefaults.standard.integer(forKey: "calendar.count")
    @Published private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "calendar.lastSync") as? Date
    @Published private(set) var problem: String?
    @Published private(set) var busy = false

    struct Entry: Codable { let id: String; let day: String; let hash: String }
    struct Desired {
        let key: String, day: String, title: String, notes: String
        let start: Int?      // seconds from midnight, nil for all-day
        let seconds: Int
        var hash: String { TrainingCalendar.fnv(title + "\n" + notes + "\n" + day + "\n" + String(start ?? -1) + "\n" + String(seconds)) }
    }

    private let store = EKEventStore()
    private var map: [String: Entry]
    private var queued: ([Workout], Mapping, String)?

    init() {
        enabled = UserDefaults.standard.bool(forKey: "calendar.enabled")
        startMinutes = UserDefaults.standard.object(forKey: "calendar.start") as? Int ?? 6 * 60
        status = Self.currentStatus()
        map = (try? JSONDecoder().decode([String: Entry].self, from: UserDefaults.standard.data(forKey: "calendar.events") ?? Data())) ?? [:]
        #if DEBUG
        // A simulator with the permission granted by simctl: switched on at launch for a screenshot.
        if ProcessInfo.processInfo.environment["AMSWS_CALENDAR"] != nil, status == .granted { enabled = true }
        #endif
    }

    static func currentStatus() -> Status {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    func refreshStatus() { status = Self.currentStatus() }

    func enable() async {
        problem = nil
        do {
            let ok = try await store.requestFullAccessToEvents()
            status = Self.currentStatus()
            guard ok, status == .granted else {
                problem = "iOS did not give the app full access to your calendar."
                return
            }
            enabled = true
        } catch {
            problem = error.localizedDescription
        }
    }

    /* Takes the sessions out: the Training calendar goes, and its events with it. */
    func disable() {
        enabled = false
        problem = nil
        let store = self.store
        let id = UserDefaults.standard.string(forKey: "calendar.id")
        map = [:]
        count = 0
        saveState()
        UserDefaults.standard.removeObject(forKey: "calendar.id")
        Task.detached(priority: .utility) {
            if let id, let cal = store.calendar(withIdentifier: id) {
                try? store.removeCalendar(cal, commit: true)
            }
        }
    }

    /* Bring the calendar in step with the plan as shown. Safe to call often: nothing unchanged is rewritten. */
    func sync(_ workouts: [Workout], mapping: Mapping, today: String) {
        guard enabled, status == .granted else { return }
        if busy { queued = (workouts, mapping, today); return }
        busy = true
        problem = nil
        let desired = Self.desired(workouts, mapping, today: today, startMinutes: startMinutes)
        let previous = map
        let store = self.store
        let calendarId = UserDefaults.standard.string(forKey: "calendar.id")
        Task.detached(priority: .utility) {
            let outcome = Self.apply(store, calendarId: calendarId, desired: desired, previous: previous, today: today)
            await MainActor.run {
                switch outcome {
                case .success(let (newMap, calId)):
                    self.map = newMap
                    self.count = desired.count
                    self.lastSync = Date()
                    UserDefaults.standard.set(calId, forKey: "calendar.id")
                    self.saveState()
                case .failure(let error):
                    self.problem = "The calendar could not be updated: \(error.localizedDescription)"
                }
                self.busy = false
                if let (w, m, t) = self.queued { self.queued = nil; self.sync(w, mapping: m, today: t) }
            }
        }
    }

    private func saveState() {
        UserDefaults.standard.set(try? JSONEncoder().encode(map), forKey: "calendar.events")
        UserDefaults.standard.set(count, forKey: "calendar.count")
        UserDefaults.standard.set(lastSync, forKey: "calendar.lastSync")
    }

    // MARK: what the calendar should hold

    static func desired(_ workouts: [Workout], _ mapping: Mapping, today: String, startMinutes: Int) -> [Desired] {
        var days: [String] = []
        var byDay: [String: [Workout]] = [:]
        for w in workouts where w.dayKey >= today {
            if byDay[w.dayKey] == nil { days.append(w.dayKey) }
            byDay[w.dayKey, default: []].append(w)
        }
        var out: [Desired] = []
        for day in days {
            var at = startMinutes * 60
            for w in byDay[day] ?? [] {
                if w.discipline.id == "rest" {
                    out.append(Desired(key: w.key, day: day, title: "Rest day", notes: w.title, start: nil, seconds: 0))
                    continue
                }
                let seconds = Int(Plan.plannedSeconds(w, mapping) ?? 0)
                let planned = seconds > 0 ? formatDuration(Double(seconds)) : ""
                var summary = w.discipline.label + (planned.isEmpty ? "" : " " + planned)
                if !w.title.isEmpty { summary += " — " + w.title }
                if summary.count > 80 { summary = String(summary.prefix(79)).trimmingCharacters(in: .whitespaces) + "…" }

                var notes: [String] = []
                var seen = Set<String>()
                func add(_ text: String) {
                    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty, !seen.contains(line.lowercased()) else { return }
                    seen.insert(line.lowercased())
                    notes.append(line)
                }
                add(w.title)
                if !w.planned.intensity.isEmpty { add("Intensity: " + w.planned.intensity) }
                let purpose = w.planned.description
                if !purpose.isEmpty { add("Purpose: " + purpose) }
                for s in w.sections where purpose.isEmpty || s.text != purpose { add(s.label + ": " + s.text) }

                out.append(Desired(key: w.key, day: day, title: summary, notes: notes.joined(separator: "\n"),
                                   start: seconds > 0 ? at : nil, seconds: seconds))
                if seconds > 0 { at += seconds }
            }
        }
        return out
    }

    // MARK: EventKit

    nonisolated private static func apply(_ store: EKEventStore, calendarId: String?, desired: [Desired],
                                          previous: [String: Entry], today: String) -> Result<([String: Entry], String), Error> {
        do {
            var map = previous
            var cal = calendarId.flatMap { store.calendar(withIdentifier: $0) }
            if cal == nil {
                // No calendar (yet, or any more): whatever was remembered about its events is moot.
                map = [:]
                cal = try makeCalendar(store)
            }
            guard let cal else { return .failure(NSError(domain: "AMSWorkoutSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "No calendar could be made."])) }

            let now = Date()
            let from = Calendar.current.date(byAdding: .year, value: -2, to: now)!
            let to = Calendar.current.date(byAdding: .year, value: 3, to: now)!
            var existing: [String: EKEvent] = [:]
            for ev in store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [cal])) {
                existing[ev.eventIdentifier] = ev
            }

            var newMap: [String: Entry] = [:]
            var saved: [(String, EKEvent, Desired)] = []
            let wanted = Set(desired.map(\.key))
            for d in desired {
                if let e = map[d.key], e.hash == d.hash, existing[e.id] != nil { newMap[d.key] = e; continue }
                let ev = map[d.key].flatMap { existing[$0.id] } ?? EKEvent(eventStore: store)
                fill(ev, d, cal)
                try store.save(ev, span: .thisEvent, commit: false)
                saved.append((d.key, ev, d))
            }
            for (key, e) in map where !wanted.contains(key) {
                if e.day >= today {
                    if let ev = existing[e.id] { try store.remove(ev, span: .thisEvent, commit: false) }
                } else {
                    newMap[key] = e
                }
            }
            try store.commit()
            for (key, ev, d) in saved { newMap[key] = Entry(id: ev.eventIdentifier, day: d.day, hash: d.hash) }

            // From today onwards the calendar holds the plan and nothing else.
            let ours = Set(newMap.values.map(\.id))
            let midnight = Calendar.current.startOfDay(for: now)
            var strays = 0
            for (id, ev) in existing where !ours.contains(id) && ev.startDate >= midnight {
                try store.remove(ev, span: .thisEvent, commit: false)
                strays += 1
            }
            if strays > 0 { try store.commit() }
            return .success((newMap, cal.calendarIdentifier))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func fill(_ ev: EKEvent, _ d: Desired, _ cal: EKCalendar) {
        ev.calendar = cal
        ev.title = d.title
        ev.notes = d.notes.isEmpty ? nil : d.notes
        let parts = d.day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return }
        var comps = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        if let start = d.start {
            comps.hour = start / 3600
            comps.minute = (start % 3600) / 60
            let at = Calendar.current.date(from: comps) ?? Date()
            ev.isAllDay = false
            ev.startDate = at
            ev.endDate = at.addingTimeInterval(TimeInterval(d.seconds))
            ev.timeZone = nil     // floating: six in the morning wherever the phone is
        } else {
            let midnight = Calendar.current.date(from: comps) ?? Date()
            ev.isAllDay = true
            ev.startDate = midnight
            ev.endDate = midnight.addingTimeInterval(86399)
        }
    }

    nonisolated private static func makeCalendar(_ store: EKEventStore) throws -> EKCalendar {
        // A Training calendar already there — from an earlier install — is adopted, not doubled.
        if let found = store.calendars(for: .event).first(where: { $0.title == "Training" && $0.allowsContentModifications }) {
            return found
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "Training"
        cal.cgColor = CGColor(srgbRed: 0, green: 0.53, blue: 0.35, alpha: 1)
        if let icloud = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
            cal.source = icloud
        } else if let def = store.defaultCalendarForNewEvents?.source {
            cal.source = def
        } else if let local = store.sources.first(where: { $0.sourceType == .local }) {
            cal.source = local
        }
        try store.saveCalendar(cal, commit: true)
        return cal
    }

    /* FNV-1a, so the same text hashes the same on every launch — Swift's own hasher does not. */
    nonisolated static func fnv(_ text: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }
}
