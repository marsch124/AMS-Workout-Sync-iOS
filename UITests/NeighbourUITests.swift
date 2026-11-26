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
        let line = app.descendants(matching: .any)["feel-from-neighbour"]
        XCTAssertTrue(line.waitForExistence(timeout: 15))
        XCTAssertEqual(line.label, "Feeling good — from Magic Morning")
        XCTAssertFalse(app.staticTexts["feel-question"].exists, "the question was asked although the answer was in the notes")
    }

    /* 2.16: a finished Workout Companion workout ticks today's strength session by itself — no Log it. */
    func testStrengthDoneInWorkoutCompanionTicksItself() {
        let app = launch()
        let done = app.staticTexts["neighbour-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "no line on today's strength card")
        XCTAssertEqual(done.label, "Ticked from Workout Companion")
        XCTAssertFalse(app.buttons["neighbour-log"].exists, "Log it is offered although the session ticked itself")

        let strength = app.buttons["today-session-2026-09-13-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        strength.tap()
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-workouts"].exists, "no Open Workout Companion although the app is there")
        XCTAssertEqual(app.buttons["open-workouts"].label, "Open Workout Companion")
        let after = app.staticTexts["neighbour-done"].firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        XCTAssertEqual(after.label, "Ticked from Workout Companion")
    }
}
