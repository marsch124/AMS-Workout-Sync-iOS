import XCTest

/*
 * Round 28: the Race page and Shoes and bikes, with invented sample data
 * (AMSWS_RACE_PAGE / AMSWS_GEAR_PAGE). Found by identifier only.
 */
final class RaceGearUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ switchName: String) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment[switchName] = "1"
        app.launch()
        return app
    }

    func testTheRacePageShowsTheCountdownTheLegsTheFuelAndTheKit() {
        let app = launch("AMSWS_RACE_PAGE")
        XCTAssertTrue(any(app, "race-page").waitForExistence(timeout: 15), "the race page did not open")
        XCTAssertTrue(any(app, "race-countdown").exists)
        for leg in ["swim", "t1", "bike", "t2", "run"] { XCTAssertTrue(any(app, "race-leg-" + leg).exists, "no tile for \(leg)") }
        XCTAssertTrue(any(app, "race-finish").label.contains("Planned finish"), "finish said \(any(app, "race-finish").label)")
        XCTAssertTrue(any(app, "race-fuel-row-0").exists)
        XCTAssertTrue(any(app, "race-fuel-add").exists)

        // Ticking a kit item changes the count.
        let count = any(app, "race-checklist-count")
        app.swipeUp(); app.swipeUp()
        let before = count.label
        any(app, "race-check-2").tap()
        XCTAssertNotEqual(count.label, before, "the tick did not change the count")

        // Untick all asks first.
        any(app, "race-untick-all").tap()
        // (The page's own button is also labelled "Untick all", so the question is found by its title.)
        let afterTick = count.label
        let question = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'packed items?'")).firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5), "no question")
        // The question is a small sheet with no Cancel button on this iOS: a tap outside keeps the ticks.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(question.exists, "the question did not close")
        XCTAssertEqual(count.label, afterTick, "keeping them should leave the ticks")

        // The times page has Cancel and Save.
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        any(app, "race-edit-pacing").tap()
        XCTAssertTrue(any(app, "race-pacing-swim").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "race-pacing-save").exists)
        any(app, "race-pacing-cancel").tap()
        XCTAssertTrue(any(app, "race-page").waitForExistence(timeout: 5))
    }

    func testTheGearPageShowsTilesAndAddHasCancelAndSave() {
        let app = launch("AMSWS_GEAR_PAGE")
        XCTAssertTrue(any(app, "gear-page").waitForExistence(timeout: 15), "the gear page did not open")
        XCTAssertTrue(any(app, "gear-tile-0").waitForExistence(timeout: 5))
        any(app, "gear-add").tap()
        XCTAssertTrue(any(app, "gear-save").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "gear-cancel").exists)
        any(app, "gear-cancel").tap()
        XCTAssertTrue(any(app, "gear-tile-0").waitForExistence(timeout: 5))
    }
}
