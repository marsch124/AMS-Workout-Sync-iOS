import XCTest
@testable import WorkoutCore

/*
 * The arithmetic behind Progress. Every number on that screen is worked out
 * from the session rows each time it opens, so a fault here is a wrong figure
 * he would have no way of noticing — the screen has no second source to
 * disagree with it.
 */
final class ProgressTests: XCTestCase {

    private func row(_ sport: String, _ day: String, planned: Double, actual: Double) -> Stats.LoadRow {
        Stats.LoadRow(sport: sport, dayKey: day, planned: planned, actual: actual)
    }

    func testAWeekAddsUpWhatIsInIt() {
        let rows = [row("run", "2026-09-28", planned: 1800, actual: 1800),
                    row("bike", "2026-09-30", planned: 3600, actual: 2700),
                    row("swim", "2026-10-01", planned: 2400, actual: 0)]
        let load = Stats.load(rows, weekStarts: ["2026-09-28"], endExclusive: "2026-10-05")
        XCTAssertEqual(load.weeks.count, 1)
        XCTAssertEqual(load.weeks[0].planned, 7800)
        XCTAssertEqual(load.weeks[0].actual, 4500)
        XCTAssertEqual(load.weeks[0].sessions, 2, "only the two with time recorded count as done")
        XCTAssertEqual(load.planned, 7800)
        XCTAssertEqual(load.actual, 4500)
    }

    func testEachWeekKeepsItsOwnDays() {
        let rows = [row("run", "2026-09-28", planned: 1800, actual: 1800),   // week one
                    row("run", "2026-10-05", planned: 1800, actual: 900)]    // week two
        let load = Stats.load(rows, weekStarts: ["2026-09-28", "2026-10-05"], endExclusive: "2026-10-12")
        XCTAssertEqual(load.weeks.map(\.start), ["2026-09-28", "2026-10-05"])
        XCTAssertEqual(load.weeks[0].actual, 1800)
        XCTAssertEqual(load.weeks[1].actual, 900)
    }

    func testDaysOutsideTheWindowAreLeftOut() {
        let rows = [row("run", "2026-08-01", planned: 1800, actual: 1800),   // long before
                    row("run", "2026-09-28", planned: 1800, actual: 1800),
                    row("run", "2026-12-24", planned: 9999, actual: 9999)]   // after the end
        let load = Stats.load(rows, weekStarts: ["2026-09-28"], endExclusive: "2026-10-05")
        XCTAssertEqual(load.weeks[0].actual, 1800)
        XCTAssertEqual(load.planned, 1800, "a day beyond the window must not be counted")
    }

    func testASportWithNothingInItIsNotListed() {
        let rows = [row("run", "2026-09-28", planned: 1800, actual: 1800),
                    row("ski", "2026-09-29", planned: 0, actual: 0)]
        let load = Stats.load(rows, weekStarts: ["2026-09-28"], endExclusive: "2026-10-05")
        XCTAssertEqual(load.sports.map(\.sport), ["run"])
    }

    func testAnEmptyPlanSaysNothingRatherThanCrashing() {
        let load = Stats.load([], weekStarts: [], endExclusive: nil)
        XCTAssertTrue(load.weeks.isEmpty)
        XCTAssertTrue(load.sports.isEmpty)
        XCTAssertEqual(load.planned, 0)
        XCTAssertEqual(load.actual, 0)
    }

    func testTheWeeksAreTheOnesAsked() {
        let starts = Stats.recentWeekStarts(12, today: "2026-09-30")
        XCTAssertEqual(starts.count, 12)
        XCTAssertEqual(starts.last, "2026-09-28", "the current week is a Monday and the last of them")
        XCTAssertEqual(Set(starts).count, 12, "no week is listed twice")
        for s in starts { XCTAssertEqual(PlanView.weekStart(s), s, "every one of them is a Monday") }
    }

    // MARK: the phase bar

    private func road(_ phases: [(String, String, String)], start: String, race: String) -> Stats.Road {
        Stats.Road(raceDay: race, raceTitle: "A race", isRace: true, start: start,
                   phases: phases.map { Stats.Phase(name: $0.0, from: $0.1, to: $0.2) },
                   sessions: 0, done: 0, behind: 0, toCome: 0,
                   plannedAll: 0, plannedSoFar: 0, doneSeconds: 0,
                   daysToGo: 0, weeksToGo: 0, through: 0, started: true)
    }

    /* The bar is the road to the race. His own sheet carries a four-week
       postseason after the race: counted in, the blocks came to 109% of the
       road and the bar drew out of its card (build 57). */
    func testAPhaseAfterTheRaceGetsNoBlock() {
        let r = road([("Base", "2026-01-05", "2026-02-01"),
                      ("Taper", "2026-02-02", "2026-02-15"),
                      ("Postseason", "2026-02-16", "2026-03-15")],
                     start: "2026-01-05", race: "2026-02-15")
        let blocks = Stats.phaseBlocks(r)
        XCTAssertEqual(blocks.map(\.index), [0, 1], "the postseason is not road")
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.width }, 1.0, accuracy: 0.02,
                       "the blocks that are road fill the bar exactly once")
    }

    /* A phase that straddles the race is cut at it, not drawn whole. */
    func testAPhaseStraddlingTheRaceIsCutThere() {
        let r = road([("Base", "2026-01-05", "2026-02-01"),
                      ("Race week and after", "2026-02-02", "2026-03-15")],
                     start: "2026-01-05", race: "2026-02-15")
        let blocks = Stats.phaseBlocks(r)
        XCTAssertEqual(blocks.count, 2)
        // 5 Jan to 15 Feb is 42 days of road, both ends counted; 2–15 Feb is 14 of them.
        XCTAssertEqual(blocks[1].width, 14.0 / 42.0, accuracy: 0.001)
        XCTAssertEqual(blocks[0].width + blocks[1].width, 1.0, accuracy: 0.001,
                       "the two together are the whole road")
        XCTAssertLessThanOrEqual(blocks.reduce(0) { $0 + $1.width }, 1.0001,
                                 "nothing may add up to more than the whole bar")
    }

    /* Whatever the sheet says, the bar can never be wider than itself —
       the guarantee the drawing leans on. */
    func testTheBlocksNeverAddUpToMoreThanTheBar() {
        let shapes: [[(String, String, String)]] = [
            [("One", "2026-01-05", "2026-02-15")],                                  // exactly the road
            [("One", "2026-01-05", "2026-01-11"), ("Two", "2026-01-12", "2026-04-01")],
            [("After", "2026-03-01", "2026-04-01")],                                // all of it past the race
            [("One", "2026-01-05", "2026-01-11"), ("Two", "2026-01-05", "2026-02-15")] // overlapping, as a typo would make them
        ]
        for shape in shapes {
            let r = road(shape, start: "2026-01-05", race: "2026-02-15")
            let sum = Stats.phaseBlocks(r).reduce(0) { $0 + $1.width }
            XCTAssertLessThanOrEqual(sum, 1.0001, "phases \(shape.map(\.0)) overflow the bar at \(sum)")
        }
    }

    // MARK: the weeks that are over, and the size of a phase

    /* A week still being lived counts every session not yet done as time
       missed, so a Thursday reading said he was behind on hours he still had
       the weekend to do (his words, 2 October 2026). */
    func testTheWeeklyFiguresStopAtTheWeekJustGone() {
        let starts = Stats.completedWeekStarts(12, today: "2026-10-02")   // a Friday
        XCTAssertEqual(starts.count, 12)
        XCTAssertEqual(PlanView.weekStart("2026-10-02"), "2026-09-28", "this week began on the Monday")
        XCTAssertEqual(starts.last, "2026-09-21", "the last one counted is the week before this one")
        XCTAssertFalse(starts.contains("2026-09-28"), "the week being lived is not in the figures")
        XCTAssertEqual(Set(starts).count, 12, "no week is listed twice")
        for w in starts { XCTAssertEqual(PlanView.weekStart(w), w, "every one of them is a Monday") }
    }

    /* Monday is the awkward day: the week that just began holds nothing yet. */
    func testOnAMondayTheWeekJustBegunIsStillLeftOut() {
        let starts = Stats.completedWeekStarts(3, today: "2026-09-28")   // the Monday itself
        XCTAssertEqual(starts, ["2026-09-07", "2026-09-14", "2026-09-21"])
    }

    /* A real mapping, read from the fixture workbook: the phase counting does
       not depend on it, but building a road does. */
    private func aMapping() throws -> Mapping {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try XCTUnwrap(try Plan.mapping(for: Workbook(data: try Data(contentsOf: url))))
    }

    private func session(_ day: String, phase: String, sport: String = "run",
                         logged: Bool = false, missed: Bool = false) -> Workout {
        Workout(key: day + sport, sheet: "Weekly Schedules", row: 1, rows: [1],
                date: parseDayKey(day)!, dayKey: day, disciplineRaw: sport,
                discipline: Discipline(id: sport, label: sport.capitalized, synonyms: []),
                title: "A session", phase: phase, sections: [],
                planned: Planned(durationRaw: 60, distanceRaw: nil, intensity: "", description: ""),
                results: [:],
                loggedInSheet: logged, missed: missed, logged: logged)
    }

    /* He asked for the size of each phase, and how much of the one he is in is
       behind him. */
    func testAPhaseKnowsHowManySessionsItHoldsAndHowManyAreDone() throws {
        let plan = [session("2026-01-05", phase: "Base 1", logged: true),
                    session("2026-01-06", phase: "Base 1"),
                    session("2026-01-07", phase: "Base 1", sport: "rest"),       // not a session
                    session("2026-01-08", phase: "Base 1", logged: true, missed: true), // not done
                    session("2026-01-12", phase: "Base 2", logged: true),
                    session("2026-01-13", phase: "Base 2")]
        let road = Stats.road(plan, today: "2026-01-09", mapping: try aMapping())
        XCTAssertNotNil(road)
        let base1 = road!.phases.first { $0.name == "Base 1" }
        XCTAssertEqual(base1?.sessions, 3, "the rest day is not a session")
        XCTAssertEqual(base1?.done, 1, "a missed session is not a done one")
        let base2 = road!.phases.first { $0.name == "Base 2" }
        XCTAssertEqual(base2?.sessions, 2)
        XCTAssertEqual(base2?.done, 1)
    }

    /* The phases must add up to the figure printed beside them on the same
       card, or the two readings argue with each other. */
    func testThePhasesAddUpToTheRoadsOwnTotals() throws {
        let plan = [session("2026-01-05", phase: "Base 1", logged: true),
                    session("2026-01-06", phase: "Base 1"),
                    session("2026-01-07", phase: "Base 1", sport: "rest"),
                    session("2026-01-12", phase: "Base 2", logged: true),
                    session("2026-01-13", phase: "Base 2", logged: true, missed: true)]
        let road = Stats.road(plan, today: "2026-01-09", mapping: try aMapping())!
        XCTAssertEqual(road.phases.reduce(0) { $0 + $1.sessions }, road.sessions)
        XCTAssertEqual(road.phases.reduce(0) { $0 + $1.done }, road.done)
    }
}
