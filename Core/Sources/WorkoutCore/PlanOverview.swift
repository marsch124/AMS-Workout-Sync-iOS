import Foundation

/*
 * The counting behind the Plan page of the wide look (iPad and Mac): the days
 * a month's calendar shows, the months a season spans, planned and done time
 * in a stretch of days, time per sport, how much of the plan was followed so
 * far, and the weeks to the race. Pure counting, no drawing.
 */
public enum PlanOverview {

    /* The number on the "All" filter: rest days are not sessions to do, so they stay out, as in the plan bar. */
    public static func countedInAll(disciplineIds: [String], extras: Int) -> Int {
        disciplineIds.filter { $0 != "rest" }.count + extras
    }

    /*
     * The letter above a week's bar on the season bars: T for a test week,
     * else E for an easy week, else none. (Pale is kept for "still to do".)
     */
    public static func weekLetter(isEasy: Bool, isTest: Bool) -> String? {
        isTest ? "T" : (isEasy ? "E" : nil)
    }

    /* The line under the season bars: only the letters that occur are named; none when the whole words are shown. */
    public static func seasonKey(hasEasy: Bool, hasTest: Bool, lettersShown: Bool) -> String {
        var parts: [String] = []
        if lettersShown {
            if hasEasy { parts.append("E = easy week") }
            if hasTest { parts.append("T = test week") }
        }
        parts.append("Tap a bar to see its week")
        return parts.joined(separator: " \u{00B7} ")
    }

    /* "2026-11" for a day key. */
    public static func month(of day: String) -> String { String(day.prefix(7)) }

    /* The first day of a month ("2026-11" → "2026-11-01"). */
    public static func firstDay(_ month: String) -> String { month + "-01" }

    /* The last day of a month. */
    public static func lastDay(_ month: String) -> String {
        PlanView.addDays(firstDay(adding(1, to: month)), -1)
    }

    /* A month moved by whole months ("2026-12" plus 1 is "2027-01"). */
    public static func adding(_ months: Int, to month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return month }
        let index = parts[0] * 12 + (parts[1] - 1) + months
        return String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }

    /*
     * The month's calendar as rows of seven day keys, Monday to Sunday: the
     * first row holds the 1st, the last row the last day, and the days of the
     * neighbouring months fill the rows out.
     */
    public static func grid(_ month: String) -> [[String]] {
        let first = PlanView.weekStart(firstDay(month))
        let last = lastDay(month)
        var rows: [[String]] = []
        var monday = first
        while monday <= last {
            rows.append((0..<7).map { PlanView.addDays(monday, $0) })
            monday = PlanView.addDays(monday, 7)
        }
        return rows
    }

    /* Every month from the one holding `from` to the one holding `to`, in order. */
    public static func months(from: String, to: String) -> [String] {
        var out: [String] = []
        var m = month(of: from)
        let end = month(of: to)
        while m <= end && out.count < 120 {
            out.append(m)
            m = adding(1, to: m)
        }
        return out
    }

    public struct Hours: Equatable {
        public var planned: Double
        public var done: Double
        public init(planned: Double = 0, done: Double = 0) { self.planned = planned; self.done = done }
    }

    /*
     * Planned time of the sessions from `from` to `to` (both included), rest
     * days left out, and the time of those recorded: what was done where the
     * watch said, else what was planned.
     */
    public static func hours(_ plan: [Workout], _ mapping: Mapping, from: String, to: String) -> Hours {
        var h = Hours()
        for w in plan where w.dayKey >= from && w.dayKey <= to && w.discipline.id != "rest" {
            let planned = Plan.plannedSeconds(w, mapping) ?? 0
            h.planned += planned
            if w.logged && !w.missed { h.done += Stats.actualSeconds(w, mapping) ?? planned }
        }
        return h
    }

    public struct SportHours: Identifiable, Equatable {
        public var id: String { sport }
        public let sport: String
        public let label: String
        public var hours: Hours
    }

    /* Planned and done time per sport in the stretch, the sport with most planned first. */
    public static func bySport(_ plan: [Workout], _ mapping: Mapping, from: String, to: String) -> [SportHours] {
        var out: [String: SportHours] = [:]
        for w in plan where w.dayKey >= from && w.dayKey <= to && w.discipline.id != "rest" {
            let one = hours([w], mapping, from: from, to: to)
            var entry = out[w.discipline.id] ?? SportHours(sport: w.discipline.id, label: w.discipline.label, hours: Hours())
            entry.hours.planned += one.planned
            entry.hours.done += one.done
            out[w.discipline.id] = entry
        }
        return out.values.filter { $0.hours.planned > 0 || $0.hours.done > 0 }
            .sorted { $0.hours.planned != $1.hours.planned ? $0.hours.planned > $1.hours.planned : $0.sport < $1.sport }
    }

    public struct Followed: Equatable {
        public let done: Int
        public let due: Int
        /* Whole per cent, nil while nothing was due. */
        public var percent: Int? { due > 0 ? Int((Double(done) / Double(due) * 100).rounded()) : nil }
    }

    /*
     * Of the sessions in the stretch that were due by today — every one before
     * today, and today's once recorded — how many were recorded as done.
     */
    public static func followed(_ plan: [Workout], from: String, to: String, today: String) -> Followed {
        let due = plan.filter { w in
            w.dayKey >= from && w.dayKey <= to && w.discipline.id != "rest"
                && (w.dayKey < today || (w.dayKey == today && w.logged))
        }
        return Followed(done: due.filter { $0.logged && !$0.missed }.count, due: due.count)
    }

    /*
     * Sessions in the stretch recorded as done on a day still to come: they
     * count in the hours done, but not in "Plan followed", which only counts
     * what was due by today. The Plan page names them so the two agree.
     */
    public static func doneAhead(_ plan: [Workout], from: String, to: String, today: String) -> Int {
        plan.filter { w in
            w.dayKey >= from && w.dayKey <= to && w.dayKey > today && w.discipline.id != "rest"
                && w.logged && !w.missed
        }.count
    }

    /* The day's main session: the longest planned one that is not rest; nil on a rest day or an empty one. */
    public static func main(_ sessions: [Workout], _ mapping: Mapping) -> Workout? {
        sessions.filter { $0.discipline.id != "rest" }
            .max { (Plan.plannedSeconds($0, mapping) ?? 0) < (Plan.plannedSeconds($1, mapping) ?? 0) }
    }

    /* Whole weeks from today to race day, a part week counted as one; nil once the race is past. */
    public static func weeksTo(_ raceDay: String, today: String) -> Int? {
        let days = Stats.daysBetween(today, raceDay)
        guard days >= 0 else { return nil }
        return (days + 6) / 7
    }
}
