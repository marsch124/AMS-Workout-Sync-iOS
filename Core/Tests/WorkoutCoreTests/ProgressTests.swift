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
}
