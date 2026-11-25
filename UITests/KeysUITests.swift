import UIKit
import XCTest

/*
 * The Keys plate of the wide look (iPad, and the iPad app on the Mac): a word "Keys" at the foot of the side list
 * opens a plate that lists every key. Written and compiled; run on an iPad simulator only (skipped on an iPhone).
 */
final class KeysUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(plate: Bool) throws -> XCUIApplication {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "The wide look is tested on an iPad simulator")
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        if plate { app.launchEnvironment["AMSWS_KEYS"] = "1" }
        app.launch()
        return app
    }

    func testKeysPlateOpensFromTheSideList() throws {
        let app = try launch(plate: false)
        let open = app.buttons["keys-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15), "no Keys word at the foot of the side list")
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keys-plate"].waitForExistence(timeout: 5), "the Keys plate did not open")
        XCTAssertTrue(app.descendants(matching: .any)["keys-row-0"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["keys-row-7"].exists, "the list stops short")
        app.buttons["keys-done"].tap()
        XCTAssertTrue(app.buttons["keys-open"].waitForExistence(timeout: 5))
    }

    func testKeysPlateOpensForAPicture() throws {
        let app = try launch(plate: true)
        XCTAssertTrue(app.descendants(matching: .any)["keys-plate"].waitForExistence(timeout: 15))
    }
}
