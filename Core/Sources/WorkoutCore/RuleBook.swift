import Foundation

/*
 * The rule book: the suggestion engine of the training plan.
 *
 * Each morning (and after a logged session, and on Sunday evening) the
 * triggers are asked in a fixed order: his own taps (section 5), a session
 * that came in already breaking a limit, T3, T2, "something hurts", T1, T4,
 * T5, T6, and back-to-back quality when he asked for it. The FIRST trigger
 * that fires builds its candidates in order; each candidate is applied to a
 * copy of the plan and run through every hard limit (L1–L13). The first that
 * passes is the card, the next two that pass are the "Other choice" list. If
 * none passes: silence — and no lower trigger gets a turn that day.
 *
 * Pure: no clock (only the `today` it is handed), no network, no files.
 * Sleep is never read. HRV stays dormant until 8.3's conditions hold.
 */
public enum RuleBook {

    struct Candidate {
        let trigger: RBTrigger
        let step: Int
        let key: String
        let moves: [Move]
        let headline: String
        let why: String
        var review: RBPlanReview? = nil
    }

    /* What a check did, for the log and for `rule-check`. */
    public struct Outcome: Equatable {
        public let fired: RBTrigger?
        public let suggestion: Suggestion?
        public let tried: [RBTried]
    }

    /* The card for this moment, or nil for silence. */
    public static func suggest(_ input: RuleBookInput) -> Suggestion? { evaluate(input).suggestion }

    public static func evaluate(_ input: RuleBookInput) -> Outcome {
        let order: [(RuleBookInput) -> [Candidate]?] = [
            section5, cameInBreaking, t3BackAfterBreak, t2MissedKey, hurts, t1Tired, t4LongTooFar, t5BigWeek,
            t6Behind, backToBack
        ]
        // A trigger whose every candidate fails gives the next one its turn,
        // unless the calm rules (L10, L11) said no: then the day stays silent.
        var silent: Outcome?
        for trigger in order {
            guard let candidates = trigger(input), let first = candidates.first else { continue }
            let outcome = judge(candidates, input: input, fired: first.trigger)
            if outcome.suggestion != nil { return outcome }
            let calm = outcome.tried.contains { $0.failed.contains { $0.limit == .l10 || $0.limit == .l11 } }
            if calm { return silent.map { Outcome(fired: $0.fired, suggestion: nil, tried: $0.tried + outcome.tried) } ?? outcome }
            if silent == nil { silent = outcome } else { silent = Outcome(fired: silent!.fired, suggestion: nil, tried: silent!.tried + outcome.tried) }
        }
        return silent ?? Outcome(fired: nil, suggestion: nil, tried: [])
    }

    static func judge(_ candidates: [Candidate], input: RuleBookInput, fired: RBTrigger) -> Outcome {
        var tried: [RBTried] = []
        var passed: [Candidate] = []
        for c in candidates {
            var failures: [LimitFailure]
            if c.moves.isEmpty {
                failures = limitFailures([], trigger: c.trigger, input: input, only: [.l10, .l11])
                if c.review == nil { failures.append(LimitFailure(.l12, "Nothing to change.")) }
            } else {
                failures = limitFailures(c.moves, trigger: c.trigger, input: input)
            }
            if let w = l13Words([c.headline, c.why, RuleBookWords.footer]) { failures.append(w) }
            tried.append(RBTried(headline: c.headline, failed: failures))
            if failures.isEmpty && !passed.contains(where: { $0.moves == c.moves }) { passed.append(c) }
        }
        guard let card = passed.first else { return Outcome(fired: fired, suggestion: nil, tried: tried) }
        let others = Array(passed.dropFirst().prefix(2))
        let changed = changedSessions(card.moves, input: input)
        let closes = changed.map(\.day).filter { $0 >= input.today }.min() ?? input.today
        let record = SuggestionRecord(
            day: input.today, trigger: card.trigger, step: card.step, key: card.key, headline: card.headline,
            why: card.why, choices: ([card] + others).map(\.moves), tried: tried, sessions: changed.map(\.id),
            closesOn: closes)
        let suggestion = Suggestion(
            trigger: card.trigger, step: card.step, choice: RBChoice(moves: card.moves, headline: card.headline),
            why: card.why, otherChoices: others.map { RBChoice(moves: $0.moves, headline: $0.headline) },
            review: card.review, footer: RuleBookWords.footer, record: record)
        return Outcome(fired: fired, suggestion: suggestion, tried: tried)
    }

    /* The plan's sessions a set of moves would change (as they stand before). */
    static func changedSessions(_ moves: [Move], input: RuleBookInput) -> [RBSession] {
        guard let after = try? apply(moves, to: input.sessions, input: input) else { return [] }
        let new = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return input.sessions.filter { new[$0.id] != $0 }
    }

    // MARK: shared pickers

    /* The order sessions go in (his guide B8), first to go first. */
    static let dropOrder: [RBSlot] = [.thirdRide, .easyRun, .strengthB, .swim, .runQuality, .bikeQuality, .longRun, .longRide]

    /* Open, counted, and something the engine may touch at all. */
    static func touchable(_ s: RBSession, _ input: RuleBookInput) -> Bool {
        let l = labels(s)
        return s.counts && s.status == .open && !l.protectedKind && input.week(of: s.day) != input.settings.raceWeek
    }

    static func dayHoldsKeyOrProtected(_ day: String, _ input: RuleBookInput) -> Bool {
        input.sessions.contains { $0.day == day && $0.counts && (labels($0).key || labels($0).protectedKind) }
    }

    static func openSessions(on day: String, _ input: RuleBookInput) -> [RBSession] {
        input.sessions.filter { $0.day == day && $0.counts && $0.status == .open }
    }

    /* Already as easy as M4 would make it. */
    static func alreadyEasy(_ s: RBSession) -> Bool {
        let z = zones(s.intensity)
        if s.sport == .strength { return (z.rpeTop ?? 0) <= 5 && (z.rpeTop ?? 0) > 0 }
        return (z.top ?? 9) <= 2 && (z.low ?? 9) <= 1
    }

    static func lastRecord(_ trigger: RBTrigger, _ input: RuleBookInput, where match: (SuggestionRecord) -> Bool = { _ in true }) -> SuggestionRecord? {
        input.log.filter { $0.trigger == trigger && $0.day <= input.today && match($0) }.max { $0.day < $1.day }
    }
}
