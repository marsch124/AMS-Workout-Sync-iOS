import XCTest

/* The Health part of the Body page with invented numbers (AMSWS_FAKE_GARMIN: no network, no key). Found by identifier only. */
final class Body29HealthUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrolled(_ app: XCUIApplication, to id: String) -> XCUIElement {
        let e = any(app, id)
        var n = 0
        while !e.exists && n < 12 { app.swipeUp(); n += 1 }
        return e
    }

    private func launch(noWater: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "body"
        if noWater { app.launchEnvironment["AMSWS_BODY_NO_WATER"] = "1" }
        app.launch()
        return app
    }

    func testTheHealthCardsShowTheirWordsAndSleepDebtOpensItsNights() {
        let app = launch()
        let debt = scrolled(app, to: "body-sleep-debt")
        XCTAssertTrue(debt.waitForExistence(timeout: 15), "no Sleep debt card")
        XCTAssertTrue(debt.label.contains("Sleep debt"), debt.label)
        XCTAssertTrue(debt.label.contains("over 7 nights"), debt.label)
        let weight = scrolled(app, to: "body-weight")
        XCTAssertTrue(weight.exists, "no Weight card")
        XCTAssertTrue(weight.label.contains("kg"), weight.label)
        XCTAssertTrue(scrolled(app, to: "body-energy").label.contains("kcal"))
        XCTAssertTrue(scrolled(app, to: "body-water").label.contains("Water 1,250 ml"))
        debt.tap()
        XCTAssertTrue(any(app, "body-sleep-debt-sheet-row-0").waitForExistence(timeout: 5), "the nights did not open")
        any(app, "body-sleep-debt-sheet-done").tap()
    }

    func testWaterNotLoggedSaysSoCalmly() {
        let app = launch(noWater: true)
        let water = scrolled(app, to: "body-water")
        XCTAssertTrue(water.waitForExistence(timeout: 15), "no Water card")
        XCTAssertTrue(water.label.contains("No water logged today. Log it in Garmin Connect."), water.label)
    }
}
