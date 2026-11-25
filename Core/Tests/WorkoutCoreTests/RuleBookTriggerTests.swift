import XCTest
@testable import WorkoutCore

/* One test per trigger, the section 5 ladder, the five switches, and what must stay silent. */
final class RuleBookTriggerTests: XCTestCase {

    let d = Fixture.day

    // MARK: T1

    func testT1TwoPoorMorningsGiveAnExtraRestDay() {
        var f = Fixture.standard()
        f.allDone(before: d(2, 2))
        f.feel.set(.tired, on: d(2, 1)); f.feel.set(.bad, on: d(2, 2))
        let card = f.suggest(d(2, 2))
        XCTAssertEqual(card?.trigger, .t1)
        XCTAssertEqual(card?.moves, [.extraRestDay(day: d(2, 2))])
        XCTAssertEqual(card?.headline, "Wed run: 55 min → rest")
        XCTAssertEqual(card?.why, "Why: you felt poor two mornings running.")
        XCTAssertEqual(card?.otherChoices.first?.headline, "Wed run: 55 → 40 min, easy")
        XCTAssertEqual(card?.footer, "Training suggestion — not medical advice.")
    }

    func testT1OneBadMorningIsSilent() {
        var f = Fixture.standard()
        f.feel.set(.bad, on: d(2, 2))
        XCTAssertNil(f.suggest(d(2, 2)))
        f.feel.set(.ok, on: d(2, 1))
        XCTAssertNil(f.suggest(d(2, 2)))
    }

    func testT1TwoHardSessionsThenTheLadderClimbs() {
        var f = Fixture.standard()
        f.allDone(before: d(2, 0))
        f.done(f.id(2, "Drill swim"), rpe: 7)        // expected 3
        f.done(f.id(2, "Trainer tempo"), rpe: 8)         // expected 5
        let first = f.suggest(d(2, 2))
        XCTAssertEqual(first?.trigger, .t1)
        XCTAssertEqual(first?.step, 1)
        XCTAssertEqual(first?.why, "Why: two sessions this week felt much harder than planned.")
        // He keeps his plan; four days of quiet, then new evidence within 7 days of closing → step 2.
        var record = first!.record; record.answer = .keptPlan; record.answeredOn = d(2, 2)
        f.log = [record]
        XCTAssertNil(f.suggest(d(2, 3)))
        f.done(f.id(2, "Run with short"), rpe: 8)
        XCTAssertNil(f.suggest(d(2, 5)))                 // still inside the 4-day cool-down
        f.feel.set(.tired, on: d(2, 6)); f.feel.set(.tired, on: d(3, 0))
        let second = f.suggest(d(3, 0))
        XCTAssertEqual(second?.step, 2)
        XCTAssertEqual(second?.why, "Why: still tired after the rest day.")
        XCTAssertTrue(second?.headline.hasPrefix("Next 3 days easy:") ?? false)
        var r2 = second!.record; r2.answer = .took(0); r2.answeredOn = d(3, 0)
        f.log.append(r2)
        f.feel.set(.bad, on: d(3, 3)); f.feel.set(.bad, on: d(3, 4))
        let third = f.suggest(d(3, 4))
        XCTAssertEqual(third?.step, 3)
        XCTAssertEqual(third?.moves, [.bringEasyWeekForward(from: d(3, 4), easyWeek: 4)])
    }

    func testT1TwoTiredWeeksBringTheEasyWeekForward() {
        var f = Fixture.standard()
        f.allDone(before: d(10, 2))
        f.feel.set(.tired, on: d(9, 1)); f.feel.set(.ok, on: d(9, 2)); f.feel.set(.tired, on: d(9, 3))
        f.feel.set(.tired, on: d(10, 0)); f.feel.set(.ok, on: d(10, 1)); f.feel.set(.bad, on: d(10, 2))
        let card = f.suggest(d(10, 2))
        XCTAssertEqual(card?.moves, [.bringEasyWeekForward(from: d(10, 2), easyWeek: 12)])
        XCTAssertEqual(card?.why, "Why: two tired weeks in a row — your guide says: easy week now.")
    }

    func testT1IsOffInAnEasyWeek() {
        var f = Fixture.standard()
        f.feel.set(.bad, on: d(4, 1)); f.feel.set(.bad, on: d(4, 2))
        XCTAssertNil(f.suggest(d(4, 2)))
        XCTAssertTrue(f.input(d(4, 2)).isTiredWeek(4))   // the days still count toward a tired week
    }

    // MARK: T2

    func testT2MissedKeyInATwoDayGapTakesTheEasyRunsDay() {
        var f = Fixture.standard()
        f.allDone(before: d(2, 0))
        f.missed(f.id(2, "Drill swim")); f.missed(f.id(2, "Strength A")); f.missed(f.id(2, "Trainer tempo"))
        let card = f.suggest(d(2, 2))
        XCTAssertEqual(card?.trigger, .t2)
        XCTAssertEqual(card?.moves, [.moveToDay(session: f.id(2, "Trainer tempo"), day: d(2, 3)), .drop(session: f.id(2, "Steady easy run"))])
        XCTAssertEqual(card?.headline, "Tue bike → Thu (instead of the easy run)")
        XCTAssertEqual(card?.why, "Why: you missed 2 days; your guide keeps the key session and drops an easy one.")
        XCTAssertEqual(card?.otherChoices.count, 1)
    }

    func testT2NeedsTwoDays() {
        var f = Fixture.standard()
        f.allDone(before: d(2, 1))
        f.missed(f.id(2, "Trainer tempo"))
        XCTAssertNil(f.suggest(d(2, 2)))
    }

    // MARK: T3

    func testT3FiveDaysOffEasesTwoDays() {
        var f = Fixture.standard()
        f.allDone(before: d(2, 0))
        f.done(f.id(2, "Long ride"))                         // back on Sunday after Mon–Sat off
        let card = f.suggest(d(3, 0))
        XCTAssertEqual(card?.trigger, .t3)
        XCTAssertEqual(card?.why, "Why: welcome back after 5 days off; ease in for two days.")
        XCTAssertEqual(card?.headline, "Next 2 days easy: Mon strength, Tue bike → easy")
    }

    func testT3TenDaysOffGivesTheReturnLadder() {
        var f = Fixture.standard()
        f.allDone(before: d(2, 0))
        f.done(f.id(3, "Long run"))                          // back on Saturday of week 3
        let card = f.suggest(d(3, 6))
        XCTAssertEqual(card?.trigger, .t3)
        XCTAssertEqual(card?.step, 1)
        XCTAssertEqual(card?.headline, "Next 7 days at half, all easy")
        XCTAssertTrue(card!.moves.contains(.shorten(session: f.id(4, "Spin, light"), minutes: 25)))
    }

    // MARK: T4

    func testT4LongRideTooFarAhead() {
        var f = Fixture.standard(longRides: [7: 120])
        f.allDone(before: d(7, 5))
        f.done(f.id(5, "Long ride"), 75); f.done(f.id(6, "Long ride"), 85); f.done(f.id(4, "Reduced long ride"), 30)
        let card = f.suggest(d(7, 5))
        XCTAssertEqual(card?.trigger, .t4)
        XCTAssertEqual(card?.moves, [.shorten(session: f.id(7, "Long ride"), minutes: 95)])
        XCTAssertEqual(card?.headline, "Sun bike: 120 → 95 min")
        XCTAssertEqual(card?.why, "Why: your longest ride in the last 3 weeks was 85 min; long rides grow a step at a time.")
        // Q4 off: the plan's numbers stand.
        f.settings.longSessionsGrowSlowly = false
        XCTAssertNil(f.suggest(d(7, 5)))
    }

    // MARK: T5

    func testT5BigWeekWithHikes() {
        var f = Fixture.standard()
        f.allDone(before: d(10, 0))
        for wd in [1, 3, 5] { f.extras.append(RBExtra(day: d(10, wd), activity: "hike", minutes: 150, countsAsTraining: false)) }
        f.allDone(before: d(11, 0))
        let card = f.suggest(d(11, 0))
        XCTAssertEqual(card?.trigger, .t5)
        XCTAssertEqual(card?.moves.first, .shorten(session: f.id(11, "Steady easy run"), minutes: 30))
        XCTAssertEqual(card?.why, "Why: last week, with the hikes, you trained about twice your planned time.")
        XCTAssertEqual(card?.otherChoices.first?.moves.first, .shorten(session: f.id(11, "Strength B"), minutes: 20))
    }

    // MARK: T6

    func testT6SundayEveningPlanReview() {
        var f = Fixture.standard()
        f.allDone(before: d(6, 0))
        f.done(f.id(6, "Long ride"))                                // one session in a whole week: under 40 %
        XCTAssertNil(f.suggest(d(6, 6), .morning))
        let card = f.suggest(d(6, 6), .evening)
        XCTAssertEqual(card?.trigger, .t6)
        XCTAssertEqual(card?.headline, "Plan review: you are about a week behind")
        XCTAssertEqual(card?.review?.guideOption, "1–2")
        XCTAssertEqual(card?.moves, [])
    }

    // MARK: section 5

    func testStopSignPausesEveryCardUntilADoctorHasSeenHim() {
        var f = Fixture.standard()
        f.feel.set(.bad, on: d(2, 1)); f.feel.set(.bad, on: d(2, 2))
        f.health.stopSignSince = d(2, 1)
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(2, 2))).step, .paused)
        XCTAssertNil(f.suggest(d(2, 2)))
        f.health.doctorSeenOn = d(2, 2)
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(2, 2))).step, .none)
        XCTAssertEqual(RuleBookWords.stopSignText.first, "Stop training now.")
    }

    func testIllnessLadderSteps() {
        var f = Fixture.standard()
        f.health = RBHealthTaps(illSince: d(2, 0), illness: .belowNeck)
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(2, 3))).step, .rest)
        f.health.symptomFreeSince = d(3, 0)
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(3, 2))).step, .rest)       // 48 h after
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(3, 3))).step, .easyDays)   // + 2 easy days
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(3, 5))).step, .week1)      // 12 days off
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(4, 5))).step, .week2)
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(5, 5))).step, .back)
        f.health.stillNotRight = [d(3, 6)]
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(4, 6))).step, .week1)      // three more days
        let card = f.suggest(d(3, 3))
        XCTAssertEqual(card?.trigger, .section5)
        XCTAssertEqual(card?.why, "Two extra easy days, as your guide says after fever or chest symptoms.")
        f.health = RBHealthTaps(illSince: d(2, 0), illness: .aboveNeck)
        XCTAssertEqual(RuleBook.ladderStep(f.input(d(2, 1))).step, .cold)
    }

    // MARK: the five switches

    func testQ1OffSuggestsTheRunQualityOnThursday() {
        var f = Fixture()
        f.addWeek(1, .load, Fixture.load(hardBike: true, hardRun: true))
        XCTAssertNil(f.suggest(d(1, 0)))
        f.settings.keepBackToBackQuality = false
        let card = f.suggest(d(1, 0))
        XCTAssertEqual(card?.trigger, .backToBack)
        XCTAssertEqual(card?.moves, [.moveToDay(session: f.id(1, "Run with short"), day: d(1, 3))])
    }

    func testQ2SomethingHurtsMakesTheThursdayRunARow() {
        var f = Fixture.standard()
        f.hurtDays = [d(2, 1)]
        let card = f.suggest(d(2, 2))
        XCTAssertEqual(card?.trigger, .hurts)
        XCTAssertEqual(card?.moves, [.makeEasier(session: f.id(2, "Steady easy run"), instead: .row)])
        f.settings.somethingHurtsTap = false
        XCTAssertNil(f.suggest(d(2, 2)))
    }

    func testQ3LaterEasyWeekStaysEasyOrBecomesNormal() throws {
        var f = Fixture.standard()
        let move = Move.bringEasyWeekForward(from: d(2, 0), easyWeek: 4)
        let kept = try RuleBook.apply([move], to: f.input(d(2, 0)).sessions, input: f.input(d(2, 0)))
        XCTAssertEqual(kept.filter { $0.day >= d(4, 0) && $0.day <= d(4, 6) && $0.counts }.reduce(0) { $0 + $1.plannedMin }, 290)
        XCTAssertTrue(RuleBook.check(move, for: .t1, input: f.input(d(2, 0))).isEmpty)
        f.settings.laterEasyWeekStaysEasy = false
        let shifted = try RuleBook.apply([move], to: f.input(d(2, 0)).sessions, input: f.input(d(2, 0)))
        XCTAssertGreaterThan(shifted.filter { $0.day >= d(4, 0) && $0.day <= d(4, 6) && $0.counts }.reduce(0) { $0 + $1.plannedMin }, 290)
    }

    func testQ5RestingPulseCountsOnlyWhenHeSaysSo() {
        var f = Fixture.standard()
        f.feel.set(.ok, on: d(2, 1)); f.feel.set(.ok, on: d(2, 2))
        var input = f.input(d(2, 2))
        input.highPulseDays = [d(2, 1), d(2, 2)]
        XCTAssertFalse(input.isBadSignalDay(d(2, 2)))
        input.settings.restingPulseShownOnly = false
        XCTAssertTrue(input.isBadSignalDay(d(2, 2)))
    }

    // MARK: not triggers, on purpose

    func testNotTriggersStaySilent() {
        var f = Fixture.standard()
        f.allDone(before: d(3, 0))
        // Doing more than planned: every session of week 2 half as long again.
        for s in f.sessions where s.originalWeek == 2 && !s.isRest { f.done(s.id, s.plannedMin * 3 / 2) }
        // A single HRV-low day while HRV is dormant, one bad morning, one hard session.
        var input = f.input(d(3, 1))
        input.hrvLowDays = [d(3, 0), d(3, 1)]; input.hrvNights = 30   // not yet 42 nights: dormant
        input.feel.set(.ok, on: d(3, 0)); input.feel.set(.bad, on: d(3, 1))
        input.sessions[input.sessions.firstIndex { $0.id == f.id(3, "Drill swim") }!].status = .done
        input.sessions[input.sessions.firstIndex { $0.id == f.id(3, "Drill swim") }!].rpe = 8
        XCTAssertNil(RuleBook.suggest(input))
        XCTAssertFalse(input.hrvActive)
        // A missed single day.
        var g = Fixture.standard()
        g.allDone(before: d(3, 2))
        g.missed(g.id(3, "Trainer tempo"))
        XCTAssertNil(g.suggest(d(3, 2)))
    }

    func testEveryCardInAQuietBlockIsCalm() {
        var f = Fixture.standard()
        f.allDone(before: d(12, 0))
        XCTAssertEqual(f.cards(from: d(1, 0), to: d(11, 6)).count, 0)
    }
}
