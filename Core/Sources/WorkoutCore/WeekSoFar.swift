import Foundation

/*
 * The week so far, per sport: done of planned, Monday to Sunday. It is the
 * Plan page's own "By sport" count (PlanOverview.bySport: rest days left out,
 * done = what the watch said, else what was planned), plus the extras that
 * count as training, as done time only — never as planned. A sport appears
 * only when the plan gives it minutes that week.
 */
public enum WeekSoFar {
    public static func sums(plan: [Workout], extras: [ExtraSummary], mapping: Mapping, today: String) -> [PlanOverview.SportHours] {
        let monday = PlanView.weekStart(today)
        let sunday = PlanView.addDays(monday, 6)
        var out = PlanOverview.bySport(plan, mapping, from: monday, to: sunday).filter { $0.hours.planned > 0 }
        for x in extras where x.isTraining && x.dayKey >= monday && x.dayKey <= sunday {
            if let i = out.firstIndex(where: { $0.sport == x.activity }) { out[i].hours.done += x.seconds }
        }
        return out
    }
}
