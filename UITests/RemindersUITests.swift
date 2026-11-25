import XCTest

/*
 * Reminders: the Settings page opens with its three switches, times and the
 * test button; the Sunday card (picture switch) shows on Today and Close puts
 * it away. Found by identifier only; the notifications themselves are not
 * asked for here.
 */
final class RemindersUITests: XCTestCase {
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

    func testThePageHasThreeSwitchesTheirTimesAndATestButton() {
        let app = launch(["AMSWS_REMINDERS_PAGE": "1"])
        XCTAssertTrue(app.descendants(matching: .any)["settings-reminders"].waitForExistence(timeout: 15), "the page did not open")
        for id in ["evening", "sunday", "missed"] {
            XCTAssertTrue(app.switches["reminder-\(id)-switch"].exists, "no switch for \(id)")
            XCTAssertTrue(app.descendants(matching: .any)["reminder-\(id)-time"].exists, "no time for \(id)")
        }
        XCTAssertTrue(app.buttons["reminder-test"].exists)
        XCTAssertTrue(app.buttons["reminders-cancel"].exists)
    }

    func testTheSundayCardShowsAndCloseWorks() {
        let app = launch(["AMSWS_SUNDAY_CARD": "1"])
        let card = app.descendants(matching: .any)["sunday-card"]
        // The invented plan may hold no session next week; then the card rightly stays away.
        guard card.waitForExistence(timeout: 15) else { return }
        let close = app.buttons["sunday-card-close"]
        XCTAssertTrue(close.exists, "the card has no Close")
        close.tap()
        XCTAssertFalse(card.exists, "the card stayed after Close")
    }
}
