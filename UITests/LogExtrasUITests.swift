import XCTest

/*
 * The four extra notes, with invented data (picture switches; nothing touches the shelf). Found by identifier only.
 */
final class LogExtrasUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ switchName: String) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment[switchName] = "1"
        app.launch()
        return app
    }

    func testTheLogFormRowsShowAndOfferTheSum() {
        let app = launch("AMSWS_LOG_EXTRAS")
        for id in ["brick-bike", "brick-change", "brick-run", "brick-use-sum", "stomach-row", "stomach-fine",
                   "stomach-line", "fuel-notes-open", "niggle-row", "openwater-switch", "openwater-wetsuit", "openwater-temp"] {
            XCTAssertTrue(any(app, id).waitForExistence(timeout: 10), "no \(id)")
        }
        any(app, "niggle-row").tap()
        XCTAssertTrue(any(app, "niggle-place-calf").waitForExistence(timeout: 5), "no place list")
        any(app, "niggle-place-calf").tap()
        XCTAssertTrue(any(app, "niggle-side-left").waitForExistence(timeout: 5), "no side choice for a calf")
        XCTAssertTrue(any(app, "niggle-save").exists)
    }

    func testTheDoneBlockAndTheTwoPages() {
        let app = launch("AMSWS_DONE_EXTRAS")
        XCTAssertTrue(any(app, "session-notes-block").waitForExistence(timeout: 10), "no notes block")
        let fuel = launch("AMSWS_FUEL_NOTES")
        XCTAssertTrue(any(fuel, "fuel-notes").waitForExistence(timeout: 10), "no fuel notes page")
        let card = launch("AMSWS_NIGGLES_CARD")
        XCTAssertTrue(any(card, "niggles-card").waitForExistence(timeout: 10), "no niggles card")
    }
}
