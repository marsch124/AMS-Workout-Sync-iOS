import Foundation

/*
 * The thirteen hard limits (spec section 2). Each is a small function run on
 * the plan as it WOULD be after a candidate; it passes (nil) or names itself
 * with a plain reason. A rule card, an AI's pick and (as a calm warning) his
 * own edit all go through the same functions.
 */

struct LimitCase {
    let input: RuleBookInput
    let trigger: RBTrigger
    let moves: [Move]
    let before: [RBSession]
    let after: [RBSession]
    /* Sessions that differ, or were added: (before, after). */
    let changed: [(RBSession?, RBSession)]
    let touchedWeeks: Set<Int>

    init(input: RuleBookInput, trigger: RBTrigger, moves: [Move], before: [RBSession], after: [RBSession]) {
        self.input = input; self.trigger = trigger; self.moves = moves; self.before = before; self.after = after
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed: [(RBSession?, RBSession)] = []
        var weeks = Set<Int>()
        for s in after {
            let b = old[s.id]
            if let b, b == s { continue }
            changed.append((b, s))
            weeks.insert(input.week(of: s.day))
            if let b { weeks.insert(input.week(of: b.day)) }
        }
        self.changed = changed
        self.touchedWeeks = weeks
    }

    var moved: [(RBSession?, RBSession)] { changed.filter { $0.0?.day != $0.1.day } }
}

extension RuleBook {

    static let allLimits: [(RBLimit, (LimitCase) -> LimitFailure?)] = [
        (.l1, l1FridayRest), (.l2, l2NoNewHardPairs), (.l3, l3WeekCap), (.l4, l4Ramp), (.l5, l5LongStep),
        (.l6, l6Protected), (.l7, l7NothingHarder), (.l8, l8NoMakeUp), (.l9, l9MondaySwim),
        (.l10, l10AfterFever), (.l11, l11Calm), (.l12, l12MenuOnly)
    ]

    // L1 · Friday is rest: no move leaves a training session on a Friday.
    static func l1FridayRest(_ c: LimitCase) -> LimitFailure? {
        for (_, s) in c.moved where s.counts && isFriday(s.day) {
            return LimitFailure(.l1, "Friday is your rest day.")
        }
        return nil
    }

    // L2 · no new hard days in a row (the plan's own pairs are left alone).
    static func hardPairs(_ list: [RBSession], weeks: Set<Int>, _ input: RuleBookInput) -> Int {
        let hardDays = Set(list.filter(isHardLeg).map(\.day))
        return hardDays.filter { d in
            hardDays.contains(PlanView.addDays(d, 1))
                && (weeks.contains(input.week(of: d)) || weeks.contains(input.week(of: PlanView.addDays(d, 1))))
        }.count
    }

    static func l2NoNewHardPairs(_ c: LimitCase) -> LimitFailure? {
        let before = hardPairs(c.before, weeks: c.touchedWeeks, c.input)
        let after = hardPairs(c.after, weeks: c.touchedWeeks, c.input)
        return after > before ? LimitFailure(.l2, "It would put two hard days in a row.") : nil
    }

    // L3 · week cap: a week's planned minutes stay within what the plan first gave it.
    // OPEN: a move that does not add minutes is not blocked by a week that was already over its cap.
    static func l3WeekCap(_ c: LimitCase) -> LimitFailure? {
        for w in c.touchedWeeks.sorted() {
            guard let cap = c.input.weekCaps[w] else { continue }
            let after = c.input.plannedMinutes(week: w, in: c.after)
            let before = c.input.plannedMinutes(week: w, in: c.before)
            if after > cap && after > before {
                return LimitFailure(.l3, "That week would go over its planned time (\(after) of \(cap) min).")
            }
        }
        return nil
    }

    // L4 · ramp ceiling for a change that adds minutes to a week.
    static func l4Ramp(_ c: LimitCase) -> LimitFailure? {
        for w in c.touchedWeeks.sorted() {
            let after = c.input.plannedMinutes(week: w, in: c.after)
            guard after > c.input.plannedMinutes(week: w, in: c.before) else { continue }
            let last = c.input.todayWeek - 1
            guard last >= 1, let mean = c.input.meanCounted(before: last + 1, count: c.input.settings.rampWeeks), mean > 0 else { continue }
            if Double(after) > c.input.settings.rampCeiling * mean {
                return LimitFailure(.l4, "That week would grow faster than your recent weeks allow.")
            }
        }
        return nil
    }

    // L5 · long run / long ride one step at a time (Q4). Read on the long sessions a move lengthens or moves.
    // OPEN: a move that shortens a long session is never blocked by L5, even if still above the step.
    static func l5LongStep(_ c: LimitCase) -> LimitFailure? {
        guard c.input.settings.longSessionsGrowSlowly else { return nil }
        for (b, s) in c.changed where s.counts && labels(s).long && (s.sport == .bike || s.sport == .run) {
            let lengthened = b.map { s.plannedMin > $0.plannedMin || s.day != $0.day } ?? true
            guard lengthened, let ref = c.input.longReference(sport: s.sport, before: s.day) else { continue }
            let limit = ref + c.input.longStep(sport: s.sport, ref: ref)
            if s.plannedMin > limit {
                return LimitFailure(.l5, "Long sessions grow a step at a time (\(limit) min for now).")
            }
        }
        return nil
    }

    // L6 · protected sessions are never cut, shortened, made easier or moved; easy weeks and the taper only get easier.
    static func l6Protected(_ c: LimitCase) -> LimitFailure? {
        let input = c.input
        let section5 = c.trigger == .section5
        for move in c.moves {
            guard case .bringEasyWeekForward(let from, let easyWeek) = move else { continue }
            let w = input.week(of: from)
            guard input.tag(w) == .load, !input.isTaper(w), input.tag(easyWeek) == .easy else {
                return LimitFailure(.l6, "This week cannot be swapped for an easy week.")
            }
            let phases = input.weeks.sorted { $0.number < $1.number }.map(\.phase).reduce(into: [String]()) {
                if $0.last != $1 { $0.append($1) }
            }
            if let a = phases.firstIndex(of: input.weekInfo(w)?.phase ?? ""),
               let b = phases.firstIndex(of: input.weekInfo(easyWeek)?.phase ?? ""), b - a > 1 {
                return LimitFailure(.l6, "The next easy week is too far ahead.")
            }
        }
        let laterEasyWeekMoves = !input.settings.laterEasyWeekStaysEasy
            && c.moves.contains { if case .bringEasyWeekForward = $0 { return true } else { return false } }
        for (b, s) in c.changed {
            guard let b else { continue }
            let l = labels(b)
            let raceWeek = input.week(of: b.day) == input.settings.raceWeek
            // OPEN: the illness ladder (section 5) may drop tests and key sessions, but never a sim, the race or race week.
            if l.sim || l.race || raceWeek || (l.test && !section5) {
                return LimitFailure(.l6, "\(dayWord(b.day)) \(sportWord(b)) is protected.")
            }
            let gentleOnly = input.tag(b.originalWeek) == .easy || input.isTaper(b.originalWeek)
            if gentleOnly && !section5 && !laterEasyWeekMoves && (s.dropped || s.day != b.day) {
                return LimitFailure(.l6, "Sessions in an easy week may get easier, never go.")
            }
        }
        return nil
    }

    // L7 · nothing harder or longer, and no new session.
    static func l7NothingHarder(_ c: LimitCase) -> LimitFailure? {
        for (b, s) in c.changed {
            guard let b else {
                if s.addedByMove { continue }
                return LimitFailure(.l7, "No session is ever added.")
            }
            if s.plannedMin > b.plannedMin { return LimitFailure(.l7, "Nothing gets longer than planned.") }
            let top = { (x: RBSession) -> Int in
                x.sport == .strength ? (zones(x.intensity).rpeTop ?? 0) : (zones(x.intensity).top ?? 0)
            }
            if top(s) > top(b) { return LimitFailure(.l7, "Nothing gets harder than planned.") }
        }
        return nil
    }

    // L8 · no make-up: nothing from before today comes back on or after today — except T2's swap.
    static func l8NoMakeUp(_ c: LimitCase) -> LimitFailure? {
        for (b, s) in c.moved {
            guard let b, s.counts, b.day < c.input.today, s.day >= c.input.today else { continue }
            if c.trigger == .t2, c.input.week(of: b.day) == c.input.week(of: s.day),
               c.after.contains(where: { $0.day == s.day && $0.dropped && $0.id != s.id && !labels($0).key }) {
                continue
            }
            return LimitFailure(.l8, "Missed sessions are not made up.")
        }
        return nil
    }

    // L9 · the Monday swim never goes two weeks running.
    static func l9MondaySwim(_ c: LimitCase) -> LimitFailure? {
        for (b, s) in c.changed where b?.slot == .swim {
            guard let b else { continue }
            let w = c.input.week(of: b.day)
            let leaves = s.dropped || c.input.week(of: s.day) != w
            guard leaves else { continue }
            let lastWeek = c.after.filter { $0.slot == .swim && c.input.week(of: $0.day) == w - 1 }
            if lastWeek.contains(where: { $0.status == .missed || $0.dropped }) {
                return LimitFailure(.l9, "Last week's swim did not happen; this one stays.")
            }
        }
        return nil
    }

    // L10 · 48 hours after fever: nothing but section 5.
    static func l10AfterFever(_ c: LimitCase) -> LimitFailure? {
        guard c.trigger != .section5 else { return nil }
        switch ladderStep(c.input).step {
        case .rest, .paused: return LimitFailure(.l10, "Rest until 48 hours completely symptom-free.")
        default: return nil
        }
    }

    // L11 · calm: one open card, one a day, two a week, none in race week, and a taken change is left alone a week.
    static func l11Calm(_ c: LimitCase) -> LimitFailure? {
        guard c.trigger != .section5 else { return nil }
        let input = c.input, s = input.settings
        if input.todayWeek == s.raceWeek { return LimitFailure(.l11, "No suggestions in race week.") }
        if input.log.contains(where: { $0.isOpen(on: input.today) }) {
            return LimitFailure(.l11, "A suggestion is already open.")
        }
        if input.log.filter({ $0.day == input.today }).count >= s.cardsPerDay {
            return LimitFailure(.l11, "One suggestion a day is enough.")
        }
        let weekAgo = PlanView.addDays(input.today, -6)
        if input.log.filter({ $0.day >= weekAgo && $0.day <= input.today && $0.trigger != .section5 }).count >= s.cardsPerSevenDays {
            return LimitFailure(.l11, "Two suggestions a week is enough.")
        }
        let since = PlanView.addDays(input.today, -s.untouchedAfterTakenDays)
        let recent = Set(input.log.filter { $0.wasTaken && $0.closedOn > since }.flatMap(\.sessions))
        if c.changed.contains(where: { recent.contains($0.1.id) }) {
            return LimitFailure(.l11, "That session was changed in the last week; it is left alone.")
        }
        return nil
    }

    // L12 · menu only: each trigger may use only its own moves (the type already holds the menu to M1–M7).
    static let menu: [RBTrigger: Set<String>] = [
        .section5: ["M1", "M3", "M4"], .cameInBreaking: ["M1"], .t1: ["M2", "M3", "M4", "M6", "M7"],
        .t2: ["M1", "M3", "M5"], .t3: ["M1", "M3", "M4"], .t4: ["M3", "M4"], .t5: ["M3", "M4"], .t6: [],
        .hurts: ["M1", "M4"], .backToBack: ["M2", "M5"], .away: ["M1", "M2", "M5"]
    ]

    static func l12MenuOnly(_ c: LimitCase) -> LimitFailure? {
        let allowed = menu[c.trigger] ?? []
        if let m = c.moves.first(where: { !allowed.contains($0.code) }) {
            return LimitFailure(.l12, "\(m.code) is not on the menu for \(c.trigger.rawValue).")
        }
        return nil
    }

    // L13 · no doctor talk, and the footer on every card.
    static let doctorWords = ["healthy", "fit", "safe", "your heart"]

    public static func l13Words(_ texts: [String]) -> LimitFailure? {
        for t in texts {
            let words = " " + normalise(t) + " "
            if let w = doctorWords.first(where: { words.contains(" " + $0 + " ") }) {
                return LimitFailure(.l13, "The words must not say \"\(w)\".")
            }
        }
        return nil
    }

    // MARK: running them

    static func limitFailures(_ moves: [Move], trigger: RBTrigger, input: RuleBookInput,
                              only: Set<RBLimit>? = nil) -> [LimitFailure] {
        let after: [RBSession]
        do { after = try apply(moves, to: input.sessions, input: input) }
        catch { return [LimitFailure(.l12, "That move does not fit the plan.")] }
        let c = LimitCase(input: input, trigger: trigger, moves: moves, before: input.sessions, after: after)
        return allLimits.filter { only?.contains($0.0) ?? true }.compactMap { $0.1(c) }
    }

    /*
     * Any proposed change — an AI's pick or a card's own — against all the
     * limits. Empty means it passes. An AI's pick that returns anything here
     * is refused and the rules' own card stands.
     */
    public static func check(_ proposed: [Move], for trigger: RBTrigger, input: RuleBookInput,
                             words: [String] = []) -> [LimitFailure] {
        var out = limitFailures(proposed, trigger: trigger, input: input)
        if let w = l13Words(words) { out.append(w) }
        return out
    }

    public static func check(_ proposed: Move, for trigger: RBTrigger, input: RuleBookInput) -> [LimitFailure] {
        check([proposed], for: trigger, input: input)
    }

    /*
     * His own edit, the plan before and after: never blocked, but one calm
     * grey line when it breaks L1, L2, L3, L6 or L8 ("Friday is your rest day.
     * Move anyway?"). Only the first line is meant to be shown.
     */
    public static func warnings(before: [RBSession], after: [RBSession], input: RuleBookInput) -> [String] {
        let c = LimitCase(input: input, trigger: .t1, moves: [], before: before, after: after)
        let checks: [(LimitCase) -> LimitFailure?] = [l1FridayRest, l2NoNewHardPairs, l3WeekCap, l6Protected, l8NoMakeUp]
        return checks.compactMap { $0(c) }.map { RuleBookWords.ownEditWarning($0) }
    }
}
