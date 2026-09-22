import Foundation

/*
 * The questions the screens ask of a plan: what is on a day, what the week
 * looks like, what is still to come. Ported from js/sync.js.
 */

/*
 * One extra as the screens need it: which day, which activity, how long.
 *
 * The rest of the row — what was covered, the heart rate, the effort, the
 * notes, and the reference the row carries — travels with it too, because the
 * form that corrects an extra opens filled in, and it has nowhere else to read
 * those from. They are the sheet's own text rather than numbers: a box shows
 * what the cell says, and only a box the person alters is written back.
 */
public struct ExtraSummary: Identifiable, Equatable {
    public let id: String
    public let dayKey: String
    public let activity: String
    public let label: String
    public let what: String
    public let minutes: Double?
    public let isTraining: Bool
    public let pending: Bool
    public let distance: String
    public let avgHr: String
    public let effort: String
    public let notes: String
    public let ref: String
    public var seconds: Double { (minutes ?? 0) * 60 }

    public init(id: String, dayKey: String, activity: String, label: String, what: String, minutes: Double?,
                isTraining: Bool, pending: Bool, distance: String = "", avgHr: String = "", effort: String = "",
                notes: String = "", ref: String = "") {
        self.id = id; self.dayKey = dayKey; self.activity = activity; self.label = label; self.what = what
        self.minutes = minutes; self.isTraining = isTraining; self.pending = pending
        self.distance = distance; self.avgHr = avgHr; self.effort = effort; self.notes = notes; self.ref = ref
    }
}

public struct PlanDay: Identifiable {
    public var id: String { dayKey }
    public let dayKey: String
    public let date: Date
    public let isToday: Bool
    public let isPast: Bool
    public let sessions: [Workout]
    public let training: [Workout]
    /* An extra does not end a rest day the way a session moved onto one does. */
    public let isRest: Bool
    public let plannedSeconds: Double
    public let extras: [ExtraSummary]
    public var extraSeconds: Double { extras.reduce(0) { $0 + $1.seconds } }
}

public struct PlanView {
    public let plan: [Workout]
    public let mapping: Mapping
    public let extras: [ExtraSummary]

    public init(plan: [Workout], mapping: Mapping, extras: [ExtraSummary] = []) {
        self.plan = plan
        self.mapping = mapping
        self.extras = extras
    }

    public func extras(on day: String) -> [ExtraSummary] { extras.filter { $0.dayKey == day } }

    /* Today in the phone's own calendar, keyed the way the sheet's dates are. */
    public static func todayKey(_ now: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func addDays(_ key: String, _ days: Int) -> String {
        guard let date = parseDayKey(key), let moved = utc.date(byAdding: .day, value: days, to: date) else { return key }
        return dayKey(moved) ?? key
    }

    public static func weekStart(_ key: String) -> String {
        guard let date = parseDayKey(key) else { return key }
        let weekday = (utc.component(.weekday, from: date) + 5) % 7   // Monday = 0
        return addDays(key, -weekday)
    }

    /*
     * A rest row says "nothing today". Move a session onto that day and it is
     * no longer true, so the rest row is not shown there — though it stays in
     * the plan, and moving the session away brings the rest day back.
     */
    public var visible: [Workout] {
        let training = Set(plan.filter { $0.discipline.id != "rest" }.map(\.dayKey))
        if training.isEmpty { return plan }
        return plan.filter { !($0.discipline.id == "rest" && training.contains($0.dayKey)) }
    }

    public func forDay(_ key: String) -> [Workout] { visible.filter { $0.dayKey == key } }

    public func upcoming(from today: String, limit: Int = 20) -> [Workout] {
        Array(visible.filter { $0.dayKey > today }.prefix(limit))
    }

    /* Before today and never recorded. */
    public func outstanding(before today: String) -> [Workout] {
        plan.filter { $0.dayKey < today && $0.discipline.id != "rest" && !$0.logged }
    }

    public func week(of key: String, today: String) -> [PlanDay] {
        let from = Self.weekStart(key)
        return (0..<7).map { i in
            let day = Self.addDays(from, i)
            let sessions = plan.filter { $0.dayKey == day }
            let planned = sessions.filter { $0.discipline.id != "rest" }
                .reduce(0.0) { $0 + (Plan.plannedSeconds($1, mapping) ?? 0) }
            return PlanDay(dayKey: day, date: parseDayKey(day) ?? Date(), isToday: day == today, isPast: day < today,
                           sessions: sessions, training: sessions.filter { $0.discipline.id != "rest" },
                           isRest: !sessions.isEmpty && sessions.allSatisfy { $0.discipline.id == "rest" },
                           plannedSeconds: planned, extras: extras(on: day))
        }
    }

    /* The phase the plan says you are in: today's, or the nearest session before it. */
    public func phase(on today: String) -> String {
        let before = plan.filter { $0.dayKey <= today && !$0.phase.isEmpty }
        return before.last?.phase ?? plan.first(where: { !$0.phase.isEmpty })?.phase ?? ""
    }
}
