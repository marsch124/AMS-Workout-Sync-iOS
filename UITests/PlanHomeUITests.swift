import XCTest

/*
 * The plan moving into the app, driven the way he does it: Settings, take the
 * plan in, look at the verdict, tap the switch, and carry on logging with no
 * Dropbox. Everything is found by identifier. Same invented fixture as the
 * other screen tests.
 */
final class PlanHomeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testThePlanMovesIntoTheAppAndLoggingWorksWithoutDropbox() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["tab-settings"].waitForExistence(timeout: 15))
        app.buttons["tab-settings"].tap()

        let start = app.buttons["plan-move-in"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Settings has no way to start the move")
        start.tap()

        let take = app.buttons["movein-take"]
        XCTAssertTrue(take.waitForExistence(timeout: 10))
        take.tap()

        let verdict = app.descendants(matching: .any).matching(identifier: "proof-verdict").firstMatch
        XCTAssertTrue(verdict.waitForExistence(timeout: 30), "the two sides were never counted")
        XCTAssertTrue(app.staticTexts["Everything matches."].exists, "the counts should match for the fixture")

        let makeHome = app.buttons["movein-switch"]
        XCTAssertTrue(makeHome.waitForExistence(timeout: 5))
        makeHome.tap()

        let done = app.buttons["movein-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the page does not say the move is done")
        done.tap()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "plan-home").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Lives in this app"].exists, "Settings does not say the plan lives in the app")

        // Open the one session of the day and mark it done as planned: no Dropbox is connected.
        app.buttons["tab-today"].tap()
        let session = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'today-session'")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10), "Today shows no session")
        session.tap()
        let asPlanned = app.buttons["session-done-as-planned"]
        XCTAssertTrue(asPlanned.waitForExistence(timeout: 10), "Done as planned is missing without Dropbox")
        asPlanned.tap()
        // The tick beside the title is labelled "Done"; the button is gone once it is.
        let tick = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Done'")).firstMatch
        XCTAssertTrue(tick.waitForExistence(timeout: 10), "the done mark did not appear")
        XCTAssertFalse(app.buttons["session-done-as-planned"].exists, "the session is still offered as not done")
    }
}
