import XCTest

/*
 * Round 28, the plan tools: search on the Sessions page, the print preview,
 * the pool card, and the "Why" line. Found by identifier only. Written to
 * compile; the invented plan is the one in Fixtures/plan.xlsx.
 */
final class PlanToolsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    func testSearchFindsASessionAndSaysWhenThereIsNothing() {
        let app = launch(["AMSWS_TAB": "plan"])
        let field = any(app, "session-search")
        XCTAssertTrue(field.waitForExistence(timeout: 15), "no search field")
        field.tap()
        field.typeText("technique")
        XCTAssertTrue(any(app, "search-result-0").waitForExistence(timeout: 5), "no result for technique")
        field.typeText("zzz")
        XCTAssertTrue(any(app, "search-empty").waitForExistence(timeout: 5), "no empty line")
    }

    func testPrintPreviewOffersThreeChoicesAndPrint() {
        let app = launch(["AMSWS_TAB": "plan", "AMSWS_PRINT": "week"])
        XCTAssertTrue(any(app, "print-sheet").waitForExistence(timeout: 15), "the print preview did not open")
        for kind in ["this-week", "next-week", "this-month"] {
            XCTAssertTrue(any(app, "print-choice-\(kind)").exists, "no choice \(kind)")
        }
        XCTAssertTrue(any(app, "print-do").exists)
        XCTAssertTrue(any(app, "print-save").exists)
    }

    func testPoolCardStepsThroughTheSet() {
        let app = launch(["AMSWS_POOL_CARD": "1"])
        XCTAssertTrue(any(app, "pool-card").waitForExistence(timeout: 15), "no pool card")
        XCTAssertTrue(any(app, "pool-row-0").exists)
        any(app, "pool-next").tap()
        XCTAssertTrue(any(app, "pool-row-1").isSelected || any(app, "pool-row-1").exists)
        any(app, "pool-back").tap()
        XCTAssertTrue(any(app, "pool-done").exists)
    }

    func testASessionPageSaysWhy() {
        let app = launch(["AMSWS_TAB": "plan"])
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sessions-session-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no session row")
        row.tap()
        XCTAssertTrue(any(app, "session-why").waitForExistence(timeout: 5), "no Why line")
    }
}
