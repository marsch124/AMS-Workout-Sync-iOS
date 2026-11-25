import XCTest

/*
 * Notes from the neighbour apps, with invented notes (AMSWS_FAKE_NOTES=1: a feel of
 * today from Magic Morning, a strength note for the day, four stretch mornings;
 * both apps pretend to be installed). The invented fortnight's strength session is
 * Sunday 13 September 2026.
 */
final class NeighbourUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-13"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_NOTES"] = "1"
        app.launch()
        return app
    }

    func testTheMorningQuestionIsNotAskedAndTheLineSaysWhereTheAnswerCame() {
        let app = launch()
        let line = app.staticTexts["feel-from-neighbour"]
        XCTAssertTrue(line.waitForExistence(timeout: 15))
        XCTAssertEqual(line.label, "Feeling good — from Magic Morning")
        XCTAssertFalse(app.staticTexts["feel-question"].exists, "the question was asked although the answer was in the notes")
    }

    func testStrengthDoneElsewhereIsLoggedOnlyByTheButton() {
        let app = launch()
        let done = app.staticTexts["neighbour-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "no done line on today's strength card")
        XCTAssertTrue(done.label.hasPrefix("Done in Workouts at 07:40"), done.label)
        XCTAssertTrue(done.label.hasSuffix("35 min"), done.label)

        let strength = app.buttons["today-session-2026-09-13-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        strength.tap()
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-workouts"].exists, "no Open Workouts although the app is there")
        let log = app.buttons["neighbour-log"].firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        let after = app.staticTexts["neighbour-done"].firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        XCTAssertEqual(after.label, "Logged from Workouts")
        XCTAssertFalse(app.buttons["neighbour-log"].exists, "Log it is offered again")
    }
}
