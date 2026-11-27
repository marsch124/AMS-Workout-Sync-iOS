import XCTest

/*
 * 2.20 Progress navigation: the colour tiles under the title, a tap on Zones jumps to the zones card
 * (which is now there with a key), and the pinned chip row appears with Zones lit. Found by identifier only.
 */
final class ProgressNav220UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testTilesJumpAndTheChipRowLightsThePart() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan-done", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_GARMIN"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "progress"
        app.launch()
        XCTAssertTrue(any(app, "progress-tiles").waitForExistence(timeout: 15), "no tiles on Progress")
        for part in ["race", "kept", "routes", "zones"] {
            XCTAssertTrue(any(app, "progress-tile-" + part).exists, "no \(part) tile")
        }
        XCTAssertFalse(any(app, "progress-chips").exists, "the chip row shows while the tiles are in sight")
        any(app, "progress-tile-zones").tap()
        XCTAssertTrue(any(app, "zones-card").waitForExistence(timeout: 10), "no zones card after the jump")
        let chip = any(app, "progress-chip-zones")
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "no pinned chip row after the jump")
        XCTAssertTrue(chip.isSelected, "the Zones chip is not lit")
        any(app, "progress-chip-kept").tap()
        XCTAssertTrue(any(app, "progress-chip-kept").waitForExistence(timeout: 5))
    }
}
