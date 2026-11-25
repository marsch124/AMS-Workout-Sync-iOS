import XCTest

/*
 * Today's weather and daylight line, the week so far, and the way back after
 * illness, with invented data (AMSWS_FAKE_WEATHER, AMSWS_LADDER: no network,
 * no permission). Found by identifier only.
 */
final class TodayRound28UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testTodayShowsWeatherDaylightWeekSoFarAndTheWayBack() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_WEATHER"] = "1"
        app.launchEnvironment["AMSWS_LADDER"] = "1"
        app.launch()

        XCTAssertTrue(any(app, "week-so-far").waitForExistence(timeout: 15), "no week so far strip")
        XCTAssertTrue(any(app, "today-weather").waitForExistence(timeout: 5), "no weather line")
        XCTAssertTrue(any(app, "today-daylight").exists, "no daylight line")
        XCTAssertTrue(any(app, "return-ladder").exists, "no staircase")
        XCTAssertTrue(any(app, "return-step-2").exists, "no second stair")
    }

    func testTheWeatherSwitchIsInSettings() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "settings"
        app.launch()
        let toggle = any(app, "settings-weather-switch")
        for _ in 0..<8 where !toggle.exists { app.swipeUp() }
        XCTAssertTrue(toggle.exists, "no weather switch in Settings")
    }
}
