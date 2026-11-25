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
    /* The reason written beside each added ride in the list of changes: it is also how the rides are known again. */
    public static let why = "Thursday easy rides"
    static let tail = "— third ride of the week"

    public struct Ride: Equatable {
        public let minutes: Double
        public let intensity: String
        public let title: String
    }

    /* The ride's name in the plan, the same on every device: "App!thu-<its Monday>". */
    public static func key(for draft: SessionDraft) -> String {
        PlanBook.appSheet + "!thu-" + PlanView.weekStart(draft.dayKey)
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
            // "Base 3 · Recovery" is still Base 3: the steps go on, they do not start again.
            let name = normalise(w.phase).hasPrefix("base 3") ? "base 3" : normalise(w.phase)
            if name != block { block = name; ordinary = 0 }
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

    /*
     * The days that hold, or held, a ride this rule added — wherever it is now.
     * A ride he moved to Friday, renamed or took out of the plan still counts
     * for its week: the rule never offers that week a second time. Only an
     * Undo of the adding itself frees the week again.
     */
    static func servedDays(sessions: [Workout], changes: [PlanChange]) -> [String] {
        var days: [String] = []
        for add in changes where add.kind == "add" && add.why == why && !add.undone {
            if let now = sessions.first(where: { $0.key == add.key }) {
                days.append(now.dayKey)
            } else if let out = changes.last(where: { $0.kind == "remove" && $0.key == add.key && $0.undo != nil }),
                      let was = out.undo {
                days.append(was.dayKey)
            }
        }
        return days
    }

    /* The rides to add: Thursdays from `start` on, not in a week that has, or had, its ride. */
    public static func drafts(weeks: [PlanWeek], sessions: [Workout], changes: [PlanChange] = [],
                              from start: String) -> [SessionDraft] {
        let rides = rides(for: weeks)
        let served = servedDays(sessions: sessions, changes: changes)
        var out: [SessionDraft] = []
        for w in weeks.sorted(by: { $0.monday < $1.monday }) {
            guard let ride = rides[w.number] else { continue }
            // The week's heading may not start on a Monday: the Thursday is counted from the real Monday.
            let monday = PlanView.weekStart(w.monday)
            let thursday = PlanView.addDays(monday, 3)
            if thursday < start { continue }
            let sunday = PlanView.addDays(monday, 6)
            if served.contains(where: { $0 >= monday && $0 <= sunday }) { continue }
            if sessions.contains(where: { $0.dayKey >= monday && $0.dayKey <= sunday && holdsARide($0) }) { continue }
            out.append(SessionDraft(dayKey: thursday, sport: "bike", title: ride.title, minutes: ride.minutes,
                                    intensity: ride.intensity, purpose: purpose, isKey: false))
        }
        return out
    }

    /* Minutes of each week the drafts touch, before and after. */
    public static func weekMinutes(weeks: [PlanWeek], sessions: [Workout], mapping: Mapping,
                                   drafts: [SessionDraft]) -> [WeekMinutes] {
        weeks.sorted(by: { $0.monday < $1.monday }).compactMap { w in
            let days = Set((0..<7).map { PlanView.addDays(PlanView.weekStart(w.monday), $0) })
            let added = drafts.filter { days.contains($0.dayKey) }.reduce(0.0) { $0 + ($1.minutes ?? 0) }
            guard added > 0 else { return nil }
            let before = sessions.filter { days.contains($0.dayKey) && $0.discipline.id != "rest" }
                .reduce(0.0) { $0 + (Plan.plannedSeconds($1, mapping) ?? 0) / 60 }
            return WeekMinutes(number: w.number, monday: w.monday, before: before.rounded(), after: (before + added).rounded())
        }
    }
}
