import Foundation

/*
 * The steps back after illness, as a staircase. Nothing is invented here: the
 * steps are the rule book's own (RuleBook.ladderStep), asked day by day, so
 * what is drawn is exactly what the plan does. After fever or chest symptoms:
 * rest until 48 hours symptom-free, two easy days, week 1 (about half, all
 * easy), week 2 (about three quarters), back on the plan. After a cold above
 * the neck: easy and shorter while it lasts, then the same weeks (only when
 * he was out a week or more — a shorter illness has no weeks).
 */
public enum ReturnLadder {

    public enum State: Equatable { case done, current, ahead }

    public struct Stair: Equatable, Identifiable {
        public var id: Int { number }
        public let number: Int
        public let step: RBLadder
        public let state: State
        /* First and last day; "" when not known yet (a step that starts when he is symptom-free). */
        public let from: String
        public let to: String
        /* How many days it lasts, when known. */
        public let days: Int?
        public let title: String
        public let words: String
    }

    static func title(_ s: RBLadder) -> String {
        switch s {
        case .rest: return "Rest"
        case .easyDays: return "Two easy days"
        case .cold: return "Cold: easy and shorter"
        case .week1: return "Week 1 back"
        case .week2: return "Week 2 back"
        case .back: return "Back on your plan"
        default: return ""
        }
    }

    static let shown: Set<RBLadder> = [.rest, .easyDays, .cold, .week1, .week2, .back]

    /* The stairs of the return that is running; empty when none is (no illness, a pause, or out for three weeks or more). */
    public static func stairs(health: RBHealthTaps, settings: RuleBookSettings, today: String) -> [Stair] {
        func step(_ h: RBHealthTaps, _ day: String) -> RBLadderState {
            RuleBook.ladderStep(RuleBookInput(sessions: [], weeks: [], planStart: day, weekCaps: [:], today: day,
                                              health: h, settings: settings))
        }
        let now = step(health, today)
        guard shown.contains(now.step), let ill = health.illSince else { return [] }

        // With the symptom-free day not yet known, the steps ahead are those he would have if it were today.
        var plan = health
        let known = health.symptomFreeSince != nil
        if !known { plan.symptomFreeSince = max(today, ill) }

        var runs: [(step: RBLadder, from: String, to: String)] = []
        var day = ill
        for _ in 0..<120 {
            let s = step(plan, day)
            if shown.contains(s.step) {
                if let last = runs.last, last.step == s.step { runs[runs.count - 1].to = day }
                else { runs.append((s.step, day, day)) }
            } else if s.step == .outLong { return [] }
            day = PlanView.addDays(day, 1)
        }
        // The last stair, "back on your plan", is the end of the climb: it ends where the rule ends.
        let currentIndex = runs.firstIndex { $0.step == now.step } ?? 0
        return runs.enumerated().map { i, r in
            let state: State = i < currentIndex ? .done : (i == currentIndex ? .current : .ahead)
            let from = (known || state != .ahead) ? r.from : ""
            let to = (known || state == .done) ? r.to : ""
            let length = RuleBook.daysBetween(r.from, r.to) + 1
            return Stair(number: i + 1, step: r.step, state: state, from: from, to: to,
                         days: (!to.isEmpty || state == .ahead) ? length : nil,
                         title: title(r.step), words: RuleBookWords.ladderText(r.step))
        }
    }
}
