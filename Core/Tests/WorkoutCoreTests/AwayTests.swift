import XCTest
@testable import WorkoutCore

/* Away mode (pick 17) and the no-gym circuit (pick 20): worked examples on the invented plan. */
final class AwayTests: XCTestCase {

    let d = Fixture.day

    /* Week 2: Mon swim 45 Z1–Z2 · Tue tempo bike (key) · Wed run Z2–Z3 · Thu strength B + easy run 40 Z2 · Sat long run · Sun long ride. */
    func period(_ untilWeekday: Int, has: [String]) -> AwayPeriod {
        AwayPeriod(from: d(2, 0), until: d(2, untilWeekday), has: has)
    }

    func input(_ f: Fixture, today: String, away: AwayPeriod?) -> RuleBookInput {
        var i = f.input(today)
        i.away = away
        return i
    }

    // swim, no pool: the easy run takes the day; the swim moves to Thursday when he is back by then
    func testSwimWithoutPoolSwapsWithTheEasyRun() throws {
        var f = Fixture.standard(); f.allDone(before: d(2, 0))
        let away = period(2, has: ["bike", "gym"])                    // away Mon–Wed, back Thursday
        let card = try XCTUnwrap(RuleBook.suggest(input(f, today: d(2, 0), away: away)))
        XCTAssertEqual(card.trigger, .away)
        XCTAssertEqual(card.moves, [.swapWithNextEasy(session: f.id(2, "Drill swim"), easy: f.id(2, "Steady easy run"))])
        XCTAssertEqual(card.headline, "Mon swim: no pool while away \u{2192} easy run 40 min (swim moves to Thu)")
        XCTAssertEqual(card.why, "Why: you are away until 16 Jan without a pool; an easy run keeps the day aerobic.")
        // other choices: the day after he is back, and rest
        XCTAssertEqual(card.otherChoices.map(\.moves), [[.moveToDay(session: f.id(2, "Drill swim"), day: d(2, 3))],
                                                        [.drop(session: f.id(2, "Drill swim"))]])
        XCTAssertEqual(card.otherChoices.map(\.headline), ["Mon swim: no pool while away \u{2192} Thu, after you are back",
                                                           "Mon swim: no pool while away \u{2192} rest"])
    }

    // still away on the easy run's day: the swim is dropped by the same choice
    func testSwapWithDropWhenTheSwimWouldStillBeAway() throws {
        var f = Fixture.standard(); f.allDone(before: d(2, 0))
        let away = period(4, has: ["bike", "gym"])                    // away Mon–Fri
        let card = try XCTUnwrap(RuleBook.suggest(input(f, today: d(2, 0), away: away)))
        XCTAssertEqual(card.moves.count, 2)
        XCTAssertEqual(card.moves.map(\.code), ["M2", "M1"])
        XCTAssertEqual(card.headline, "Mon swim: no pool while away \u{2192} easy run 40 min instead")
    }

    // open water or a pool is enough: no card
    func testASwimHeCanDoGivesNoCard() {
        var f = Fixture.standard(); f.allDone(before: d(2, 0))
        XCTAssertNil(RuleBook.suggest(input(f, today: d(2, 0), away: period(2, has: ["pool", "bike"]))))
        XCTAssertNil(RuleBook.suggest(input(f, today: d(2, 0), away: period(2, has: ["openwater", "bike"]))))
        XCTAssertEqual(Away.chip(sport: .swim, text: "Drill swim", day: d(2, 0), period: period(2, has: ["bike"])), "No pool while away")
        XCTAssertNil(Away.chip(sport: .swim, text: "Drill swim", day: d(2, 0), period: period(2, has: ["pool"])))
        // an "open water" swim needs open water, a pool does not do
        XCTAssertEqual(Away.chip(sport: .swim, text: "Open water swim", day: d(2, 0), period: period(2, has: ["pool"])), "No open water while away")
    }

    // bike, no bike, in a load week: a card; in an easy week the week stays easy (chip, no card)
    func testBikeWithoutBikeAndTheEasyWeek() throws {
        var f = Fixture.standard()
        // week 2 Tuesday is a key bike session; put it on Wednesday (today), no bike, away Tue–Thu
        let away = AwayPeriod(from: d(2, 1), until: d(2, 3), has: ["pool", "gym"])
        let key = f.id(2, "Trainer tempo")
        f.sessions[f.index(key)].day = d(2, 2)
        f.allDone(before: d(2, 2))
        let card = try XCTUnwrap(RuleBook.suggest(input(f, today: d(2, 2), away: away)))
        XCTAssertEqual(card.trigger, .away)
        // a key session is never dropped: only a swap or a move are on the menu
        XCTAssertTrue(([card.choice] + card.otherChoices).allSatisfy { !$0.moves.contains(.drop(session: key)) })
        // easy week 4: spin on Monday, no bike: the easy week stays easy
        var g = Fixture.standard(); g.allDone(before: d(4, 0))
        let awayEasy = AwayPeriod(from: d(4, 0), until: d(4, 3), has: ["pool", "gym"])
        XCTAssertNil(RuleBook.suggest(input(g, today: d(4, 0), away: awayEasy)))
        XCTAssertEqual(Away.chip(sport: .bike, text: "Spin, light gear", day: d(4, 0), period: awayEasy), "No bike while away")
    }

    // strength, no gym: a chip, never a card (the No-gym version changes nothing)
    func testStrengthWithoutGymGetsNoCard() {
        var f = Fixture.standard(); f.allDone(before: d(2, 3))
        let away = AwayPeriod(from: d(2, 3), until: d(2, 6), has: ["pool", "bike"])
        let card = RuleBook.suggest(input(f, today: d(2, 3), away: away))
        XCTAssertNotEqual(card?.trigger, .away)
        XCTAssertEqual(Away.chip(sport: .strength, text: "Strength B", day: d(2, 3), period: away), "No gym while away")
        XCTAssertNil(Away.chip(sport: .strength, text: "Strength B", day: d(2, 3), period: AwayPeriod(from: d(2, 3), until: d(2, 6), has: ["gym"])))
    }

    // the day after he is back, and a day before he leaves: no card, no chip
    func testNoCardAfterHeIsBackOrBeforeHeLeaves() {
        var f = Fixture.standard(); f.allDone(before: d(2, 0))
        let away = AwayPeriod(from: d(2, 0), until: d(2, 0), has: ["bike", "gym"])       // only Monday
        XCTAssertNotNil(RuleBook.suggest(input(f, today: d(2, 0), away: away)))
        var g = Fixture.standard(); g.allDone(before: d(2, 1))
        XCTAssertNil(RuleBook.suggest(input(g, today: d(2, 1), away: away)))             // Tuesday: back
        XCTAssertNil(Away.chip(sport: .swim, text: "Swim", day: d(2, 1), period: away))
        XCTAssertNil(Away.todayLine(period: away, today: d(2, 1)))
        let later = AwayPeriod(from: d(3, 0), until: d(3, 3), has: [])
        XCTAssertNil(RuleBook.suggest(input(f, today: d(2, 0), away: later)))             // not away yet: nothing today or in 2 days
    }

    // nothing is ever added or made harder or longer, and the book's limits and "Keep my plan" hold
    func testAwayNeverAddsOrMakesHarder() throws {
        var f = Fixture.standard(); f.allDone(before: d(2, 0))
        let i = input(f, today: d(2, 0), away: period(4, has: []))
        let card = try XCTUnwrap(RuleBook.suggest(i))
        for choice in [card.choice] + card.otherChoices {
            XCTAssertEqual(RuleBook.check(choice.moves, for: .away, input: i), [])
            let after = try RuleBook.apply(choice.moves, to: i.sessions, input: i)
            XCTAssertEqual(after.count, i.sessions.count)
            for s in after {
                let b = i.sessions.first { $0.id == s.id }!
                XCTAssertLessThanOrEqual(s.plannedMin, b.plannedMin)
                XCTAssertEqual(s.intensity, b.intensity)
            }
            XCTAssertTrue(choice.moves.allSatisfy { ["M1", "M2", "M5"].contains($0.code) })
        }
        // after "Keep my plan" the same session is not asked about again
        var kept = card.record; kept.answer = .keptPlan; kept.answeredOn = d(2, 0)
        var next = i; next.log = [kept]; next.today = d(2, 1)
        XCTAssertNotEqual(RuleBook.suggest(next)?.record.key, f.id(2, "Drill swim"))
    }

    func testTodayLineAndPeriodEdges() {
        let away = AwayPeriod(from: "2030-01-02", until: "2030-01-09", has: ["bike"])
        XCTAssertEqual(Away.todayLine(period: away, today: "2030-01-05"), "Away until Wed 9 Jan \u{00B7} no pool, no gym, no open water")
        XCTAssertEqual(Away.todayLine(period: AwayPeriod(from: "2030-01-02", until: "2030-01-09", has: ["pool", "bike", "gym", "openwater"]), today: "2030-01-05"), "Away until Wed 9 Jan")
        XCTAssertNil(Away.todayLine(period: away, today: "2030-01-10"))
        XCTAssertNil(Away.todayLine(period: away, today: "2030-01-01"))
        let data = try? JSONDecoder().decode(AwayPeriod.self, from: Data(#"{"until":"2030-01-09","has":["gym"],"extra":1}"#.utf8))
        XCTAssertEqual(data?.has, ["gym"])
        XCTAssertFalse(data?.contains("2030-01-05") ?? true)   // no start date: holds no day
    }

    // the no-gym circuit: three lengths, total within 5 minutes of the plan
    func testNoGymCircuitThreeLengths() {
        for planned in [20, 30, 45] {
            let c = NoGymCircuit.build(plannedMinutes: planned)
            XCTAssertLessThanOrEqual(abs(c.totalMinutes - Double(planned)), 5, "\(planned) min gave \(c.totalMinutes)")
            XCTAssertGreaterThanOrEqual(c.rounds, 2)
            XCTAssertEqual(c.moves.count, planned > 25 ? 8 : 6)
            XCTAssertTrue(c.warmUp.hasPrefix("Warm-up"))
            XCTAssertTrue(c.coolDown.hasPrefix("Cool-down"))
        }
        XCTAssertEqual(NoGymCircuit.build(plannedMinutes: 45).moves.map(\.name).first, "Squats")
        XCTAssertEqual(NoGymCircuit.build(plannedMinutes: 30), NoGymCircuit.build(plannedMinutes: 30))
    }
}
