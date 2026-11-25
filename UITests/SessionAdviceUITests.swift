import XCTest

/*
 * The two calm lines on a session's page. The invented fortnight has one
 * strength session (Sunday 13 September 2026, 30 minutes): it gets the protein
 * line and, being short, no fuel line. The fixture holds no session over 90
 * minutes and no interval session, so the fuel line and the Garmin card are
 * covered by the Core tests only.
 */
final class SessionAdviceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStrengthSessionShowsProteinLineAndNoFuelLine() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-13"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launch()

        let strength = app.buttons["today-session-2026-09-13-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 15))
        strength.tap()
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 5), "the session did not open")
        XCTAssertTrue(app.staticTexts["session-protein"].waitForExistence(timeout: 5), "no protein line on a strength session")
        XCTAssertFalse(app.staticTexts["session-fuel"].exists, "a 30-minute session has no fuel line")
        XCTAssertFalse(app.buttons["garmin-card"].exists, "a strength session has no Garmin card")
    }
}
