import XCTest

/*
 * Claude built in: the settings page, with no network and no key ever typed.
 * AMSWS_CLAUDE_PAGE opens the page; AMSWS_FAKE_CLAUDE gives a saved-key state
 * with three invented answers in the log. Found by identifier only.
 * Written and compiled; not run by the helper that wrote it.
 */
final class ClaudeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

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

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /* The page opens with its field, its two buttons and its switch. */
    func testThePageOpens() {
        let app = launch(["AMSWS_CLAUDE_PAGE": "1"])
        XCTAssertTrue(any(app, "claude-save").waitForExistence(timeout: 15), "the Claude page did not open")
        XCTAssertTrue(any(app, "claude-key").exists)
        XCTAssertTrue(any(app, "claude-cancel").exists)
        XCTAssertTrue(any(app, "claude-on").exists)
        XCTAssertTrue(any(app, "claude-month").exists)
    }

    /* The page will not save an empty key, and says why in words. */
    func testAnEmptyKeyIsRefusedInWords() {
        let app = launch(["AMSWS_CLAUDE_PAGE": "1"])
        let save = any(app, "claude-save")
        XCTAssertTrue(save.waitForExistence(timeout: 15), "the Claude page did not open")
        save.tap()
        let problem = any(app, "claude-problem")
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "no red line for an empty key")
        XCTAssertTrue(problem.label.contains("Nothing typed yet"), "it said \(problem.label)")
    }

    /* With the fake switch: a saved key, the month line and three log rows. */
    func testTheLogAndTheMonthShow() {
        let app = launch(["AMSWS_CLAUDE_PAGE": "1", "AMSWS_FAKE_CLAUDE": "1"])
        let month = any(app, "claude-month")
        XCTAssertTrue(month.waitForExistence(timeout: 15), "the month line did not show")
        XCTAssertTrue(month.label.contains("0.12 US dollars of 5.00"), "it said \(month.label)")
        XCTAssertTrue(month.label.contains("6 answers"))
        XCTAssertTrue(any(app, "claude-remove").exists, "a saved key can be removed")
        XCTAssertFalse(any(app, "claude-save").exists, "no key field once a key is saved")
        let rows = app.descendants(matching: .any).matching(identifier: "claude-log-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 3)
    }
}
