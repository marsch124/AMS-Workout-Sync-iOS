import XCTest

/*
 * Entering a test result: the app as the plan's home, the zones page opened
 * by the picture switch, a test with invented numbers typed in and saved.
 */
final class TestEntryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testEnterATestAndSeeItInTheList() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_TEST"] = "1"
        app.launch()

        let enter = app.buttons["test-enter"]
        XCTAssertTrue(enter.waitForExistence(timeout: 15), "the zones page has no way to enter a test")
        let before = app.otherElements.matching(identifier: "test-row").count
        enter.tap()

        // Nothing typed: refused in one red line, and the page stays.
        let save = app.buttons["test-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["test-problem"].waitForExistence(timeout: 3), "an empty test was not refused")

        let pulse = app.textFields["test-lthr"]
        pulse.tap(); pulse.typeText("160")
        let ftp = app.textFields["test-ftp"]
        ftp.tap(); ftp.typeText("200")
        let swim = app.textFields["test-swim"]
        swim.tap(); swim.typeText("1:50")
        let weight = app.textFields["test-weight"]
        weight.tap(); weight.typeText("70")
        save.tap()

        XCTAssertFalse(app.buttons["test-save"].waitForExistence(timeout: 3), "the page did not close")
        XCTAssertTrue(app.otherElements["test-row"].firstMatch.waitForExistence(timeout: 5), "the new test is not in the list")
        XCTAssertGreaterThanOrEqual(app.otherElements.matching(identifier: "test-row").count, max(before, 1))
    }
}
