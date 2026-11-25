import Foundation

/*
 * "Repeat every week until …": the days a session would be added on, and the
 * days that are left out and why. Nothing here writes to the plan.
 *
 * The first day is the session itself; the repeats start one week later.
 * Left out: a day that already holds the same sport + title, a day in race
 * week, a day outside the plan (before its first week or after its last day).
 */
public enum RepeatRule {
    public enum Reason: Equatable { case alreadyThere, raceWeek, outsidePlan }

    public struct LeftOut: Equatable {
        public let day: String
        public let reason: Reason
    }

    public struct Result: Equatable {
        public var days: [String] = []
        public var leftOut: [LeftOut] = []
    }

    /* The last day of the plan: the Sunday of its last week. */
    public static func lastDay(of weeks: [PlanWeek]) -> String? {
        weeks.map(\.monday).max().map { PlanView.addDays($0, 6) }
    }

    /* Eight weeks ahead, never past the plan's last day. */
    public static func defaultUntil(from start: String, weeks: [PlanWeek]) -> String {
        let eight = PlanView.addDays(start, 56)
        guard let last = lastDay(of: weeks) else { return eight }
        return min(eight, last)
    }

    private static func isRaceWeek(_ w: PlanWeek) -> Bool { normalise(w.tag).contains("race week") }

    public static func plan(start: String, until: String, sport: String, title: String,
                            weeks: [PlanWeek], sessions: [Workout]) -> Result {
        var out = Result()
        let want = normalise(title)
        let last = lastDay(of: weeks)
        let first = weeks.map(\.monday).min()
        var day = PlanView.addDays(start, 7)
        var guardCount = 0
        while day <= until, guardCount < 120 {
            guardCount += 1
            defer { day = PlanView.addDays(day, 7) }
            let monday = PlanView.weekStart(day)
            if let last, day > last { out.leftOut.append(LeftOut(day: day, reason: .outsidePlan)); continue }
            if let first, day < first { out.leftOut.append(LeftOut(day: day, reason: .outsidePlan)); continue }
            if let week = weeks.first(where: { $0.monday == monday }), isRaceWeek(week) {
                out.leftOut.append(LeftOut(day: day, reason: .raceWeek)); continue
            }
            if sessions.contains(where: { $0.dayKey == day && $0.discipline.id == sport && normalise($0.title) == want }) {
                out.leftOut.append(LeftOut(day: day, reason: .alreadyThere)); continue
            }
            out.days.append(day)
        }
        return out
    }

    // MARK: the one entry in "Changes to the plan"

    /* All sessions of one repeat carry the same reason line ending in " #<batch>": that is how they are one entry and one Undo. */
    public static func why(title: String, count: Int, batch: String = String(UUID().uuidString.prefix(8))) -> String {
        "Repeated every week: " + title + " (\(count) session\(count == 1 ? "" : "s")) #" + batch
    }

    public static func batch(of why: String) -> String? {
        guard why.hasPrefix("Repeated every week: "), let r = why.range(of: " #", options: .backwards) else { return nil }
        return String(why[r.upperBound...])
    }

    /* The reason line as he reads it, without the batch mark. */
    public static func shownWhy(_ why: String) -> String {
        guard batch(of: why) != nil, let r = why.range(of: " #", options: .backwards) else { return why }
        return String(why[..<r.lowerBound])
    }
}
