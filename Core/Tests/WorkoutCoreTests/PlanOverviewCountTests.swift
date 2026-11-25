import XCTest
@testable import WorkoutCore

final class PlanOverviewCountTests: XCTestCase {
    func testAllCountLeavesRestDaysOut() {
        XCTAssertEqual(PlanOverview.countedInAll(disciplineIds: ["run", "rest", "swim", "rest"], extras: 2), 4)
    }
}
