import XCTest

/*
 * Round 28, Claude: "Your week with Claude" and "Ask about your plan". No network,
 * no key: AMSWS_FAKE_CLAUDE with the picture switches. Found by identifier only.
 * Written and compiled; not run by the helper that wrote it.
 */
final class ClaudeReviewUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_CLAUDE"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /* The card shows five lines and the question; there is no button once the week is written. */
    func testTheReviewCardShowsFiveLinesAndAQuestion() {
        let app = launch(["AMSWS_CLAUDE_REVIEW": "1"])
        XCTAssertTrue(any(app, "claude-review-card").waitForExistence(timeout: 15), "the card did not show")
        XCTAssertTrue(any(app, "claude-review-question").exists)
        for n in 1...5 { XCTAssertTrue(any(app, "claude-review-line-\(n)").exists, "line \(n) missing") }
        XCTAssertFalse(any(app, "claude-review-line-6").exists)
        XCTAssertFalse(any(app, "claude-review-write").exists)
    }

    /* Before it is written: what is sent, and the one full-colour button; the tap brings the answer. */
    func testWriteMyWeekBringsTheAnswer() {
        let app = launch(["AMSWS_CLAUDE_REVIEW": "write"])
        let write = any(app, "claude-review-write")
        XCTAssertTrue(write.waitForExistence(timeout: 15), "the button did not show")
        XCTAssertTrue(any(app, "claude-review-sent").label.contains("no names, no notes"))
        write.tap()
        XCTAssertTrue(any(app, "claude-review-question").waitForExistence(timeout: 10), "no answer after the tap")
        XCTAssertTrue(any(app, "claude-review-line-5").exists)
    }

    /* The page with one invented question and answer, and Clear takes them away. */
    func testTheAskPageShowsAnAnswerAndClears() {
        let app = launch(["AMSWS_CLAUDE_ASK": "1"])
        XCTAssertTrue(any(app, "claude-ask-field").waitForExistence(timeout: 15), "the page did not open")
        XCTAssertTrue(any(app, "claude-ask-answer").exists)
        XCTAssertTrue(any(app, "claude-ask-send").exists)
        any(app, "claude-ask-clear").tap()
        XCTAssertFalse(any(app, "claude-ask-answer").waitForExistence(timeout: 3), "the answer stayed after Clear")
    }

    /* A typed question gets an answer; one about pain is answered by the app itself. */
    func testAskingAndTheDoctorLine() {
        let app = launch(["AMSWS_CLAUDE_ASK": "empty"])
        let field = any(app, "claude-ask-field")
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Why is Thursday's ride short?")
        any(app, "claude-ask-send").tap()
        XCTAssertTrue(any(app, "claude-ask-answer").waitForExistence(timeout: 10))
        field.tap()
        field.typeText("My knee hurts today")
        any(app, "claude-ask-send").tap()
        XCTAssertTrue(any(app, "claude-ask-answer").label.contains("doctor"), "the pain question was not met with the doctor line")
    }
}
