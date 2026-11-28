import XCTest

/*
 * Session score and Fitter at the same pulse, with invented Garmin answers (AMSWS_FAKE_GARMIN) on the invented plan.
 * Found by identifier only.
 */
final class Score30UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan-done", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    func testADoneSessionShowsItsWord() {
        for (mode, word) in [("on", "On target"), ("hard", "A bit hard"), ("too", "Too hard")] {
            let app = launch(["AMSWS_DONE": "run", "AMSWS_SCORE": mode])
            let w = app.descendants(matching: .any)["session-score-word"]
            XCTAssertTrue(w.waitForExistence(timeout: 20), "no score word for \(mode)")
            XCTAssertEqual(w.label, word)
            XCTAssertTrue(app.descendants(matching: .any)["session-score-line"].label.contains("min in zone"))
            app.terminate()
        }
    }

    func testProgressHasTheCardAndItsPage() {
        // Since 2.20 Progress opens with the colour tiles and the card sits far down: open it at the Routes card, which the card follows.
        let app = launch(["AMSWS_TAB": "progress", "AMSWS_SCROLL": "routes"])
        // The card is a button, and SwiftUI names a button after the identifiers inside it ("fitter-line-run-fitter-line-ride-..."),
        // so "fitter-card" is not on the screen: the card is found by its lines, and a tap on the first line is a tap on the card.
        let run = app.descendants(matching: .any)["fitter-line-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 20), "no Fitter card")
        XCTAssertTrue(app.descendants(matching: .any)["fitter-line-ride"].exists)
        run.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fitter-page"].waitForExistence(timeout: 10), "the page did not open")
        XCTAssertTrue(app.descendants(matching: .any)["fitter-tile-run"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["fitter-tile-ride"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["fitter-how"].exists)
    }
}
