import XCTest

/*
 * The Gym sessions card on the Body page, with invented sessions (AMSWS_FAKE_GARMIN) and with no
 * folder chosen (AMSWS_GYM_NO_FOLDER). Found by identifier only.
 */
final class Body29GymUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(noFolder: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "body"
        if noFolder { app.launchEnvironment["AMSWS_GYM_NO_FOLDER"] = "1" }
        app.launch()
        return app
    }

    private func scrolled(_ app: XCUIApplication, to id: String) -> XCUIElement {
        let e = any(app, id)
        var n = 0
        while !e.exists && n < 12 { app.swipeUp(); n += 1 }
        return e
    }

    func testTheCardShowsTheLatestSessionAndSwitchesToAnother() {
        let app = launch(noFolder: false)
        XCTAssertTrue(scrolled(app, to: "body-gym-card").exists, "no Gym sessions card")
        XCTAssertTrue(any(app, "body-gym-head").label.contains("City Gym"), "the head line said \(any(app, "body-gym-head").label)")
        XCTAssertTrue(any(app, "body-gym-counts").label.contains("4 machines"), "counts: \(any(app, "body-gym-counts").label)")
        XCTAssertTrue(any(app, "body-gym-compare").label.hasPrefix("vs the one before"), "no compare line")
        XCTAssertTrue(any(app, "body-gym-machine-0").label.contains("Leg press"), "no machine line")
        XCTAssertFalse(any(app, "body-gym-back").exists)
        any(app, "body-gym-row-g2").tap()
        XCTAssertTrue(any(app, "body-gym-back").waitForExistence(timeout: 3), "no way back to the latest")
        XCTAssertFalse(any(app, "body-gym-compare").exists)
        any(app, "body-gym-back").tap()
        XCTAssertTrue(any(app, "body-gym-compare").waitForExistence(timeout: 3))
    }

    func testWithoutAFolderTheCardSaysHowItFills() {
        let app = launch(noFolder: true)
        XCTAssertTrue(scrolled(app, to: "body-gym-card").exists, "no Gym sessions card")
        XCTAssertTrue(any(app, "body-gym-empty").label.contains("AMS Triathlon Training"), "the line said \(any(app, "body-gym-empty").label)")
        XCTAssertTrue(any(app, "body-gym-choose").exists, "no Choose folder button")
    }
}
