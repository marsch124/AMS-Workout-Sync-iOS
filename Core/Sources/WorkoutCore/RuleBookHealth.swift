import Foundation

/*
 * Stop signs and the illness return ladder (spec section 5): his own taps,
 * fixed words, and a small state machine that says which step today is on.
 * Nothing here reads a watch number — no pulse, no sleep, nothing can lift a
 * pause but his own "A doctor has seen me".
 */

public enum RBLadder: String, Codable, Equatable, Sendable {
    case none
    /* Stop sign: everything "Paused" until "A doctor has seen me". */ case paused
    /* Step 0: rest until 48 h after "Symptom-free since …". */ case rest
    /* Step 0b: two easy days after fever or chest symptoms. */ case easyDays
    /* A cold above the neck, while it lasts. */ case cold
    case week1, week2
    /* Week 3: the plan as written. */ case back
    /* Out three weeks or more: the plan review instead. */ case outLong
}

public struct RBLadderState: Equatable, Sendable {
    public let step: RBLadder
    /* First and last day of this step ("" when open-ended). */
    public let from: String
    public let to: String
    /* The fixed sentence the plan shows for this step. */
    public var text: String { RuleBookWords.ladderText(step) }
}

public enum RuleBookWords {}

extension RuleBookWords {
    public static let stopSignTitle = "Stop training now."
    public static let stopSignSigns = "Chest pain or pressure · unusual breathlessness · dizziness or fainting · a racing or uneven heartbeat."
    public static let stopSignDoctor = "These need a doctor to look at them before you train again. If it is strong or does not pass, call 112."
    public static let stopSignPause = "The app pauses all training suggestions until you tap \"A doctor has seen me\"."
    public static let stopSignFooter = "Training app, not medical advice."
    public static let stopSignText = [stopSignTitle, stopSignSigns, stopSignDoctor, stopSignPause, stopSignFooter]
    public static let doctorSeenButton = "A doctor has seen me"
    public static let pausedLabel = "Paused"

    public static let illQuestion = "Fever, or chest / body aches?"
    public static let illYes = "Yes"
    public static let illNo = "No, a cold above the neck"
    public static let stillNotRightButton = "Still not right"
    public static let restLabel = "Rest — not until 48 h symptom-free"
    public static let rowInstead = "Row instead, same minutes, easy"

    public static func ladderText(_ step: RBLadder) -> String {
        switch step {
        case .none: return ""
        case .paused: return stopSignPause
        case .rest: return "Rest until 48 hours completely symptom-free. Your guide asks you to respect this strictly."
        case .easyDays: return "Two extra easy days, as your guide says after fever or chest symptoms."
        case .cold: return "Cold above the neck: easy only, shorter, until it has gone."
        case .week1: return "Week 1 back: about half, all easy, no key sessions."
        case .week2: return "Week 2 back: about three quarters, one quality session mid-week."
        case .back: return "Back on your plan."
        case .outLong: return "The whole plan shifts instead (your guide, section 5)."
        }
    }
}

extension RuleBook {

    /*
     * Which step today is on. Days, not hours: "48 h after symptom-free since"
     * is read as the two whole days after that day.
     * OPEN: day-level 48 h (the calmer reading: a little longer, never shorter).
     */
    public static func ladderStep(_ input: RuleBookInput) -> RBLadderState {
        let h = input.health, s = input.settings, today = input.today
        if let stop = h.stopSignSince, stop <= today, (h.doctorSeenOn ?? "") < stop {
            return RBLadderState(step: .paused, from: stop, to: "")
        }
        guard let ill = h.illSince, ill <= today, let kind = h.illness else { return RBLadderState(step: .none, from: "", to: "") }
        guard let free = h.symptomFreeSince, free <= today else {
            return RBLadderState(step: kind == .belowNeck ? .rest : .cold, from: ill, to: "")
        }
        var resume = PlanView.addDays(free, 1)
        if kind == .belowNeck {
            let restDays = max(1, s.feverRestHours / 24)
            let restEnd = PlanView.addDays(free, restDays)
            if today <= restEnd { return RBLadderState(step: .rest, from: ill, to: restEnd) }
            let easyEnd = PlanView.addDays(restEnd, s.feverEasyDays)
            if today <= easyEnd { return RBLadderState(step: .easyDays, from: PlanView.addDays(restEnd, 1), to: easyEnd) }
            resume = PlanView.addDays(easyEnd, 1)
        }
        let off = daysBetween(ill, resume)
        if off >= 21 { return RBLadderState(step: .outLong, from: resume, to: "") }
        guard off >= 7 else { return RBLadderState(step: .none, from: "", to: "") }
        // "Still not right" in week 1 adds three easy days to it.
        let extra = h.stillNotRight.filter { $0 >= resume }.count * s.stillNotRightDays
        let w1End = PlanView.addDays(resume, 6 + extra)
        if today <= w1End { return RBLadderState(step: .week1, from: resume, to: w1End) }
        let w2End = PlanView.addDays(w1End, 7)
        if today <= w2End { return RBLadderState(step: .week2, from: PlanView.addDays(w1End, 1), to: w2End) }
        let backEnd = PlanView.addDays(w2End, 7)
        if today <= backEnd { return RBLadderState(step: .back, from: PlanView.addDays(w2End, 1), to: backEnd) }
        return RBLadderState(step: .none, from: "", to: "")
    }

    /* The open sessions on these days that a ladder step may change (never a sim, the race or race week — L6). */
    static func ladderSessions(_ input: RuleBookInput, days: [String], tests: Bool = true) -> [RBSession] {
        input.sessions.filter { s in
            let l = labels(s)
            return days.contains(s.day) && s.counts && s.status == .open && !l.sim && !l.race && (tests || !l.test)
                && input.week(of: s.day) != input.settings.raceWeek
        }
    }

    /* Week 1 back: half, all easy; keys, bricks and tests dropped. */
    static func ladderWeek1(_ input: RuleBookInput, days: [String], rowInstead: Bool = false, tests: Bool = true) -> [Move] {
        var moves: [Move] = []
        for s in ladderSessions(input, days: days, tests: tests) {
            let l = labels(s)
            if l.key || l.brick || l.test { moves.append(.drop(session: s.id)); continue }
            moves.append(.shorten(session: s.id, minutes: percent(s.plannedMin, 50)))
            moves.append(.makeEasier(session: s.id, instead: rowInstead && s.sport == .run ? .row : nil))
        }
        return moves
    }

    /* Week 2 back: three quarters; all easy but the one mid-week quality session of highest priority. */
    static func ladderWeek2(_ input: RuleBookInput, days: [String], rowInstead: Bool = false, tests: Bool = true) -> [Move] {
        let list = ladderSessions(input, days: days, tests: tests)
        let quality = list.first { $0.slot == .bikeQuality } ?? list.first { $0.slot == .runQuality }
        var moves: [Move] = []
        for s in list {
            moves.append(.shorten(session: s.id, minutes: percent(s.plannedMin, 75)))
            if s.id != quality?.id { moves.append(.makeEasier(session: s.id, instead: rowInstead && s.sport == .run ? .row : nil)) }
        }
        return moves
    }

    /* Easy and shorter at `percent`; keys and tests dropped when `dropKeys`. */
    static func ladderEasy(_ input: RuleBookInput, days: [String], percent n: Int, dropKeys: Bool) -> [Move] {
        var moves: [Move] = []
        for s in ladderSessions(input, days: days) {
            let l = labels(s)
            if dropKeys && (l.key || l.test) { moves.append(.drop(session: s.id)); continue }
            moves.append(.shorten(session: s.id, minutes: percent(s.plannedMin, n)))
            moves.append(.makeEasier(session: s.id, instead: nil))
        }
        return moves
    }

    static func days(from: String, count: Int) -> [String] { (0..<max(0, count)).map { PlanView.addDays(from, $0) } }

    /*
     * Section 5's own cards: one at the start of each step that changes the
     * plan (two easy days, a cold, week 1, week 2, "still not right"). Rest
     * and a pause change nothing — the plan simply shows "Rest" or "Paused".
     */
    static func section5(_ input: RuleBookInput) -> [Candidate]? {
        let state = ladderStep(input)
        let h = input.health
        func done(_ key: String) -> Bool { input.log.contains { $0.trigger == .section5 && $0.key == key } }
        let ill = h.illSince ?? ""
        switch state.step {
        case .easyDays:
            let key = "easy|" + ill
            if done(key) { return nil }
            let d = days(from: input.today, count: daysBetween(input.today, state.to) + 1)
            return [Candidate(trigger: .section5, step: 0, key: key, moves: ladderEasy(input, days: d, percent: 50, dropKeys: true),
                              headline: "Next \(d.count) days easy and at half", why: ladderText(.easyDays))]
        case .cold:
            let key = "cold|" + ill + "|" + String(daysBetween(ill, input.today) / 7)
            if done(key) { return nil }
            let d = days(from: input.today, count: 7)
            return [Candidate(trigger: .section5, step: 0, key: key, moves: ladderEasy(input, days: d, percent: 70, dropKeys: true),
                              headline: "Next 7 days easy and shorter, no key sessions", why: ladderText(.cold))]
        case .week1:
            if let tap = h.stillNotRight.last, tap >= state.from, !done("notright|" + tap) {
                let d = days(from: input.today, count: input.settings.stillNotRightDays)
                let moves = ladderSessions(input, days: d).map { Move.makeEasier(session: $0.id, instead: nil) }
                return [Candidate(trigger: .section5, step: 1, key: "notright|" + tap, moves: moves,
                                  headline: "\(d.count) more easy days", why: "Why: you said you are still not right.")]
            }
            let key = "week1|" + ill
            if done(key) { return nil }
            let d = days(from: input.today, count: 7)
            return [Candidate(trigger: .section5, step: 1, key: key, moves: ladderWeek1(input, days: d),
                              headline: "Next 7 days at half, all easy", why: ladderText(.week1)),
                    Candidate(trigger: .section5, step: 1, key: key, moves: ladderWeek1(input, days: d, rowInstead: true),
                              headline: RuleBookWords.rowInstead, why: ladderText(.week1))]
        case .week2:
            let key = "week2|" + ill
            if done(key) { return nil }
            let d = days(from: input.today, count: 7)
            return [Candidate(trigger: .section5, step: 2, key: key, moves: ladderWeek2(input, days: d),
                              headline: "Next 7 days at three quarters, one quality session", why: ladderText(.week2)),
                    Candidate(trigger: .section5, step: 2, key: key, moves: ladderWeek2(input, days: d, rowInstead: true),
                              headline: RuleBookWords.rowInstead, why: ladderText(.week2))]
        default:
            return nil
        }
    }

    static func ladderText(_ step: RBLadder) -> String { RuleBookWords.ladderText(step) }
}
