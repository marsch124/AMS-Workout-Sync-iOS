import XCTest

/*
 * The suggestion card on Today, the stop-sign page and the Settings log,
 * found by identifier. The same invented fortnight as the other screen
 * tests, the app as the plan's home, on Wednesday 16 September 2026.
 * AMSWS_SUGGEST=card puts a card on Today (made by the rule book from two
 * invented poor mornings, or a fixed sample when it stays silent).
 */
final class SuggestionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(suggest: String? = "card") -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        if let suggest { app.launchEnvironment["AMSWS_SUGGEST"] = suggest }
        app.launch()
        return app
    }

    /* Keep my plan closes the card, and Settings › Suggestions lists it. */
    func testKeepMyPlanClosesTheCardAndItIsLogged() {
        let app = launch()
        let card = app.otherElements["suggestion-card"]
        XCTAssertTrue(app.staticTexts["suggestion-headline"].waitForExistence(timeout: 15), "no card on Today")
        XCTAssertTrue(app.staticTexts["suggestion-why"].exists)
        XCTAssertTrue(app.buttons["suggestion-take"].exists)
        app.buttons["suggestion-keep"].tap()
        XCTAssertFalse(app.staticTexts["suggestion-headline"].waitForExistence(timeout: 2), "the card stayed")
        XCTAssertFalse(card.exists)

        app.buttons["tab-settings"].tap()
        let row = app.buttons["settings-suggestions"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Settings has no Suggestions row")
        row.tap()
        XCTAssertTrue(app.switches["suggest-on"].waitForExistence(timeout: 5))
        let log = app.descendants(matching: .any)["suggest-log-row"]
        for _ in 0..<4 where !log.exists { app.swipeUp() }
        XCTAssertTrue(log.waitForExistence(timeout: 5), "the kept card is not in the log")
    }

    /* Take it: the card's place says "Changed — Undo"; Undo takes it back. */
    func testTakeItShowsChangedUndo() {
        let app = launch()
        XCTAssertTrue(app.buttons["suggestion-take"].waitForExistence(timeout: 15), "no card on Today")
        app.buttons["suggestion-take"].tap()
        XCTAssertTrue(app.staticTexts["suggestion-changed"].waitForExistence(timeout: 5), "no Changed line")
        let undo = app.buttons["suggestion-undo"]
        XCTAssertTrue(undo.exists)
        undo.tap()
        XCTAssertFalse(app.staticTexts["suggestion-changed"].waitForExistence(timeout: 2), "Undo left the Changed line")
    }

    /* The quiet Stop sign button on Today opens the page with its fixed heading; opening it pauses, "Opened by mistake" takes it back. */
    func testStopSignPageOpens() {
        let app = launch(suggest: nil)
        let stop = app.buttons["stop-sign"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "no Stop sign on Today")
        stop.tap()
        XCTAssertTrue(app.staticTexts["stop-title"].waitForExistence(timeout: 5), "the stop-sign page did not open")
        XCTAssertTrue(app.staticTexts["stop-paused"].exists, "opening the stop sign pauses")
        XCTAssertTrue(app.buttons["stop-mistake"].exists)
        app.buttons["stop-mistake"].tap()
        XCTAssertFalse(app.staticTexts["stop-title"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["ill-button"].exists, "\u{201C}I\u{2019}m ill\u{201D} has its own button")
    }
}
