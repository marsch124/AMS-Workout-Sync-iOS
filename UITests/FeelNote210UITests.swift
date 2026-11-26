import XCTest

/* 2.10: a tap on a face keeps the card for a few words; Save puts them under the morning line. */
final class FeelNote210UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAFaceThenAFewWordsShowsUnderTheMorningLine() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["feel-question"].waitForExistence(timeout: 15))
        app.buttons["feel-4"].tap()
        let field = app.textFields["feel-note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the card does not ask for a comment after the face")
        field.tap()
        field.typeText("sore legs")
        app.buttons["feel-note-save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the card stays after Save")
        let line = app.descendants(matching: .any).matching(identifier: "feel-note-line").firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5), "the comment is not shown under the morning line")
        XCTAssertTrue(line.label.contains("sore legs"), "the line reads: \(line.label)")
    }
}
