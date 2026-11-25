import XCTest

/*
 * A done session's "From your watch" and the Progress zones card, with
 * invented numbers (AMSWS_FAKE_GARMIN, AMSWS_ZONES_CARD: no network, no
 * key). Found by identifier only. Written and compiled; not run by the
 * helper that wrote it.
 */
final class GarminActivityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        // plan-done.xlsx: the invented plan with four sessions logged (the plain plan has none, so no session page is "done").
        let plan = Bundle(for: Self.self).url(forResource: "plan-done", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /* AMSWS_HURTS opens the first logged session: its watch section, laps and the last-time card show. */
    func testADoneSessionShowsTheWatchSectionAndLastTime() {
        let app = launch(["AMSWS_FAKE_GARMIN": "1", "AMSWS_HURTS": "1"])
        XCTAssertTrue(any(app, "watch-section").waitForExistence(timeout: 15), "no From your watch section")
        XCTAssertTrue(any(app, "watch-pulse").exists, "no pulse curve")
        XCTAssertTrue(any(app, "watch-laps").exists, "no laps")
        XCTAssertFalse(any(app, "watch-laps-all").exists, "six laps need no Show all button")
        XCTAssertTrue(any(app, "last-time-card").exists, "no Last time card")
    }

    /* Without a key the section is simply not there. */
    func testNoKeyNoWatchSection() {
        let app = launch(["AMSWS_HURTS": "1"])
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 15))
        XCTAssertFalse(any(app, "watch-section").waitForExistence(timeout: 3))
    }

    /* Progress: five slim bars, one per zone. */
    func testProgressShowsTheZonesCard() {
        let app = launch(["AMSWS_ZONES_CARD": "1", "AMSWS_TAB": "progress"])
        let card = any(app, "zones-card")
        var tries = 0
        while !card.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no zones card")
        for n in 1...5 { XCTAssertTrue(any(app, "zones-bar-\(n)").exists, "no bar for Z\(n)") }
    }
}
