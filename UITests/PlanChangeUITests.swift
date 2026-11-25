import XCTest

/*
 * Changing the plan itself: the app as the plan's home (AMSWS_HOME=app), the
 * same invented fortnight as the other screen tests, on Wednesday 16 September
 * 2026 whose one session is a 35-minute run. Everything is found by identifier.
 */
final class PlanChangeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launch()
        return app
    }

    private func openRun(_ app: XCUIApplication) {
        let run = app.buttons["today-session-2026-09-16-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 15))
        run.tap()
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 5), "the session did not open")
    }

    /* Change the length, add a session, take one out. */
    func testChangeAddAndTakeOutASession() {
        let app = launch()
        openRun(app)

        let length = app.staticTexts["session-length"]
        XCTAssertTrue(length.waitForExistence(timeout: 5), "the session shows no length")
        XCTAssertTrue(length.label.contains("35"), "unexpected starting length: \(length.label)")

        app.buttons["session-change"].tap()
        let minutes = app.textFields["edit-minutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5), "the change page did not open")
        minutes.tap()
        minutes.clearAndType("40")
        app.buttons["edit-save"].tap()
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session-length"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session-length"].label.contains("40"), "the new length is not shown")

        // Add one from the Sessions tab.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["tab-plan"].tap()
        let add = app.buttons["sessions-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the Sessions tab has no add button")
        add.tap()
        let title = app.textFields["edit-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["edit-save"].tap()
        XCTAssertTrue(app.staticTexts["edit-problem"].waitForExistence(timeout: 3), "an empty session was not refused")
        title.tap()
        title.typeText("Easy spin")
        app.buttons["edit-save"].tap()
        XCTAssertFalse(app.buttons["edit-save"].waitForExistence(timeout: 3), "the page did not close")

        // Take the run out.
        app.buttons["tab-today"].tap()
        openRun(app)
        app.buttons["session-change"].tap()
        let remove = app.buttons["edit-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        app.buttons["Take out"].tap()
        XCTAssertFalse(app.buttons["edit-remove"].waitForExistence(timeout: 3), "the page did not close")
        XCTAssertFalse(app.staticTexts["session-title"].waitForExistence(timeout: 3), "the session's own page stayed open")
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        let current = (value as? String) ?? ""
        if !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
