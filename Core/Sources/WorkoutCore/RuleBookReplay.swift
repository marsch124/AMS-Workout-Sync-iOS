import Foundation

/*
 * Walking past days as if each were "today": what would the rule book have
 * said, knowing only what was known by then? Used by `rule-check` on a copy
 * of the real plan and by the worked-example tests.
 *
 * Logs dated today or later are taken away in the morning (later than today
 * in the evening); morning answers and extras are only read up to the day.
 * A card nobody answers closes as "Keep my plan" at the end of the day of the
 * first session it changes, as it would in the app.
 */
extension RuleBook {

    public struct ReplayLine: Equatable {
        public let day: String
        public let moment: RBMoment
        public let outcome: Outcome
    }

    static func asKnown(_ sessions: [RBSession], today: String, moment: RBMoment) -> [RBSession] {
        sessions.map { s in
            let unknown = moment == .morning ? s.day >= today : s.day > today
            guard unknown, s.status == .done || s.status == .missed else { return s }
            var t = s
            t.status = .open; t.actualMin = nil; t.rpe = nil
            return t
        }
    }

    /*
     * Each day from `from` to `to`, morning then evening. `answer` decides what
     * he says to a card (nil: leaves it, so it closes as "Keep my plan").
     */
    public static func replay(_ base: RuleBookInput, from: String, to: String,
                              answer: ((Suggestion) -> RBAnswer?)? = nil) -> [ReplayLine] {
        var out: [ReplayLine] = []
        var log = base.log
        var sessions = base.sessions
        var day = from
        while day <= to {
            for moment in [RBMoment.morning, .evening] {
                for i in log.indices where log[i].answer == nil && log[i].closesOn < day {
                    log[i].answer = .closedUnanswered; log[i].answeredOn = log[i].closesOn
                }
                var input = base
                input.today = day
                input.moment = moment
                input.log = log
                input.sessions = asKnown(sessions, today: day, moment: moment)
                let outcome = evaluate(input)
                out.append(ReplayLine(day: day, moment: moment, outcome: outcome))
                guard let card = outcome.suggestion else { continue }
                var record = card.record
                if let a = answer?(card) {
                    record.answer = a; record.answeredOn = day
                    if case .took(let i) = a, let moves = record.choice(i),
                       let changed = try? apply(moves, to: sessions, input: input) {
                        sessions = changed
                    }
                }
                log.append(record)
            }
            day = PlanView.addDays(day, 1)
        }
        return out
    }
}
