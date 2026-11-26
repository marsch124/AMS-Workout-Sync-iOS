import XCTest

/* The Training load and Fitness cards with invented numbers (AMSWS_FAKE_GARMIN: no network, no key). */
final class Body29LoadUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testTheLoadAndFitnessCardsAndTheLoadSheet() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "body"
        app.launch()

        let load = any(app, "body-training-load")
        var n = 0
        while !load.exists && n < 10 { app.swipeUp(); n += 1 }
        XCTAssertTrue(load.exists, "no Training load card")
        XCTAssertTrue(load.label.contains("7 days"), "the card said \(load.label)")
        XCTAssertTrue(load.label.contains("ratio"), "no ratio: \(load.label)")
        let fit = any(app, "body-fitness")
        XCTAssertTrue(fit.exists, "no Fitness card")
        XCTAssertTrue(fit.label.contains("Fitness age 49"), "the card said \(fit.label)")
        XCTAssertTrue(fit.label.contains("years younger"), "no age line: \(fit.label)")

        load.tap()
        XCTAssertTrue(any(app, "body-training-load-done").waitForExistence(timeout: 5), "the sheet did not open")
        any(app, "body-training-load-done").tap()
        XCTAssertTrue(load.waitForExistence(timeout: 5))
    }
}
