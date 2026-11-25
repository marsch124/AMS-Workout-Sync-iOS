import Foundation

/*
 * The Thursday easy rides: a third bike day, one easy ride beside the easy run.
 *
 * It is a rule, not a list. Each plan week says what it is (its phase and its
 * heading), and that alone decides the ride: how long, how hard, or none.
 *
 *   Base 1–2 ........ 45 min Z1–Z2
 *   Base 3 .......... 50, 55, then 60 min Z2, as the block goes on
 *   Build 1 and 2 ... 60 min Z2
 *   Peak ............ 45 min Z2
 *   easy, test, taper weeks .... 30 min Z1 spin
 *   race-practice weeks, race week, anything after the race .... none
 *
 * Nothing here writes to the plan: it only says what would be added, so a page
 * can show it first. A Thursday that already holds such a ride gets no second one.
 */
public enum ThursdayRides {
    public static let purpose = "Easy aerobic bike volume; keeps easy days easy"
    static let tail = "— third ride of the week"

    public struct Ride: Equatable {
        public let minutes: Double
        public let intensity: String
        public let title: String
    }

    /* One plan week, before and after, in minutes. */
    public struct WeekMinutes: Equatable, Identifiable {
        public var id: Int { number }
        public let number: Int
        public let monday: String
        public let before: Double
        public let after: Double
    }

    private enum Kind { case base2, base3, build, peak, spin, none }

    private static func kind(_ w: PlanWeek) -> Kind {
        let tag = normalise(w.tag), phase = normalise(w.phase)
        if tag.contains("race") { return .none }
        if phase.hasPrefix("taper") { return .spin }
        if w.isEasy || w.isTest { return phase.hasPrefix("base") || phase.hasPrefix("build") || phase.hasPrefix("peak") ? .spin : .none }
        if phase.hasPrefix("base 3") { return .base3 }
        if phase.hasPrefix("base") { return .base2 }
        if phase.hasPrefix("build") { return .build }
        if phase.hasPrefix("peak") { return .peak }
        return .none
    }

    private static let easy = Ride(minutes: 45, intensity: "Z1\u{2013}Z2",
                                   title: "Easy ride (trainer or road): conversational \(tail)")
    private static func aerobic(_ minutes: Double) -> Ride {
        Ride(minutes: minutes, intensity: "Z2", title: "Aerobic ride (trainer or road): steady Z2, no efforts \(tail)")
    }
    private static let spin = Ride(minutes: 30, intensity: "Z1",
                                   title: "Easy spin: very easy, high cadence 95\u{2013}105 rpm \(tail)")

    /* The ride for each plan week (by number), for every week the rule gives one. */
    public static func rides(for weeks: [PlanWeek]) -> [Int: Ride] {
        var out: [Int: Ride] = [:]
        var ordinary = 0   // ordinary weeks so far in the current Base 3 block
        var block = ""
        for w in weeks.sorted(by: { $0.monday < $1.monday }) {
            let k = kind(w)
            if normalise(w.phase) != block { block = normalise(w.phase); ordinary = 0 }
            switch k {
            case .base2: out[w.number] = easy
            case .base3:
                out[w.number] = aerobic(ordinary == 0 ? 50 : ordinary < 3 ? 55 : 60)
                ordinary += 1
            case .build: out[w.number] = aerobic(60)
            case .peak: out[w.number] = aerobic(45)
            case .spin: out[w.number] = spin
            case .none: break
            }
        }
        return out
    }

    static func holdsARide(_ s: Workout) -> Bool {
        s.discipline.id == "bike" && (s.planned.description == purpose || s.title.hasSuffix(tail))
    }

    /* The rides to add: Thursdays from `start` on, not where one already is. */
    public static func drafts(weeks: [PlanWeek], sessions: [Workout], from start: String) -> [SessionDraft] {
        let rides = rides(for: weeks)
        var out: [SessionDraft] = []
        for w in weeks.sorted(by: { $0.monday < $1.monday }) {
            guard let ride = rides[w.number] else { continue }
            let thursday = PlanView.addDays(w.monday, 3)
            if thursday < start { continue }
            if sessions.contains(where: { $0.dayKey == thursday && holdsARide($0) }) { continue }
            out.append(SessionDraft(dayKey: thursday, sport: "bike", title: ride.title, minutes: ride.minutes,
                                    intensity: ride.intensity, purpose: purpose, isKey: false))
        }
        return out
    }

    /* Minutes of each week the drafts touch, before and after. */
    public static func weekMinutes(weeks: [PlanWeek], sessions: [Workout], mapping: Mapping,
                                   drafts: [SessionDraft]) -> [WeekMinutes] {
        weeks.sorted(by: { $0.monday < $1.monday }).compactMap { w in
            let days = Set((0..<7).map { PlanView.addDays(w.monday, $0) })
            let added = drafts.filter { days.contains($0.dayKey) }.reduce(0.0) { $0 + ($1.minutes ?? 0) }
            guard added > 0 else { return nil }
            let before = sessions.filter { days.contains($0.dayKey) && $0.discipline.id != "rest" }
                .reduce(0.0) { $0 + (Plan.plannedSeconds($1, mapping) ?? 0) / 60 }
            return WeekMinutes(number: w.number, monday: w.monday, before: before.rounded(), after: (before + added).rounded())
        }
    }
}
