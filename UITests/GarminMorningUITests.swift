import XCTest

/*
 * Garmin's morning numbers on Today and in Settings, with invented numbers
 * (AMSWS_FAKE_GARMIN: no network, no key). Found by identifier only.
 * Written and compiled; not run by the helper that wrote it.
 */
final class GarminMorningUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /* The line shows the numbers with the dot beside its words; a tap opens the plate with its rows. */
    func testTheLineShowsAndThePlateOpens() {
        let app = launch(["AMSWS_FAKE_GARMIN": "1"])
        let line = any(app, "morning-garmin")
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the Garmin line did not show")
        XCTAssertTrue(line.label.contains("HRV 64"), "the line should say HRV 64, it said \(line.label)")
        XCTAssertTrue(any(app, "morning-dot").exists, "no dot with its words")

        line.tap()
        XCTAssertTrue(any(app, "morning-plate").waitForExistence(timeout: 5), "the plate did not open")
        for name in ["hrv", "sleep", "resting", "bodybattery", "stress"] {
            XCTAssertTrue(any(app, "morning-row-" + name).exists, "no row for \(name)")
        }
        app.buttons["morning-plate-done"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5))
    }

    /* Without a key nothing new shows on Today. */
    func testNoKeyNoLine() {
        let app = launch([:])
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        XCTAssertFalse(any(app, "morning-garmin").waitForExistence(timeout: 3))
    }

    /* The settings page will not save an empty key, and says why in words. */
    func testAnEmptyKeyIsRefusedInWords() {
        let app = launch(["AMSWS_GARMIN_PAGE": "1"])
        let save = any(app, "garmin-save")
        XCTAssertTrue(save.waitForExistence(timeout: 15), "the Garmin page did not open")
        XCTAssertTrue(any(app, "garmin-key").exists)
        XCTAssertTrue(any(app, "garmin-cancel").exists)
        save.tap()
        let problem = any(app, "garmin-problem")
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "no red line for an empty key")
        XCTAssertFalse(problem.label.isEmpty)
    }
}
