import XCTest

/*
 * 2.19 Routes: the Progress card and the Routes page, with invented routes
 * (AMSWS_FAKE_GARMIN: no network, no key). Found by identifier only.
 * Written and compiled; not run by the helper that wrote it.
 */
final class RoutesMap31UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testTheRoutesCardOpensTheRoutesPage() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan-done", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "progress"
        app.launch()
        let card = any(app, "progress-routes-card")
        var tries = 0
        while !card.exists && tries < 8 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no Routes card on Progress")
        card.tap()
        XCTAssertTrue(any(app, "routes-filter-run").waitForExistence(timeout: 10), "no Run chip on the Routes page")
        XCTAssertTrue(any(app, "routes-month").exists, "no month label")
        XCTAssertTrue(any(app, "routes-month-prev").exists, "no previous month")
        any(app, "routes-done").tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Done did not return to Progress")
    }
}
