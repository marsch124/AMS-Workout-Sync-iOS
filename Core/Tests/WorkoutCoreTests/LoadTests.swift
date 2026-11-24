import XCTest
@testable import WorkoutCore

/*
 * Load and the morning question: one small test a rule, each on numbers that
 * can be worked out in the head.
 */
final class LoadTests: XCTestCase {

    /* Load = minutes x how hard. A 60-minute run at 5 counts 300. */
    func testLoadIsMinutesTimesHowHard() {
        XCTAssertEqual(Load.points(minutes: 60, score: 5), 300)
        XCTAssertEqual(Load.points(minutes: 147, score: 3), 441)
        XCTAssertEqual(Load.points(minutes: 60, score: 0), 0, "no score, no load")
        XCTAssertEqual(Load.points(minutes: 60, score: 11), 0, "11 is not on the scale")
        XCTAssertEqual(Load.points(minutes: 0, score: 5), 0)
    }

    /* His answer first, then the plan's zone, then easy — and it says which. */
    func testTheScoreFallsBackInOrderAndSaysWhich() {
        XCTAssertEqual(Load.score(answered: 6, planned: "Z2"), Load.Score(value: 6, source: .answered))
        XCTAssertEqual(Load.score(answered: 0, planned: "Z2"), Load.Score(value: 3, source: .planned))
        XCTAssertEqual(Load.score(answered: 0, planned: "Z4–Z5"), Load.Score(value: 8, source: .planned))
        XCTAssertEqual(Load.score(answered: 0, planned: "Z1-Z2"), Load.Score(value: 2.5, source: .planned))
        XCTAssertEqual(Load.score(answered: 0, planned: "RPE 6–7"), Load.Score(value: 6.5, source: .planned))
        XCTAssertEqual(Load.score(answered: 0, planned: "—"), Load.Score(value: 3, source: .guessed))
        XCTAssertEqual(Load.score(answered: 0, planned: ""), Load.Score(value: 3, source: .guessed))
    }

    /* A workout from Health counts once: not again when the plan or an extra already holds it. */
    func testAHealthWorkoutAlreadyWrittenDownIsNotCountedTwice() {
        let found = [
            Load.Found(id: "run", dayKey: "2026-11-07", sport: "run", name: "Run", minutes: 46),
            Load.Found(id: "hike", dayKey: "2026-11-07", sport: "walk", name: "Hike", minutes: 147),
            Load.Found(id: "gym", dayKey: "2026-11-08", sport: "strength", name: "Strength", minutes: 40),
            Load.Found(id: "breath", dayKey: "2026-11-08", sport: "mind", name: "Breathing", minutes: 20),
            Load.Found(id: "short", dayKey: "2026-11-08", sport: "walk", name: "Walk", minutes: 6),
            Load.Found(id: "ski", dayKey: "2026-11-09", sport: "other", name: "Workout", minutes: 62)
        ]
        let recorded = [
            Load.Recorded(dayKey: "2026-11-07", sport: "run", minutes: 45),      // the plan's run
            Load.Recorded(dayKey: "2026-11-09", sport: "ski", minutes: 60)       // an extra under another name, same length
        ]
        let left = Load.outside(found, recorded: recorded).map(\.id)
        XCTAssertEqual(left, ["hike", "gym"], "the run and the ski are written down; breathing and six minutes are not load")
        // One recorded run accounts for one workout only: a second run that day is its own.
        let twoRuns = [found[0], Load.Found(id: "run2", dayKey: "2026-11-07", sport: "run", name: "Run", minutes: 30)]
        XCTAssertEqual(Load.outside(twoRuns, recorded: [recorded[0]]).map(\.id), ["run2"])
    }

    /* A week adds up what fell in it, the plan's and the rest apart; a usual week is the four before this one. */
    func testWeeksAddUpAndAUsualWeekIsTheFourBefore() {
        func item(_ day: String, _ minutes: Double, _ score: Double, inPlan: Bool) -> Load.Item {
            Load.Item(dayKey: day, minutes: minutes, score: Load.Score(value: score, source: .answered), inPlan: inPlan)
        }
        let starts = Stats.recentWeekStarts(6, today: "2026-11-25")   // Mondays 19 Oct ... 23 Nov
        XCTAssertEqual(starts.first, "2026-10-19")
        XCTAssertEqual(starts.last, "2026-11-23")
        let items = [
            item("2026-10-20", 60, 5, inPlan: true),     // 300, week of 19 Oct — outside the four
            item("2026-10-27", 100, 4, inPlan: true),    // 400
            item("2026-11-03", 60, 5, inPlan: true),     // 300
            item("2026-11-08", 120, 3, inPlan: false),   // 360, the Sunday of the week of 2 Nov
            item("2026-11-10", 50, 6, inPlan: true),     // 300
            item("2026-11-17", 40, 5, inPlan: true),     // 200
            item("2026-11-24", 30, 4, inPlan: true),     // 120, this week
            item("2026-09-01", 600, 10, inPlan: true)    // long before the first week shown
        ]
        let weeks = Load.weeks(items, starts: starts)
        XCTAssertEqual(weeks.map(\.total), [300, 400, 660, 300, 200, 120])
        XCTAssertEqual(weeks[2].inPlan, 300)
        XCTAssertEqual(weeks[2].outside, 360)
        XCTAssertEqual(Load.usual(weeks, firstDay: "2026-09-10"), (400 + 660 + 300 + 200) / 4)
        // Recording began on 9 November: the weeks before it are not averaged in as zeros.
        XCTAssertEqual(Load.usual(weeks, firstDay: "2026-11-09"), (300 + 200) / 2)
        XCTAssertNil(Load.usual([weeks[5]], firstDay: nil), "no finished week, no usual week")
    }

    /* Asked once a day: one answer a day, a second tap replaces it, and a new day asks again. */
    func testTheMorningQuestionIsAnsweredOnceADay() throws {
        var log = FeelLog()
        XCTAssertTrue(log.asks(on: "2026-11-24"))
        log.set(.tired, on: "2026-11-24")
        XCTAssertFalse(log.asks(on: "2026-11-24"))
        log.set(.good, on: "2026-11-24")
        XCTAssertEqual(log.answer(on: "2026-11-24"), .good)
        XCTAssertEqual(log.days.count, 1, "the second tap replaced the first")
        XCTAssertTrue(log.asks(on: "2026-11-25"), "tomorrow it asks again")
        XCTAssertEqual(log.last(3, endingOn: "2026-11-25"), [nil, .good, nil])
        // It survives being saved and read back.
        let back = try JSONDecoder().decode(FeelLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(back, log)
    }
}
