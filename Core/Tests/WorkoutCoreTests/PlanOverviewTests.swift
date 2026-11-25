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
}
