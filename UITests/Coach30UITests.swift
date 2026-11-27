import XCTest

/*
 * Round 30, lane coach: the Drill cards page and a card, the Swim video check
 * with invented pictures and tips, the block card on Today, and the rows on a
 * swim session. Found by identifier only.
 */
final class Coach30UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    func testDrillCardsPageOpensACardWithThreeSteps() {
        let app = launch(["AMSWS_DRILL_CARDS": "1"])
        XCTAssertTrue(app.descendants(matching: .any)["drill-cards-page"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["drill-cards-swim-check"].exists)
        let tile = app.descendants(matching: .any)["drill-tile-catch-up"]
        XCTAssertTrue(tile.exists)
        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["drill-card-catch-up"].waitForExistence(timeout: 10))
        for n in 1...3 { XCTAssertTrue(app.descendants(matching: .any)["drill-step-\(n)"].exists, "step \(n)") }
        XCTAssertTrue(app.descendants(matching: .any)["drill-trains"].exists)
    }

    func testSwimCheckShowsSixPicturesAndThreeTipsAfterSending() {
        let app = launch(["AMSWS_SWIM_CHECK": "1", "AMSWS_FAKE_CLAUDE": "1"])
        XCTAssertTrue(app.descendants(matching: .any)["swim-check-page"].waitForExistence(timeout: 15))
        for n in 1...6 { XCTAssertTrue(app.descendants(matching: .any)["swim-check-frame-\(n)"].exists, "frame \(n)") }
        XCTAssertTrue(app.descendants(matching: .any)["swim-check-sent"].exists)
        let send = app.buttons["swim-check-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        for n in 1...3 { XCTAssertTrue(app.descendants(matching: .any)["swim-tip-\(n)"].waitForExistence(timeout: 10), "tip \(n)") }
    }

    func testTheBlockCardShowsOnTodayAndGotItPutsItAway() {
        let app = launch(["AMSWS_BLOCK_INTRO": "build"])
        XCTAssertTrue(app.descendants(matching: .any)["block-intro-card"].waitForExistence(timeout: 15))
        for id in ["block-intro-for", "block-intro-different", "block-intro-watch"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].exists, id)
        }
        app.buttons["block-intro-got-it"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.descendants(matching: .any)["block-intro-card"])
        waitForExpectations(timeout: 10)
    }

    func testASwimSessionOffersTheDrillCardsAndTheCheck() {
        let app = launch(["AMSWS_PLANNED": "swim"])
        XCTAssertTrue(app.buttons["session-swim-check"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["session-drill-cards"].exists)
    }
}
