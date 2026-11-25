import Foundation

/*
 * Triggers T1–T3 (spec section 4). Each returns nil when it does not fire,
 * or its candidates in order: the card's own move first, then the "Other
 * choice" list. The limits decide which of them may be shown.
 */
extension RuleBook {

    // MARK: T1 · tired signs (his guide's action ladder)

    static func t1Tired(_ input: RuleBookInput) -> [Candidate]? {
        let today = input.today, w = input.todayWeek, s = input.settings
        let tag = input.tag(w)
        if tag == .easy || tag == .race || input.isTaper(w) { return nil }
        if tag == .test && input.sessions.contains(where: { $0.day == today && labels($0).test }) { return nil }

        let last = lastRecord(.t1, input)
        // Cool-down: after "Keep my plan", silent for 4 days.
        if let last, last.wasKept, daysBetween(last.closedOn, today) < s.tiredCoolDownDays { return nil }
        if let last, last.answer == nil { return nil }

        // Evidence (two separate days, at least one of them since the last T1 card).
        let since = last?.day ?? ""
        let yesterday = PlanView.addDays(today, -1)
        let poor = { (d: String) in (input.feel.answer(on: d)?.rawValue ?? 9) <= 2 }
        let poorMornings = poor(today) && poor(yesterday) && today > since
        let weekAgo = PlanView.addDays(today, -6)
        let harder = input.sessions.filter {
            $0.day >= weekAgo && input.known($0.day) && feltHarder($0, today: today, margin: s.feltHarderMargin)
        }
        let hardSessions = Set(harder.map(\.day)).count >= 2 && harder.contains { $0.day > since }
        let twoTiredWeeks = w >= 2 && input.isTiredWeek(w) && input.isTiredWeek(w - 1)
            && !input.log.contains { $0.trigger == .t1 && $0.key == "tired-weeks|\(w)" }
        guard poorMornings || hardSessions || twoTiredWeeks else { return nil }

        let why = poorMornings ? RuleBookWords.whyPoorMornings : RuleBookWords.whyHardSessions
        if twoTiredWeeks, let forward = easyWeekForward(input, key: "tired-weeks|\(w)", step: 3,
                                                        headline: RuleBookWords.easyWeekLine(wasMonday: nil),
                                                        why: RuleBookWords.whyTwoTiredWeeks) {
            return [forward] + (t1Step2(input, why: RuleBookWords.whyTwoTiredWeeks, key: "tired-weeks|\(w)") ?? [])
        }

        // Which rung: again within 7 days of the last one closing → the next; after that the ladder starts over.
        var step = 1
        if let last, last.answer != nil, daysBetween(last.closedOn, today) <= s.ladderStepDays,
           daysBetween(last.day, today) <= s.ladderResetDays {
            step = min(3, last.step + 1)
        }
        let key = "tired|\(today)"
        switch step {
        case 1: return t1Step1(input, why: why, key: key)
        case 2: return t1Step2(input, why: RuleBookWords.whyStillTired, key: key)
        default:
            guard let next = input.weeks.filter({ $0.number > w && $0.tag == .easy }).min(by: { $0.number < $1.number }),
                  let forward = easyWeekForward(input, key: key, step: 3, headline: RuleBookWords.easyWeekLine(wasMonday: next.monday),
                                                why: RuleBookWords.whyTiredOverWeek) else { return t1Step2(input, why: RuleBookWords.whyStillTired, key: key) }
            return [forward] + (t1Step2(input, why: RuleBookWords.whyTiredOverWeek, key: key) ?? [])
        }
    }

    /* Step 1: an extra rest day (today, else a non-Friday day within 2 days without a key); else today's session easier. */
    static func t1Step1(_ input: RuleBookInput, why: String, key: String) -> [Candidate]? {
        let today = input.today
        let restDay = [today, PlanView.addDays(today, 1), PlanView.addDays(today, 2)].first { d in
            !isFriday(d) && !dayHoldsKeyOrProtected(d, input) && !openSessions(on: d, input).isEmpty
                && openSessions(on: d, input).allSatisfy { touchable($0, input) }
        }
        var out: [Candidate] = []
        if let d = restDay {
            let list = openSessions(on: d, input)
            let headline = list.count == 1 ? RuleBookWords.dropLine(list[0])
                : "\(RuleBookWords.day(d)): " + list.map(RuleBookWords.sport).joined(separator: ", ") + " → rest"
            out.append(Candidate(trigger: .t1, step: 1, key: key, moves: [.extraRestDay(day: d)], headline: headline, why: why))
        }
        let target = (restDay.map { openSessions(on: $0, input) } ?? openSessions(on: today, input)).first { touchable($0, input) }
        if let s = target {
            let shorter = labels(s).long ? max(percent(s.plannedMin, 70), percent(s.plannedMin, input.settings.longFloorPercent)) : percent(s.plannedMin, 70)
            if restDay == nil {
                out.append(Candidate(trigger: .t1, step: 1, key: key, moves: [.makeEasier(session: s.id, instead: nil)],
                                     headline: RuleBookWords.easierLine(s, minutes: nil, easier: true), why: why))
            }
            out.append(Candidate(trigger: .t1, step: 1, key: key,
                                 moves: [.shorten(session: s.id, minutes: shorter), .makeEasier(session: s.id, instead: nil)],
                                 headline: RuleBookWords.easierLine(s, minutes: shorter, easier: true), why: why))
            if let e = nextEasy(after: s, input) {
                out.append(Candidate(trigger: .t1, step: 1, key: key, moves: [.swapWithNextEasy(session: s.id, easy: e.id)],
                                     headline: RuleBookWords.swapLine(s, e), why: why))
            }
        }
        return out.isEmpty ? nil : out
    }

    /* The first later EASY session in the same plan week, not on a Friday (M2's partner). */
    static func nextEasy(after s: RBSession, _ input: RuleBookInput) -> RBSession? {
        let w = input.week(of: s.day)
        return input.sessions.filter {
            $0.day > s.day && input.week(of: $0.day) == w && !isFriday($0.day) && $0.counts && $0.status == .open
                && sessionClass($0) == .easy && !labels($0).key
        }.min { ($0.day, $0.row) < ($1.day, $1.row) }
    }

    /* Step 2: every non-protected session of the next 3 days made easy. */
    static func t1Step2(_ input: RuleBookInput, why: String, key: String) -> [Candidate]? {
        let days = days(from: input.today, count: 3)
        let list = input.sessions.filter { days.contains($0.day) && touchable($0, input) && !alreadyEasy($0) }
        guard !list.isEmpty else { return nil }
        let easy = list.map { Move.makeEasier(session: $0.id, instead: nil) }
        let shorter = list.map { Move.shorten(session: $0.id, minutes: percent($0.plannedMin, 70)) }
        return [Candidate(trigger: .t1, step: 2, key: key, moves: easy,
                          headline: RuleBookWords.easyDaysLine(count: 3, sessions: list), why: why),
                Candidate(trigger: .t1, step: 2, key: key, moves: shorter,
                          headline: "Next 3 days shorter: " + list.map(RuleBookWords.name).joined(separator: ", ") + " at 70 %", why: why)]
    }

    /* M6: the next easy week brought forward to today. */
    static func easyWeekForward(_ input: RuleBookInput, key: String, step: Int, headline: String, why: String) -> Candidate? {
        let w = input.todayWeek
        guard let next = input.weeks.filter({ $0.number > w && $0.tag == .easy }).min(by: { $0.number < $1.number }) else { return nil }
        let line = headline == RuleBookWords.easyWeekLine(wasMonday: nil) ? headline : RuleBookWords.easyWeekLine(wasMonday: next.monday)
        return Candidate(trigger: .t1, step: step, key: key, moves: [.bringEasyWeekForward(from: input.today, easyWeek: next.number)],
                         headline: line, why: why)
    }

    // MARK: T2 · a missed key session in a 2–3 day gap

    static func t2MissedKey(_ input: RuleBookInput) -> [Candidate]? {
        guard input.moment == .morning else { return nil }
        let today = input.today
        var gapDays = 0
        var keys: [RBSession] = []
        var day = PlanView.addDays(today, -1)
        while gapDays <= 3 && day >= input.planStart {
            let planned = input.sessions.filter { $0.day == day && !$0.isRest && !$0.dropped }
            if planned.isEmpty { day = PlanView.addDays(day, -1); if daysBetween(day, today) > 10 { break }; continue }
            // Open for more than 48 h counts as missed; before that the app only asks "Did you do …?".
            let gone = planned.allSatisfy { $0.status == .missed || ($0.status == .open && daysBetween($0.day, today) >= 3) }
            guard gone else { break }
            gapDays += 1
            keys += planned.filter { labels($0).key && !labels($0).test && !labels($0).sim }
            day = PlanView.addDays(day, -1)
        }
        guard (2...3).contains(gapDays), !keys.isEmpty else { return nil }
        let order = Array(dropOrder.reversed())
        guard let k = keys.min(by: { (order.firstIndex(of: $0.slot) ?? 99) < (order.firstIndex(of: $1.slot) ?? 99) }) else { return nil }
        if input.log.contains(where: { $0.trigger == .t2 && $0.key == k.id }) { return nil }
        // A non-key, non-protected session from today on in the same plan week, not on a Friday —
        // OPEN: "the first" read by his drop order (G4: "used whenever a move must pick a session"), then by day.
        let w = input.week(of: k.day)
        let rank = { (s: RBSession) in dropOrder.firstIndex(of: s.slot) ?? 99 }
        guard let e = input.sessions.filter({
            $0.day >= today && input.week(of: $0.day) == w && !isFriday($0.day) && touchable($0, input) && !labels($0).key
        }).min(by: { (rank($0), $0.day, $0.row) < (rank($1), $1.day, $1.row) }) else { return nil }
        let why = RuleBookWords.whyMissedKey(days: gapDays)
        let line = RuleBookWords.keySwapLine(k, to: e.day, replacing: e)
        let base: [Move] = [.moveToDay(session: k.id, day: e.day), .drop(session: e.id)]
        return [Candidate(trigger: .t2, step: 0, key: k.id, moves: base, headline: line, why: why),
                Candidate(trigger: .t2, step: 0, key: k.id, moves: base + [.shorten(session: k.id, minutes: percent(k.plannedMin, 75))],
                          headline: line + ", at three quarters", why: why)]
    }

    // MARK: T3 · back after a break

    /* Days in a row without a done session or a counted extra, ending the day before `end` (Fridays not counted). */
    static func gapBefore(_ end: String, _ input: RuleBookInput) -> Int {
        var count = 0
        var day = PlanView.addDays(end, -1)
        while day >= input.planStart && input.countedMinutes(on: day) == 0 {
            if !isFriday(day) { count += 1 }
            day = PlanView.addDays(day, -1)
            if count > 60 { break }
        }
        return day < input.planStart ? 0 : count
    }

    static func t3BackAfterBreak(_ input: RuleBookInput) -> [Candidate]? {
        guard input.moment == .morning else { return nil }
        if ladderStep(input).step != .none || input.health.illSince.map({ $0 <= input.today && input.health.symptomFreeSince == nil }) == true {
            return nil
        }
        let today = input.today, yesterday = PlanView.addDays(today, -1)

        // Week 2 of the return ladder, seven days after a taken week 1.
        if let w1 = lastRecord(.t3, input, where: { $0.step == 1 && $0.wasTaken }), daysBetween(w1.day, today) == 7,
           !input.log.contains(where: { $0.trigger == .t3 && $0.key == w1.key && $0.step == 2 }) {
            let d = days(from: today, count: 7)
            return [Candidate(trigger: .t3, step: 2, key: w1.key, moves: ladderWeek2(input, days: d, tests: false),
                              headline: "Next 7 days at three quarters, one quality session", why: ladderText(.week2)),
                    Candidate(trigger: .t3, step: 2, key: w1.key, moves: ladderWeek2(input, days: d, rowInstead: true, tests: false),
                              headline: RuleBookWords.rowInstead, why: ladderText(.week2))]
        }

        // The first morning after the break: yesterday something was done again.
        guard input.countedMinutes(on: yesterday) > 0 else { return nil }
        let gap = gapBefore(yesterday, input)
        guard gap >= 4, gap < 21 else { return nil }
        let key = "break|" + PlanView.addDays(yesterday, -gap)
        if input.log.contains(where: { $0.trigger == .t3 && $0.key == key }) { return nil }
        if gap < 7 {
            let d = days(from: today, count: 2)
            let list = input.sessions.filter { d.contains($0.day) && touchable($0, input) && !alreadyEasy($0) }
            guard !list.isEmpty else { return nil }
            let why = RuleBookWords.whyBackShort(days: gap)
            let rows = list.map { Move.makeEasier(session: $0.id, instead: $0.sport == .run ? .row : nil) }
            return [Candidate(trigger: .t3, step: 0, key: key, moves: list.map { .makeEasier(session: $0.id, instead: nil) },
                              headline: RuleBookWords.easyDaysLine(count: 2, sessions: list), why: why),
                    Candidate(trigger: .t3, step: 0, key: key, moves: rows, headline: RuleBookWords.rowInstead, why: why)]
        }
        let d = days(from: today, count: 7)
        return [Candidate(trigger: .t3, step: 1, key: key, moves: ladderWeek1(input, days: d, tests: false),
                          headline: "Next 7 days at half, all easy", why: RuleBookWords.whyBackLong),
                Candidate(trigger: .t3, step: 1, key: key, moves: ladderWeek1(input, days: d, rowInstead: true, tests: false),
                          headline: RuleBookWords.rowInstead, why: RuleBookWords.whyBackLong)]
    }
}
