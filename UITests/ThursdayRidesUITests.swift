import XCTest

/*
 * Thursday rides: Settings → Thursday rides, on the same invented fortnight as
 * the other screen tests. That plan may hold few weeks or none, so the test
 * asks only that the page opens and says one of the three honest things.
 */
final class ThursdayRidesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testThePageOpensAndSaysWhatItWillDo() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_RIDES"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["rides-title"].waitForExistence(timeout: 15), "the page did not open")
        XCTAssertTrue(app.buttons["rides-cancel"].exists)
        let add = app.buttons["rides-add"]
        let already = app.staticTexts["rides-already"]
        let none = app.staticTexts["rides-none"]
        let found = add.waitForExistence(timeout: 5) || already.exists || none.exists
        XCTAssertTrue(found, "the page says neither what it adds nor why it adds nothing")

        if add.exists {
            XCTAssertTrue(app.descendants(matching: .any)["rides-row"].exists)
            add.tap()
            XCTAssertTrue(app.staticTexts["rides-done"].waitForExistence(timeout: 5), "no word that the rides were added")
            XCTAssertFalse(add.exists, "the button stayed after the rides were added")
        }
    }
}
