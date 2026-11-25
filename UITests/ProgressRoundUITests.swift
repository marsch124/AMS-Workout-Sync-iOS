import XCTest

/*
 * Round 28, Progress: the five new cards, each opened by its picture switch on
 * the invented plan (UITests/Fixtures/plan.xlsx), found by identifier.
 */
final class ProgressRoundUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ switchName: String) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-10-02"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment[switchName] = "1"
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testMonthInReviewAndItsReportPage() {
        let app = launch("AMSWS_MONTH_REVIEW")
        XCTAssertTrue(element(app, "month-review").waitForExistence(timeout: 15), "no month in review")
        XCTAssertTrue(element(app, "month-followed").exists)
        let report = app.buttons["report-pdf"]
        XCTAssertTrue(report.exists, "no Report as PDF button")
        report.tap()
        XCTAssertTrue(app.buttons["report-make"].waitForExistence(timeout: 5), "the page does not say what is in the PDF")
        app.buttons["report-cancel"].tap()
        XCTAssertFalse(app.buttons["report-make"].waitForExistence(timeout: 2))
    }

    func testReportPageAlone() {
        let app = launch("AMSWS_REPORT")
        XCTAssertTrue(app.buttons["report-make"].waitForExistence(timeout: 15))
    }

    func testBestsCard() {
        let app = launch("AMSWS_BESTS")
        XCTAssertTrue(element(app, "bests-card").waitForExistence(timeout: 15), "no bests card")
    }

    func testTestsCard() {
        let app = launch("AMSWS_TESTS_CARD")
        XCTAssertTrue(element(app, "tests-card").waitForExistence(timeout: 15), "no tests card")
    }

    func testSteadyWeeks() {
        let app = launch("AMSWS_STEADY")
        XCTAssertTrue(element(app, "steady-weeks").waitForExistence(timeout: 15), "no steady weeks")
        XCTAssertTrue(element(app, "steady-square-12").exists, "twelve squares expected")
    }
}
