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
}
