import Foundation

/*
 * The questions the screens ask of a plan: what is on a day, what the week
 * looks like, what is still to come. Ported from js/sync.js.
 */

public struct PlanDay: Identifiable {
    public var id: String { dayKey }
    public let dayKey: String
    public let date: Date
    public let isToday: Bool
    public let isPast: Bool
    public let sessions: [Workout]
    public let training: [Workout]
    public let isRest: Bool
    public let plannedSeconds: Double
}

public struct PlanView {
    public let plan: [Workout]
    public let mapping: Mapping

    public init(plan: [Workout], mapping: Mapping) {
        self.plan = plan
        self.mapping = mapping
    }

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
                           plannedSeconds: planned)
        }
    }

    /* The phase the plan says you are in: today's, or the nearest session before it. */
    public func phase(on today: String) -> String {
        let before = plan.filter { $0.dayKey <= today && !$0.phase.isEmpty }
        return before.last?.phase ?? plan.first(where: { !$0.phase.isEmpty })?.phase ?? ""
    }
}
