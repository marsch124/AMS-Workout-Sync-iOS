import XCTest

/*
 * The Body page with invented numbers (AMSWS_FAKE_GARMIN: no network, no
 * key). Found by identifier only.
 */
final class BodyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /* The tab opens the page: the head card, the four tiles, and a tile's seven days with Done. */
    func testTheBodyTabShowsTheCardTheTilesAndSevenDays() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launch()

        let tab = any(app, "tab-body")
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no Body tab")
        tab.tap()
        XCTAssertTrue(any(app, "body-page").waitForExistence(timeout: 5), "the Body page did not open")
        let hero = any(app, "body-hero")
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "no head card")
        XCTAssertTrue(hero.label.contains("Body Battery 40 now"), "the card said \(hero.label)")
        XCTAssertTrue(hero.label.contains("Run −17"), "the workout is not on the card: \(hero.label)")
        for name in ["sleep", "hrv", "resting", "stress"] {
            XCTAssertTrue(any(app, "body-tile-" + name).exists, "no tile for \(name)")
        }

        any(app, "body-tile-hrv").tap()
        XCTAssertTrue(any(app, "body-peek-row-0").waitForExistence(timeout: 5), "the seven days did not open")
        XCTAssertTrue(any(app, "body-peek-row-0").label.contains("64 ms"), "the newest day should be 64 ms")
        XCTAssertTrue(any(app, "body-peek-row-6").exists, "seven rows were expected")
        app.buttons["body-peek-done"].tap()
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "body-peek-row-0").exists, "Done did not close the seven days")
    }

    /* 2.7: yesterday's line is named on the card, a workout on the curve opens its session, and one the plan does not hold opens its own facts. */
    func testAWorkoutOnTheCurveOpensItsSessionOrItsFacts() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "body"
        app.launch()

        XCTAssertTrue(any(app, "body-hero").waitForExistence(timeout: 15), "no head card")
        XCTAssertTrue(any(app, "body-yesterday").exists, "yesterday's line is not named on the card")
        XCTAssertTrue(any(app, "body-foot").label.contains("Tap a workout"), "the page does not say a workout can be tapped")

        // The morning run: the plan has a run that day, so its page opens on the Body page, with a way back.
        let run = any(app, "body-workout-0")
        XCTAssertTrue(run.exists, "the run on the curve cannot be tapped")
        XCTAssertGreaterThanOrEqual(run.frame.width, 43.5, "the tap area is narrower than a finger")
        XCTAssertGreaterThanOrEqual(run.frame.height, 43.5, "the tap area is lower than a finger")
        run.tap()
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 5), "the run's session did not open")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(any(app, "body-hero").waitForExistence(timeout: 5), "the way back did not lead to Body")

        // Strength at noon: nothing like it in the plan that day, so its own facts, and Done.
        any(app, "body-workout-1").tap()
        XCTAssertTrue(any(app, "body-workout-plate").waitForExistence(timeout: 5), "the workout's facts did not open")
        XCTAssertTrue(any(app, "body-workout-row-0").label.contains("Started"), "the plate does not say when it started")
        app.buttons["body-workout-done"].tap()
        XCTAssertTrue(any(app, "body-hero").waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "body-workout-plate").exists, "Done did not close the plate")
    }
}
