import XCTest

/* The month's workouts card on the Body page, with invented numbers (AMSWS_FAKE_GARMIN). Found by identifier only. */
final class Body29WorkoutsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testTheMonthCardListsWorkoutsAndOpensAllOfThem() {
        let app = XCUIApplication()
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "body"
        app.launch()

        let card = any(app, "body-month-card")
        var n = 0
        while !card.exists && n < 12 { app.swipeUp(); n += 1 }
        XCTAssertTrue(card.exists, "no month card")
        XCTAssertTrue(any(app, "body-month-totals").exists, "no totals line")
        let all = any(app, "body-month-all")
        n = 0
        while !all.exists && n < 4 { app.swipeUp(); n += 1 }
        XCTAssertTrue(all.exists, "no All workouts button")
        all.tap()
        let done = any(app, "body-month-done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the sheet did not open")
        done.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }
}
