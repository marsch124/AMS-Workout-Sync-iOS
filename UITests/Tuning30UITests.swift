import XCTest

/*
 * Round 30, lane "tuning": the "Next week, tuned" card and the "Your sessions
 * point to stronger zones" card, found by identifier. The invented fortnight
 * of the other screen tests, the app as the plan's home, Wednesday 16
 * September 2026. AMSWS_TUNED and AMSWS_ZONES_SESSIONS show the cards whatever
 * the day, from invented situations (no Garmin, no Claude, no network).
 */
final class Tuning30UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    private func reveal(_ e: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(e.exists && e.isHittable) { app.swipeUp() }
    }

    /* Take it: "Changed — Undo" in the card's place; Undo brings the card back. */
    func testTunedCardTakeAndUndo() {
        let app = launch(["AMSWS_TUNED": "card"])
        let take = app.buttons["tuned-take"]
        reveal(take, in: app)
        XCTAssertTrue(take.waitForExistence(timeout: 15), "no Next week, tuned card on Today")
        XCTAssertTrue(app.staticTexts["tuned-line-0"].exists)
        XCTAssertTrue(app.staticTexts["tuned-why"].exists)
        XCTAssertTrue(app.buttons["tuned-keep"].exists)
        take.tap()
        let undo = app.buttons["tuned-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Changed — Undo")
        XCTAssertTrue(app.staticTexts["tuned-changed"].exists)
        undo.tap()
        XCTAssertTrue(app.buttons["tuned-take"].waitForExistence(timeout: 5), "Undo did not bring the card back")
    }

    /* Keep my plan puts the card away. */
    func testTunedKeepMyPlanClosesTheCard() {
        let app = launch(["AMSWS_TUNED": "card"])
        let keep = app.buttons["tuned-keep"]
        reveal(keep, in: app)
        XCTAssertTrue(keep.waitForExistence(timeout: 15))
        keep.tap()
        XCTAssertFalse(app.buttons["tuned-take"].waitForExistence(timeout: 2), "the card stayed")
    }

    /* Nothing to change: one calm line, no buttons. */
    func testStaysAsPlannedLine() {
        let app = launch(["AMSWS_TUNED": "stays"])
        let line = app.staticTexts["tuned-stays"]
        reveal(line, in: app)
        XCTAssertTrue(line.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["tuned-take"].exists)
    }

    /* The zones card on Today: Use the new zones, then Undo. */
    func testStrongerZonesUseAndUndo() {
        let app = launch(["AMSWS_ZONES_SESSIONS": "card"])
        let use = app.buttons["zones-sessions-use"]
        reveal(use, in: app)
        XCTAssertTrue(use.waitForExistence(timeout: 15), "no zones card on Today")
        XCTAssertTrue(app.descendants(matching: .any)["zones-sessions-row-pulse"].exists)
        XCTAssertTrue(app.buttons["zones-sessions-keep"].exists)
        use.tap()
        let undo = app.buttons["zones-sessions-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Changed — Undo")
        undo.tap()
        XCTAssertTrue(app.buttons["zones-sessions-use"].waitForExistence(timeout: 5), "Undo did not bring the card back")
    }

    /* Your zones: the run power zones card (invented 250 W). */
    func testRunPowerZonesOnTheZonesPage() {
        let app = launch(["AMSWS_ZONES": "1", "AMSWS_ZONES_SESSIONS": "power"])
        XCTAssertTrue(app.descendants(matching: .any)["run-power-card"].waitForExistence(timeout: 15), "no run power card")
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "run-power-row").count, 5)
    }
}
