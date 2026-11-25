import XCTest

/*
 * Away mode and the no-gym version: the page opens with its switch, dates and
 * four things; an invented period shows the grey line on Today and a chip; the
 * no-gym card opens and Done closes it. Found by identifier only.
 */
final class AwayUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    func testThePageHasASwitchDatesAndFourThings() {
        let app = launch(["AMSWS_AWAY_PAGE": "1"])
        XCTAssertTrue(app.descendants(matching: .any)["settings-away"].waitForExistence(timeout: 15), "the page did not open")
        XCTAssertTrue(app.switches["away-switch"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["away-from"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["away-until"].exists)
        for thing in ["pool", "bike", "gym", "openwater"] {
            XCTAssertTrue(app.switches["away-has-\(thing)"].exists, "no switch for \(thing)")
        }
        XCTAssertTrue(app.buttons["away-save"].exists)
        app.buttons["away-cancel"].tap()
    }

    func testWhileAwayTodayShowsTheGreyLine() {
        let app = launch(["AMSWS_AWAY": "nopool"])
        XCTAssertTrue(app.descendants(matching: .any)["away-today-line"].waitForExistence(timeout: 15), "no grey line on Today")
    }

    func testTheNoGymCardOpensAndDoneClosesIt() {
        let app = launch(["AMSWS_NOGYM": "1"])
        XCTAssertTrue(app.descendants(matching: .any)["nogym-card"].waitForExistence(timeout: 15), "the card did not open")
        app.buttons["nogym-done"].tap()
        XCTAssertTrue(app.buttons["nogym-open"].waitForExistence(timeout: 5))
    }
}
