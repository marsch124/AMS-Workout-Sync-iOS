import XCTest
@testable import WorkoutCore

/*
 * Round 30, lane "tuning": Next week, tuned (pick 2) and Zones that keep up
 * (pick 3). One small test per rule, on the rule book's invented plan
 * (RuleBookFixture: Monday 7 January 2030 onwards) and invented laps.
 */
final class Tuning30Tests: XCTestCase {

    // MARK: Next week, tuned

    /* Week 2 all done; three named sessions answered with an effort. */
    private func doneWeek2(_ f: inout Fixture, rpe: [String: Int]) {
        f.allDone(before: Fixture.day(3, 0))
        for (title, r) in rpe {
            let i = f.index(f.id(2, title))
            f.sessions[i].rpe = r
        }
    }

    private func card(_ f: Fixture, load: Double? = nil) -> NextWeekTune.Card? {
        NextWeekTune.card(f.input(Fixture.day(2, 6), .afterSession), monday: Fixture.day(3, 0), loadRatio: load)
    }

    func testShowsOnSundayOnceSettledOrFromFiveAndAllMonday() {
        let sunday = Fixture.day(2, 6), monday = Fixture.day(3, 0)
        XCTAssertNil(NextWeekTune.anchor(today: sunday, hour: 10, sundaySettled: false))
        XCTAssertEqual(NextWeekTune.anchor(today: sunday, hour: 10, sundaySettled: true), monday)
        XCTAssertEqual(NextWeekTune.anchor(today: sunday, hour: 17, sundaySettled: false), monday)
        XCTAssertEqual(NextWeekTune.anchor(today: monday, hour: 21, sundaySettled: false), monday)
        XCTAssertNil(NextWeekTune.anchor(today: Fixture.day(3, 2), hour: 12, sundaySettled: true))
    }

    func testCutsStayWithinTenToTwentyPercentInFiveMinuteSteps() {
        XCTAssertEqual(NextWeekTune.cut(60, percent: 10), 50)
        XCTAssertEqual(NextWeekTune.cut(90, percent: 20), 75)
        XCTAssertEqual(NextWeekTune.cut(45, percent: 10), 40)
        XCTAssertNil(NextWeekTune.cut(20, percent: 10), "5 of 20 minutes is 25 %")
        XCTAssertEqual(NextWeekTune.grow(100), 110)
        XCTAssertEqual(NextWeekTune.grow(60), 65)
        XCTAssertNil(NextWeekTune.grow(40), "4 minutes is less than a 5-minute step")
    }

    func testThreeHardSessionsMakeTheIntervalEasyAndShortenTwo() {
        var f = Fixture.standard()
        doneWeek2(&f, rpe: ["Trainer tempo": 8, "Run with short": 8, "Long run": 8])
        let c = card(f)
        XCTAssertEqual(c?.kind, .easeMore)
        XCTAssertEqual(c?.lines, ["Wed run \u{2192} easy", "Thu run: 40 \u{2192} 35 min", "Mon swim: 45 \u{2192} 40 min"])
        XCTAssertEqual(c?.why, "Why: three sessions felt hard this week.")
        XCTAssertLessThanOrEqual(c?.choices.count ?? 0, 3)
    }

    func testOneSignShortensTwoByTenPercent() {
        var f = Fixture.standard()
        doneWeek2(&f, rpe: [:])
        f.feel.set(.tired, on: Fixture.day(2, 2))
        f.feel.set(.bad, on: Fixture.day(2, 4))
        let c = card(f)
        XCTAssertEqual(c?.kind, .ease)
        XCTAssertEqual(c?.lines, ["Thu run: 40 \u{2192} 35 min", "Mon swim: 45 \u{2192} 40 min"])
        XCTAssertEqual(c?.why, "Why: you felt tired on two mornings.")
    }

    func testOverreachingLoadIsASignButSleepIsNeverRead() {
        var f = Fixture.standard()
        doneWeek2(&f, rpe: [:])
        XCTAssertEqual(card(f, load: 1.4)?.kind, .ease)
        XCTAssertEqual(card(f, load: 1.4)?.why, "Why: your training load is well above your usual.")
        XCTAssertEqual(card(f, load: 1.1)?.kind, .stays)
    }

    private func goodWeek() -> Fixture {
        var f = Fixture.standard(longRides: [1: 100, 2: 100, 3: 100])
        doneWeek2(&f, rpe: ["Trainer tempo": 5, "Run with short": 5, "Long run": 5])
        for d in [0, 2, 3, 5] { f.feel.set(.good, on: Fixture.day(2, d)) }
        return f
    }

    func testAllDoneModerateAndFineLengthensTheLongSessionsAtMostTenPercent() {
        let f = goodWeek()
        let c = card(f, load: 1.0)
        XCTAssertEqual(c?.kind, .lengthen)
        XCTAssertEqual(c?.lines, ["Sun bike: 100 \u{2192} 110 min", "Sat run: 60 \u{2192} 65 min"])
        XCTAssertEqual(c?.why, "Why: every session done, efforts moderate and your mornings good.")
    }

    func testNoLengtheningAfterAMissedSessionOrHigherEffortOrOverreaching() {
        var missed = goodWeek()
        missed.missed(missed.id(2, "Steady easy run"))
        XCTAssertEqual(card(missed, load: 1.0)?.kind, .stays, "a missed session is not made up, and nothing grows")
        var hard = goodWeek()
        hard.sessions[hard.index(hard.id(2, "Long run"))].rpe = 7
        XCTAssertEqual(card(hard, load: 1.0)?.kind, .stays, "an effort above moderate")
        XCTAssertEqual(card(goodWeek(), load: 1.35)?.kind, .ease, "Overreaching")
    }

    func testThreeMissedEaseBackIn() {
        var f = Fixture.standard()
        f.allDone(before: Fixture.day(2, 0))
        for title in ["Drill swim", "Trainer tempo", "Run with short"] { f.missed(f.id(2, title)) }
        f.done(f.id(2, "Long ride")); f.done(f.id(2, "Long run")); f.done(f.id(2, "Strength A")); f.done(f.id(2, "Strength B"))
        f.done(f.id(2, "Steady easy"))
        let c = card(f)
        XCTAssertEqual(c?.kind, .missed)
        XCTAssertEqual(c?.why, "Why: three sessions were missed or not logged this week; next week eases back in.")
    }

    func testNeverTouchesTestsAndKeepsEveryChangeInItsBand() {
        var f = Fixture.standard()
        f.allDone(before: Fixture.day(5, 0))
        // Week 4 (easy) felt hard three times; week 5 is the test week.
        for title in ["Gentle run", "Short shakeout", "Reduced long run"] { f.sessions[f.index(f.id(4, title))].rpe = 9 }
        let input = f.input(Fixture.day(4, 6), .afterSession)
        let c = NextWeekTune.card(input, monday: Fixture.day(5, 0), loadRatio: nil)
        XCTAssertNotNil(c)
        for choice in c?.choices ?? [] {
            for id in choice.moves.flatMap(\.sessionIDs) {
                XCTAssertFalse(RuleBook.labels(input.session(id)!).test, "a test was touched")
            }
            XCTAssertTrue(NextWeekTune.failures(choice.moves, input: input, monday: Fixture.day(5, 0)).isEmpty)
        }
    }

    func testRaceWeekAndAPauseGiveNoCardAtAll() {
        var f = Fixture.standard()
        doneWeek2(&f, rpe: ["Trainer tempo": 8, "Run with short": 8, "Long run": 8])
        f.settings.raceWeek = 3
        XCTAssertNil(card(f))
        var g = Fixture.standard()
        g.health.stopSignSince = Fixture.day(2, 5)
        XCTAssertNil(card(g))
    }

    func testLimitsRefuseMoreThanTenPercentLongerDoneSessionsAndOtherMoves() {
        let f = goodWeek()
        let input = f.input(Fixture.day(2, 6), .afterSession)
        let monday = Fixture.day(3, 0)
        let ride = f.id(3, "Long ride")
        XCTAssertFalse(NextWeekTune.failures([.shorten(session: ride, minutes: 120)], input: input, monday: monday).isEmpty)
        XCTAssertTrue(NextWeekTune.failures([.shorten(session: ride, minutes: 110)], input: input, monday: monday).isEmpty)
        XCTAssertFalse(NextWeekTune.failures([.drop(session: ride)], input: input, monday: monday).isEmpty)
        XCTAssertFalse(NextWeekTune.failures([.shorten(session: f.id(2, "Long ride"), minutes: 90)], input: input, monday: monday).isEmpty,
                       "a done session of this week")
    }

    func testClaudeOnlyPicksFromTheMenuAndItsWordsAreChecked() {
        var f = Fixture.standard()
        doneWeek2(&f, rpe: ["Trainer tempo": 8, "Run with short": 8, "Long run": 8])
        guard let c = card(f), c.choices.count >= 2 else { return XCTFail("no menu") }
        let p = NextWeekTune.picked(c, by: ClaudeAnswer(pick: 2, why: "Why: a lighter week suits the plan now."))
        XCTAssertEqual(p?.choices.first, c.choices[1])
        XCTAssertEqual(p?.why, "Why: a lighter week suits the plan now.")
        XCTAssertEqual(p?.claudePicked, true)
        XCTAssertNil(NextWeekTune.picked(c, by: ClaudeAnswer(pick: 0, why: "Why: keep it.")), "keep is the card's own button")
        XCTAssertNil(NextWeekTune.picked(c, by: ClaudeAnswer(pick: 9, why: "Why: something else.")))
        XCTAssertNil(NextWeekTune.picked(c, by: ClaudeAnswer(pick: 1, why: "Why: you slept badly.")), "never sleep")
        XCTAssertEqual(TuneClaude(menu: [["other"]], pick: 2, why: "Why: fine.").apply(to: c), c, "another menu: not used")
        let ask = NextWeekTune.claudeRequest(c, input: f.input(Fixture.day(2, 6), .afterSession))
        XCTAssertTrue(ask.user.contains("1 = Wed run"))
        XCTAssertFalse(ask.user.lowercased().contains("sleep"))
    }

    func testTakeItOnlyWhileTheSessionsAreAsTheyWere() {
        var f = Fixture.standard()
        doneWeek2(&f, rpe: ["Trainer tempo": 8, "Run with short": 8, "Long run": 8])
        guard let c = card(f) else { return XCTFail("no card") }
        XCTAssertTrue(NextWeekTune.stillFits(c, input: f.input(Fixture.day(2, 6), .afterSession)))
        f.sessions[f.index(f.id(3, "Steady easy run"))].plannedMin = 50
        XCTAssertFalse(NextWeekTune.stillFits(c, input: f.input(Fixture.day(2, 6), .afterSession)))
    }

    // MARK: Zones that keep up

    private func laps(_ hr: [Double], seconds: Double = 300, power: [Double]? = nil) -> [GarminLap] {
        hr.enumerated().map { i, h in
            GarminLap(number: i + 1, metres: 1000, seconds: seconds, avgHr: h, powerW: power?[i])
        }
    }

    func testBestSteadyTwentyMinutesOfLapsGivesNinetyFivePercent() {
        let s = SessionZones.sample(activityId: 1, day: "2030-02-01", typeKey: "running", seconds: 2400,
                                    laps: laps([140, 168, 170, 172, 170, 150, 145, 140]))
        XCTAssertEqual(s?.pulse ?? 0, 170 * 0.95, accuracy: 0.01)
        let jumpy = SessionZones.sample(activityId: 2, day: "2030-02-01", typeKey: "running", seconds: 1200,
                                        laps: laps([140, 175, 140, 175]))
        XCTAssertNil(jumpy?.pulse, "not steady: 35 beats between laps")
        XCTAssertNil(SessionZones.sample(activityId: 3, day: "2030-02-01", typeKey: "running", seconds: 600,
                                         laps: laps([160, 160, 160, 160])), "laps longer than the session are summaries")
    }

    func testRunPowerCountsOnlyFromAThresholdEffort() {
        let hard = SessionZones.sample(activityId: 1, day: "2030-02-01", typeKey: "running", seconds: 1200,
                                       laps: laps([158, 160, 160, 162], power: [260, 262, 262, 264]))
        XCTAssertEqual(hard?.power ?? 0, 262 * 0.95, accuracy: 0.01)
        let other = SessionZones.Sample(activityId: 2, day: "2030-02-02", sport: "run", power: 250, powerPulse: 120)
        let p = SessionZones.proposal([hard!, hard!, other].enumerated().map { var x = $1; x.activityId = $0; return x },
                                      inUse: .init(lthr: 165), today: "2030-02-10")
        XCTAssertEqual(p?.row(.runPower)?.new, (262 * 0.95).rounded())
        XCTAssertEqual(p?.row(.runPower)?.sessions.count, 2, "the easy run (pulse 120) does not count")
        XCTAssertEqual(p?.row(.runPower)?.figure, "none yet \u{2192} 249")
    }

    func testPulseNeedsTwoSessionsThreeBeatsHigherAndNeverLowers() {
        func s(_ id: Int, _ p: Double, _ sport: String = "run") -> SessionZones.Sample {
            SessionZones.Sample(activityId: id, day: "2030-02-0\(id)", sport: sport, pulse: p)
        }
        let use = SessionZones.InUse(lthr: 160)
        XCTAssertNil(SessionZones.proposal([s(1, 166)], inUse: use, today: "2030-02-10"), "one session is not enough")
        XCTAssertNil(SessionZones.proposal([s(1, 162), s(2, 162.5)], inUse: use, today: "2030-02-10"), "less than 3 beats")
        XCTAssertNil(SessionZones.proposal([s(1, 150), s(2, 151)], inUse: use, today: "2030-02-10"), "lower shows nothing")
        let p = SessionZones.proposal([s(1, 168), s(2, 164.2, "bike"), s(3, 150)], inUse: use, today: "2030-02-10")
        XCTAssertEqual(p?.row(.pulse)?.new, 164, "the second best, so two sessions support it")
        XCTAssertNil(SessionZones.proposal([s(1, 168), s(2, 166)], inUse: use, today: "2030-04-10"), "older than 6 weeks")
    }

    func testSwimPaceFromTheFastestLongPoolLap() {
        let pool = [GarminLap(number: 1, metres: 400, seconds: 412), GarminLap(number: 2, metres: 100, seconds: 90),
                    GarminLap(number: 3, metres: 500, seconds: 540)]
        let s = SessionZones.sample(activityId: 1, day: "2030-02-01", typeKey: "lap_swimming", seconds: 1100, laps: pool)
        XCTAssertEqual(s?.swimPace ?? 0, 103 + 3, accuracy: 0.01)
        XCTAssertNil(SessionZones.sample(activityId: 2, day: "2030-02-01", typeKey: "open_water_swimming", seconds: 1100, laps: pool))
        let a = SessionZones.Sample(activityId: 1, day: "2030-02-01", sport: "swim", swimPace: 106)
        let b = SessionZones.Sample(activityId: 2, day: "2030-02-03", sport: "swim", swimPace: 107)
        XCTAssertEqual(SessionZones.proposal([a, b], inUse: .init(css: 112), today: "2030-02-10")?.row(.swim)?.new, 107)
        XCTAssertNil(SessionZones.proposal([a, b], inUse: .init(css: 108), today: "2030-02-10"), "less than 2 % faster")
    }

    func testKeepMineHoldsUntilSessionsShowClearlyMore() {
        let row = { (p: Double) in SessionZones.Proposal(rows: [SessionZones.Row(measure: .pulse, old: 160, new: p, sessions: [])]) }
        let kept = SessionZones.Kept(row(164), day: "2030-02-10")
        XCTAssertNil(SessionZones.shown(row(165), kept: kept, today: "2030-02-12"))
        XCTAssertNotNil(SessionZones.shown(row(167), kept: kept, today: "2030-02-12"))
        XCTAssertNotNil(SessionZones.shown(row(165), kept: kept, today: "2030-04-12"), "after 6 weeks it may come back")
    }

    func testTheEntryGoesAfterTheLastTestSoThePlansTestsStillFillIn() {
        let tests = [TestResult(name: "Test 1", dates: "06 Jan 2030", lthr: 160, css: 112),
                     TestResult(name: "Test 2", week: "W9")]
        let p = SessionZones.Proposal(rows: [
            SessionZones.Row(measure: .pulse, old: 160, new: 164, sessions: []),
            SessionZones.Row(measure: .runPower, old: nil, new: 250, sessions: [])])
        let e = SessionZones.entry(p, tests: tests, today: "2030-02-10")!
        XCTAssertEqual(e.name, "Your sessions")
        XCTAssertEqual(e.notes, "From your sessions \u{00B7} run power 250 W")
        XCTAssertNil(e.css, "only what the sessions showed")
        let list = SessionZones.inserting(e, into: tests)
        XCTAssertEqual(list.map(\.name), ["Test 1", "Your sessions", "Test 2"])
        XCTAssertEqual(ZoneMaths.current(list).lthr, 164)
        XCTAssertEqual(ZoneMaths.current(list).css, 112)
        XCTAssertEqual(TestEntry.target(existing: list), .waiting(tests[1]))
        XCTAssertEqual(SessionZones.removing(["Your sessions"], from: list), tests)
        XCTAssertEqual(SessionZones.freshName(list, used: ["Your sessions 2"]), "Your sessions 3")
        XCTAssertNil(SessionZones.entry(SessionZones.Proposal(rows: [p.rows[1]]), tests: tests, today: "2030-02-10"))
    }

    func testRunPowerBandsAndTargets() {
        XCTAssertEqual(RunPowerZones.rows(250).map(\.value),
                       ["up to 200 W", "203\u{2013}220 W", "223\u{2013}238 W", "240\u{2013}263 W", "from 265 W"])
        XCTAssertEqual(RunPowerZones.target(intensity: "Z2", threshold: 250), "203\u{2013}220 W")
        XCTAssertEqual(RunPowerZones.target(intensity: "Z1–Z2", threshold: 250), "up to 220 W")
        XCTAssertEqual(RunPowerZones.target(intensity: "Z4–Z5", threshold: 250), "from 240 W")
        XCTAssertNil(RunPowerZones.target(intensity: "RPE 6", threshold: 250))
    }
}
