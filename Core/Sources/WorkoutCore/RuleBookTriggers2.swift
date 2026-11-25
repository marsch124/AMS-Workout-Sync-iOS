import Foundation

/*
 * Triggers T4–T6, "something hurts" (Q2), back-to-back quality (Q1), and the
 * one-time card for a session that came into the app already breaking a limit.
 *
 * Not triggers, on purpose (spec section 4): sleep hours, resting pulse (unless
 * Q5 lets it count with a morning answer), Body Battery, stress, a single HRV
 * value, one bad morning, one hard session, a missed single day, doing more
 * than planned, the short-vs-long-term load ratio. Nothing here reads them.
 */
extension RuleBook {

    // MARK: T4 · a long session too far ahead

    static func t4LongTooFar(_ input: RuleBookInput) -> [Candidate]? {
        let s = input.settings
        guard s.longSessionsGrowSlowly, input.moment == .morning, !input.easyStretch(input.today) else { return nil }
        let today = input.today, tomorrow = PlanView.addDays(today, 1)
        let longs = input.sessions.filter {
            ($0.day == today || $0.day == tomorrow) && ($0.sport == .bike || $0.sport == .run) && labels($0).long
                && touchable($0, input)
        }.sorted { ($0.day, $0.row) < ($1.day, $1.row) }
        for l in longs {
            if input.log.contains(where: { $0.trigger == .t4 && $0.key == l.id }) { continue }
            // After "Keep my plan", silent for that sport for 14 days.
            if input.log.contains(where: { r in
                r.trigger == .t4 && r.wasKept && daysBetween(r.closedOn, today) < s.longCoolDownDays
                    && input.session(r.key)?.sport == l.sport
            }) { continue }
            guard let ref = input.longReference(sport: l.sport, before: l.day) else { continue }
            let limit = ref + input.longStep(sport: l.sport, ref: ref)
            guard l.plannedMin > limit else { continue }
            // OPEN: when the step lies below his guide's 70 % floor, the floor wins (B22).
            let floor = percent(l.plannedMin, s.longFloorPercent)
            let target = max(roundTo5(Double(limit)), floor)
            let aboveZ2 = (zones(l.intensity).top ?? 0) > 2
            let why = RuleBookWords.whyLong(sport: l.sport, longest: ref)
            var first: [Move] = [.shorten(session: l.id, minutes: target)]
            if aboveZ2 { first.append(.makeEasier(session: l.id, instead: nil)) }
            var out = [Candidate(trigger: .t4, step: 0, key: l.id, moves: first,
                                 headline: RuleBookWords.easierLine(l, minutes: target, easier: aboveZ2), why: why)]
            if aboveZ2 {
                out.append(Candidate(trigger: .t4, step: 0, key: l.id, moves: [.makeEasier(session: l.id, instead: nil)],
                                     headline: RuleBookWords.easierLine(l, minutes: nil, easier: true), why: why))
            }
            if floor != target {
                out.append(Candidate(trigger: .t4, step: 0, key: l.id, moves: [.shorten(session: l.id, minutes: floor)],
                                     headline: RuleBookWords.easierLine(l, minutes: floor, easier: false), why: why))
            }
            return out
        }
        return nil
    }

    // MARK: T5 · a big week (hikes included)

    static func t5BigWeek(_ input: RuleBookInput) -> [Candidate]? {
        let s = input.settings, w = input.todayWeek
        guard input.moment == .morning, weekday(input.today) == 0, w >= 2, !input.easyStretch(input.today) else { return nil }
        let tag = input.tag(w)
        if tag == .easy || tag == .race || input.isTaper(w) { return nil }
        if input.log.contains(where: { $0.trigger == .t5 && daysBetween($0.day, input.today) < s.bigWeekCoolDownDays }) { return nil }
        let last = w - 1
        guard let cap = input.weekCaps[last], cap > 0,
              let mean = input.meanCounted(before: last, count: s.bigWeekAverageWeeks), mean > 0 else { return nil }
        let counted = Double(input.countedMinutes(week: last))
        guard counted >= s.bigWeekFactor * Double(cap), counted >= s.bigWeekFactor * mean else { return nil }

        let lastMonday = input.monday(of: last)
        let hikes = input.extras.contains { $0.activity == "hike" && $0.day >= lastMonday && $0.day < input.monday(of: w) && input.countsExtra($0) }
        let why = RuleBookWords.whyBigWeek(ratio: counted / Double(cap), hikes: hikes)
        let monday = input.monday(of: w)
        let week = Set((0..<7).map { PlanView.addDays(monday, $0) })
        let base = input.weekInfo(w).map { normalise($0.phase).contains("base") } ?? true
        let pool = input.sessions.filter { week.contains($0.day) && $0.day >= input.today && touchable($0, input) && !labels($0).key }
        var picks: [RBSession] = []
        for slot in dropOrder where slot != .swim || base {
            picks += pool.filter { $0.slot == slot }.sorted { ($0.day, $0.row) < ($1.day, $1.row) }
        }
        guard !picks.isEmpty else { return nil }
        return picks.prefix(3).map { p in
            let m = percent(p.plannedMin, 70)
            return Candidate(trigger: .t5, step: 0, key: "week|\(last)",
                             moves: [.shorten(session: p.id, minutes: m), .makeEasier(session: p.id, instead: nil)],
                             headline: RuleBookWords.easierLine(p, minutes: m, easier: true), why: why)
        }
    }

    // MARK: T6 · behind the plan (Sunday evening, a review, not a daily move)

    static func t6Behind(_ input: RuleBookInput) -> [Candidate]? {
        // Switched off for now (the coach's review): only "Keep my plan", every Sunday, and unlogged weeks read as behind.
        guard input.settings.planReviewOn, input.moment == .evening, weekday(input.today) == 6,
              !input.easyStretch(input.today) else { return nil }
        let w = input.todayWeek
        if input.log.contains(where: { $0.trigger == .t6 && $0.key == "week|\(w)" }) { return nil }
        var behind = 0
        var n = w
        while n >= 1, let cap = input.weekCaps[n], cap > 0,
              Double(input.countedMinutes(week: n)) < input.settings.behindFraction * Double(cap) {
            behind += 1; n -= 1
        }
        let longOff = gapBefore(PlanView.addDays(input.today, 1), input) >= 21 || ladderStep(input).step == .outLong
        if longOff { behind = max(behind, 3) }
        guard behind >= 1 else { return nil }
        let option = behind <= 2 ? "1–2" : (behind <= 4 ? "3–4" : "5+")
        var c = Candidate(trigger: .t6, step: 0, key: "week|\(w)", moves: [], headline: RuleBookWords.reviewLine(weeks: behind),
                          why: RuleBookWords.whyBehind(weeks: behind))
        c.review = RBPlanReview(weeksBehind: behind, guideOption: option)
        return [c]
    }

    // MARK: Q2 · "something hurts"

    static func hurts(_ input: RuleBookInput) -> [Candidate]? {
        guard input.settings.somethingHurtsTap,
              let tap = input.hurtDays.filter({ $0 <= input.today && $0 >= PlanView.addDays(input.today, -1) }).max(),
              !input.log.contains(where: { $0.trigger == .hurts && $0.key == tap }) else { return nil }
        let end = PlanView.addDays(input.today, 6)
        guard let run = input.sessions.filter({ $0.slot == .easyRun && $0.day >= input.today && $0.day <= end && touchable($0, input) })
            .min(by: { $0.day < $1.day }) else { return nil }
        let why = RuleBookWords.whyHurts
        return [Candidate(trigger: .hurts, step: 0, key: tap, moves: [.makeEasier(session: run.id, instead: .row)],
                          headline: RuleBookWords.easierLine(run, minutes: nil, easier: true, instead: .row), why: why),
                Candidate(trigger: .hurts, step: 0, key: tap, moves: [.makeEasier(session: run.id, instead: .easySpin)],
                          headline: RuleBookWords.easierLine(run, minutes: nil, easier: true, instead: .easySpin), why: why),
                Candidate(trigger: .hurts, step: 0, key: tap, moves: [.drop(session: run.id)],
                          headline: RuleBookWords.dropLine(run), why: why)]
    }

    // MARK: Q1 · back-to-back quality, only when he asked for the run quality on Thursday

    static func backToBack(_ input: RuleBookInput) -> [Candidate]? {
        guard !input.settings.keepBackToBackQuality, input.moment == .morning else { return nil }
        let w = input.todayWeek
        if input.log.contains(where: { $0.trigger == .backToBack && $0.key == "week|\(w)" }) { return nil }
        let monday = input.monday(of: w)
        let thursday = PlanView.addDays(monday, 3)
        guard let run = input.sessions.first(where: {
            $0.slot == .runQuality && input.week(of: $0.day) == w && $0.day >= input.today && $0.day < thursday
                && touchable($0, input) && isHardLeg($0)
        }), input.sessions.contains(where: { $0.day == PlanView.addDays(run.day, -1) && isHardLeg($0) }) else { return nil }
        let why = RuleBookWords.whyBackToBack
        var out = [Candidate(trigger: .backToBack, step: 0, key: "week|\(w)", moves: [.moveToDay(session: run.id, day: thursday)],
                             headline: RuleBookWords.moveLine(run, to: thursday), why: why)]
        if let e = nextEasy(after: run, input) {
            out.append(Candidate(trigger: .backToBack, step: 0, key: "week|\(w)", moves: [.swapWithNextEasy(session: run.id, easy: e.id)],
                                 headline: RuleBookWords.swapLine(run, e), why: why))
        }
        return out
    }

    // MARK: a session that came in already breaking a limit (once, at import)

    /*
     * When the plan is taken in, a session from a week already over that now
     * sits today or later (a make-up, L8) gets one card: rest. Only the first
     * such session, only in the week after import; his own later moves get a
     * grey warning line instead, never a card.
     * OPEN: the spec shows this only as worked example 11; read as "at import".
     */
    static func cameInBreaking(_ input: RuleBookInput) -> [Candidate]? {
        guard let imported = input.importDay, input.today >= imported, daysBetween(imported, input.today) < 7,
              !input.log.contains(where: { $0.trigger == .cameInBreaking }) else { return nil }
        let w = input.todayWeek
        guard let s = input.sessions.filter({
            $0.day >= input.today && $0.originalWeek < w && $0.originalWeek < input.week(of: $0.day) && touchable($0, input)
        }).min(by: { ($0.day, $0.row) < ($1.day, $1.row) }) else { return nil }
        let easy = input.tag(input.week(of: s.day)) == .easy
        return [Candidate(trigger: .cameInBreaking, step: 0, key: s.id, moves: [.drop(session: s.id)],
                          headline: RuleBookWords.dropLine(s), why: RuleBookWords.whyCameIn(easyWeek: easy, isRun: s.sport == .run))]
    }
}
