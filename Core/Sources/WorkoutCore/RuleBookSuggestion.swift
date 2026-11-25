import Foundation

/*
 * What a check hands back — one card, or silence — and what is kept of it.
 * Codable throughout: the app keeps a log, and the same menu can later be
 * handed to an AI that may only pick from it.
 */

public enum RBTrigger: String, Codable, Equatable, Sendable, CaseIterable {
    /* Section 5: his own taps (stop sign, illness). */ case section5 = "S5"
    /* A session that came into the app already breaking a limit (spec example 11). */ case cameInBreaking = "IN"
    case t1 = "T1", t2 = "T2", t3 = "T3", t4 = "T4", t5 = "T5", t6 = "T6"
    /* "Something hurts" (Q2). */ case hurts = "Q2"
    /* Back-to-back quality, only when Q1 asks for it. */ case backToBack = "Q1"
}

public enum RBLimit: String, Codable, Equatable, Sendable, CaseIterable {
    case l1 = "L1", l2 = "L2", l3 = "L3", l4 = "L4", l5 = "L5", l6 = "L6", l7 = "L7"
    case l8 = "L8", l9 = "L9", l10 = "L10", l11 = "L11", l12 = "L12", l13 = "L13"
}

public struct LimitFailure: Codable, Equatable, Sendable {
    public let limit: RBLimit
    public let reason: String
    public init(_ limit: RBLimit, _ reason: String) { self.limit = limit; self.reason = reason }
}

/* One way to answer a trigger: its moves and the words for them. */
public struct RBChoice: Codable, Equatable, Sendable {
    public let moves: [Move]
    /* "Tue bike: 60 → 40 min, easy" */
    public let headline: String
    public init(moves: [Move], headline: String) { self.moves = moves; self.headline = headline }
}

/* A plan review (T6) is not a move: it opens a before/after page he says yes to. */
public struct RBPlanReview: Codable, Equatable, Sendable {
    public let weeksBehind: Int
    /* "1–2", "3–4" or "5+": which of his guide's options the page shows. */
    public let guideOption: String
}

public struct Suggestion: Codable, Equatable, Sendable {
    public let trigger: RBTrigger
    /* Which rung of a ladder (T1 step 1–3, T3 week 1–2); 0 where there is none. */
    public let step: Int
    public let choice: RBChoice
    /* "Why: you felt poor two mornings running." */
    public let why: String
    /* At most two, each of which also passed every limit. */
    public let otherChoices: [RBChoice]
    public let review: RBPlanReview?
    public let footer: String
    public let record: SuggestionRecord

    public var headline: String { choice.headline }
    public var moves: [Move] { choice.moves }
}

public enum RBAnswer: Codable, Equatable, Sendable {
    /* "Take it": 0 the card's own choice, 1… an other choice. */
    case took(Int)
    case keptPlan
    /* Not answered by the end of the day of the first session it changes: closes as "Keep my plan", silently. */
    case closedUnanswered
}

public struct RBTried: Codable, Equatable, Sendable {
    public let headline: String
    public let failed: [LimitFailure]
}

public struct SuggestionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String { trigger.rawValue + "|" + day + "|" + key }
    public let day: String
    public let trigger: RBTrigger
    public let step: Int
    /* What the card is about, so a cool-down "once per gap / per break / per session" can find it. */
    public let key: String
    public let headline: String
    public let why: String
    /* The card's own choice first, then the other choices. */
    public let choices: [[Move]]
    public let tried: [RBTried]
    /* The sessions it would change. */
    public let sessions: [String]
    /* The last day it may stay open (the day of the first session it changes). */
    public let closesOn: String
    public var answer: RBAnswer?
    public var answeredOn: String?

    public init(day: String, trigger: RBTrigger, step: Int, key: String, headline: String, why: String,
                choices: [[Move]], tried: [RBTried], sessions: [String], closesOn: String,
                answer: RBAnswer? = nil, answeredOn: String? = nil) {
        self.day = day; self.trigger = trigger; self.step = step; self.key = key; self.headline = headline
        self.why = why; self.choices = choices; self.tried = tried; self.sessions = sessions
        self.closesOn = closesOn; self.answer = answer; self.answeredOn = answeredOn
    }

    public func choice(_ i: Int) -> [Move]? { choices.indices.contains(i) ? choices[i] : nil }

    /* Open on `today`: not answered and not yet past its closing day. */
    public func isOpen(on today: String) -> Bool { answer == nil && today <= closesOn }

    /* The day it stopped being open. */
    public var closedOn: String { answeredOn ?? closesOn }

    public var wasKept: Bool {
        switch answer { case .keptPlan?, .closedUnanswered?: return true; default: return false }
    }

    public var wasTaken: Bool { if case .took? = answer { return true } else { return false } }
}
