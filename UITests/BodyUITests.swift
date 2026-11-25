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
}
