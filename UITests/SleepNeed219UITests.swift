import XCTest

/* 2.19: Settings › Garmin › Sleep need — the row reads 6h at the start; a choice and Save carry the new need back to the row. */
final class SleepNeed219UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSleepNeedStartsAtSixHoursAndSaves() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "settings"
        app.launch()

        let row = app.buttons["garmin-sleep-need"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no Sleep need row in Settings")
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.tap()
        let six = app.buttons["sleep-need-360"]
        XCTAssertTrue(six.waitForExistence(timeout: 5), "the Sleep need page did not open")
        XCTAssertTrue(six.isSelected, "6h is not the chosen need at the start")
        XCTAssertTrue(app.buttons["sleep-need-0"].exists, "no Garmin's estimate choice")
        XCTAssertTrue(app.buttons["sleep-need-cancel"].exists)
        app.buttons["sleep-need-420"].tap()
        XCTAssertTrue(app.buttons["sleep-need-420"].isSelected, "the tap did not choose 7h")
        app.buttons["sleep-need-save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Save did not bring Settings back")
        XCTAssertTrue(row.label.contains("7h"), "the row reads: \(row.label)")
    }
}
