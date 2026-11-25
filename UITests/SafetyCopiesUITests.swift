import XCTest

/*
 * Settings → Safety copies, opened straight with the picture switches
 * (AMSWS_SAFETY, which files two copies of the plan for the days before). The
 * app is the plan's home. Found by identifier only.
 */
final class SafetyCopiesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPutASafetyCopyBack() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_SAFETY"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["safety-title"].waitForExistence(timeout: 15), "the page did not open")
        let rows = app.descendants(matching: .any).matching(identifier: "safety-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2, "expected two safety copies")

        let put = app.buttons.matching(identifier: "safety-put-back").firstMatch
        XCTAssertTrue(put.waitForExistence(timeout: 5), "no button to put a copy back")
        put.tap()
        let confirm = app.buttons["safety-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "it did not ask first")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["safety-done"].waitForExistence(timeout: 5), "no word that the plan is back")
    }
}
