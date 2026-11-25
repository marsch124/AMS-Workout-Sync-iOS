import Foundation

/*
 * A tap on one of today's workouts on the Body Battery curve (2.7): which
 * page it opens, and where its tap area stands. Pure, so a data test can
 * read it. The tap only opens a page — nothing is logged or changed.
 *
 * The rule follows the one a session's page already uses to offer the day's
 * watch workouts for its log form (same day, same sport, a walk may be the
 * run), but stricter where that one is wide: there a wrong offer costs
 * nothing, here it would open the wrong page.
 */
public enum BodyTap {

    public enum Target: Equatable {
        /* A session of the plan, by its key. */
        case session(String)
        /* An extra outside the plan, by its id. */
        case extra(String)
        /* Nothing in the app matches: the workout's own facts on a small plate. */
        case facts
    }

    /* Garmin's sport key ("trail_running", "lap_swimming") as the app's own sport. */
    public static func sport(ofGarmin type: String) -> String {
        let t = type.lowercased()
        if t.contains("multi") || t.contains("triathlon") || t.contains("brick") { return "multi" }
        if t.contains("swim") { return "swim" }
        if t.contains("cycl") || t.contains("bik") || t.contains("ride") { return "bike" }
        if t.contains("walk") || t.contains("hik") { return "walk" }
        if t.contains("run") { return "run" }
        if t.contains("strength") { return "strength" }
        if t.contains("row") { return "rowing" }
        if t.contains("yoga") || t.contains("pilates") || t.contains("stretch") || t.contains("mobility") || t.contains("flexib") { return "mobility" }
        return "other"
    }

    /* The same sport words for an extra's kind. */
    public static func sport(ofExtra activity: String) -> String {
        switch activity {
        case "swim", "bike", "run", "strength", "rowing": return activity
        case "mobility", "yoga": return "mobility"
        case "walk", "hike": return "walk"
        default: return "other"
        }
    }

    /*
     * What each workout opens, in the order the workouts were given.
     *  1. a session of exactly that sport planned on that day (the first
     *     workout of a sport takes the first such session, the second the second);
     *  2. an extra of that kind on that day;
     *  3. looser: a walk or hike may be that day's run; a swim, ride, run or
     *     a multisport recording may be that day's Brick or Race;
     *  4. otherwise the workout's own facts.
     * Only the same calendar day counts, and a rest day never matches.
     */
    public static func targets(for workouts: [BodyDay.Workout], day: String,
                               sessions: [Workout], extras: [ExtraSummary]) -> [Target] {
        let planned = sessions.filter { $0.dayKey == day && $0.discipline.id != "rest" }
        let outside = extras.filter { $0.dayKey == day }
        var seen: [String: Int] = [:]
        var out = Array(repeating: Target.facts, count: workouts.count)
        for i in workouts.indices.sorted(by: { workouts[$0].start < workouts[$1].start }) {
            let sport = sport(ofGarmin: workouts[i].type)
            let nth = seen[sport, default: 0]
            seen[sport] = nth + 1
            out[i] = target(sport: sport, nth: nth, planned: planned, outside: outside)
        }
        return out
    }

    private static func target(sport: String, nth: Int, planned: [Workout], outside: [ExtraSummary]) -> Target {
        if sport != "other" && sport != "multi" {
            let exact = planned.filter { $0.discipline.id == sport }
            if !exact.isEmpty { return .session(exact[min(nth, exact.count - 1)].key) }
            let kind = outside.filter { self.sport(ofExtra: $0.activity) == sport }
            if !kind.isEmpty { return .extra(kind[min(nth, kind.count - 1)].id) }
        }
        if sport == "walk", let run = planned.first(where: { $0.discipline.id == "run" }) { return .session(run.key) }
        if ["swim", "bike", "run", "multi"].contains(sport),
           let big = planned.first(where: { $0.discipline.id == "brick" || $0.discipline.id == "race" }) { return .session(big.key) }
        return .facts
    }

    /*
     * Where each workout's tap area stands along the curve, in points. Each
     * is centred on its own bar and at least `least` wide (a finger's 44),
     * pushed back inside the card at the edges. Where two neighbours would
     * overlap they share the room: both are cut halfway between their bars.
     * `bars` are the workouts' own bars (start and end along the curve), in
     * time order.
     */
    public static func spans(bars: [(lo: Double, hi: Double)], from left: Double, to right: Double,
                             least: Double = 44) -> [(lo: Double, hi: Double)] {
        var out: [(lo: Double, hi: Double)] = bars.map { b in
            let centre = (b.lo + b.hi) / 2
            let half = max(least / 2, (b.hi - b.lo) / 2 + 4)
            var lo = centre - half, hi = centre + half
            if lo < left { hi += left - lo; lo = left }
            if hi > right { lo -= hi - right; hi = right }
            return (max(lo, left), hi)
        }
        guard out.count > 1 else { return out }
        for i in 1..<out.count where out[i - 1].hi > out[i].lo {
            let a = (bars[i - 1].lo + bars[i - 1].hi) / 2, b = (bars[i].lo + bars[i].hi) / 2
            let cut = (a + b) / 2
            out[i - 1].hi = cut
            out[i].lo = cut
        }
        return out
    }

    /* The plate's rows for a workout the app does not know: name beside figure, top to bottom. */
    public static func facts(_ w: BodyDay.Workout, time: (Date) -> String) -> [(name: String, value: String)] {
        var rows: [(name: String, value: String)] = [("Started", time(w.start))]
        let seconds = w.end.timeIntervalSince(w.start)
        if seconds.isFinite, seconds >= 60 { rows.append(("Lasted", formatDuration((seconds / 60).rounded() * 60))) }
        if let d = w.drain, d.isFinite, d.rounded() > 0 { rows.append(("Body Battery", "−" + BodyPage.whole(d))) }
        else { rows.append(("Body Battery", "no cost from Garmin")) }
        return rows
    }

    /* The plate's heading: Garmin's own name, or the short word when it gave none. */
    public static func title(_ w: BodyDay.Workout) -> String {
        let name = w.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? BodyPage.shortName(type: w.type, name: w.name) : name
    }
}
