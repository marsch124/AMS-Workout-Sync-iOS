import XCTest

/*
 * 2.17: an invented Garmin strength activity of today (AMSWS_FAKE_GARMIN=1: 40 minutes) ticks the
 * day's strength session by itself; Progress counts the month's strength. The invented fortnight's
 * strength session is Sunday 13 September 2026.
 */
final class GarminTick217UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-13"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        if let tab {
            app.launchEnvironment["AMSWS_TAB"] = tab
            app.launchEnvironment["AMSWS_SCROLL"] = "load"
        }
        app.launch()
        return app
    }

    func testAGarminStrengthActivityTicksTodaysStrength() {
        let app = launch()
        let line = app.staticTexts["neighbour-done"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 20), "no line on today's strength card")
        XCTAssertEqual(line.label, "Ticked from Garmin")
        XCTAssertFalse(app.buttons["neighbour-log"].exists)
    }

    func testProgressCountsTheMonthsStrength() {
        let app = launch(tab: "progress")
        let line = app.staticTexts["strength-month"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 20), "no Strength line in the Load card")
        XCTAssertTrue(line.label.hasPrefix("Strength: ") && line.label.hasSuffix(" this month"), line.label)
    }
}
