import XCTest

/*
 * Mobility and strength (2.14): Settings → Mobility and strength, on the same
 * invented plan as the other screen tests. The page must say one honest thing
 * (what changes, already done, or no weeks ahead); when it offers a change,
 * one tap makes it and says so, and the button goes.
 */
final class MobilityStrengthUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testThePageShowsTheWeeksAndChangesThemInOneTap() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-13"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_MOBILITY"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["ms-title"].waitForExistence(timeout: 15), "the page did not open")
        XCTAssertTrue(app.buttons["ms-cancel"].exists)
        let change = app.buttons["ms-change"]
        let found = change.waitForExistence(timeout: 5) || app.staticTexts["ms-already"].exists || app.staticTexts["ms-none"].exists
        XCTAssertTrue(found, "the page says neither what it changes nor why it changes nothing")

        if change.exists {
            XCTAssertTrue(app.descendants(matching: .any)["ms-week"].firstMatch.exists, "no week is shown before the change")
            change.tap()
            XCTAssertTrue(app.staticTexts["ms-done"].waitForExistence(timeout: 5), "no word that the plan was changed")
            XCTAssertFalse(change.exists, "the button stayed after the change")
            XCTAssertEqual(app.buttons["ms-cancel"].label, "Done")
        }
    }
}
