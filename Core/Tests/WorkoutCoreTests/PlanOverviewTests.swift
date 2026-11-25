import XCTest
@testable import WorkoutCore

/* The counting behind the Plan page: a month's calendar rows, the months of a season, the weeks to the race. */
final class PlanOverviewTests: XCTestCase {

    func testNovember2026HasSixRowsFromMonday26October() {
        let rows = PlanOverview.grid("2026-11")
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.first?.first, "2026-10-26")
        XCTAssertEqual(rows.first?.last, "2026-11-01")
        XCTAssertEqual(rows.last?.first, "2026-11-30")
        XCTAssertTrue(rows.allSatisfy { $0.count == 7 })
    }

    func testMonthsAcrossTheNewYear() {
        XCTAssertEqual(PlanOverview.months(from: "2026-11-25", to: "2027-02-03"),
                       ["2026-11", "2026-12", "2027-01", "2027-02"])
        XCTAssertEqual(PlanOverview.adding(-1, to: "2027-01"), "2026-12")
        XCTAssertEqual(PlanOverview.lastDay("2028-02"), "2028-02-29")
    }

    func testWeeksToTheRaceCountAPartWeekAsOne() {
        XCTAssertEqual(PlanOverview.weeksTo("2026-12-02", today: "2026-11-25"), 1)
        XCTAssertEqual(PlanOverview.weeksTo("2026-12-03", today: "2026-11-25"), 2)
        XCTAssertNil(PlanOverview.weeksTo("2026-11-24", today: "2026-11-25"))
    }

    /* A session recorded on a day still to come is "done ahead": in the hours, not in "Plan followed". */
    func testASessionDoneAheadIsNamedNotCountedAsFollowed() {
        let plan = [session("2026-11-23", logged: true), session("2026-11-24", logged: true),
                    session("2026-11-25"), session("2026-11-26", logged: true),
                    session("2026-11-27", sport: "rest", logged: true)]
        let f = PlanOverview.followed(plan, from: "2026-11-23", to: "2026-11-29", today: "2026-11-25")
        XCTAssertEqual(f.done, 2)
        XCTAssertEqual(f.due, 2)
        XCTAssertEqual(PlanOverview.doneAhead(plan, from: "2026-11-23", to: "2026-11-29", today: "2026-11-25"), 1)
    }

    private func session(_ day: String, sport: String = "run", logged: Bool = false) -> Workout {
        Workout(key: day + sport, sheet: "Weekly Schedules", row: 1, rows: [1],
                date: parseDayKey(day)!, dayKey: day, disciplineRaw: sport,
                discipline: Discipline(id: sport, label: sport.capitalized, synonyms: []),
                title: "A session", phase: "", sections: [],
                planned: Planned(durationRaw: 60, distanceRaw: nil, intensity: "", description: ""),
                results: [:], loggedInSheet: logged, missed: false, logged: logged)
    }
}
