import XCTest

/* 2.22: Settings › How this works — a picture opens big in a sheet and Done closes it again. */
final class Guide222UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testTheGuideOpensAPictureBigAndDoneClosesIt() {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_TAB"] = "settings"
        app.launch()

        let row = app.buttons["settings-how-it-works"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no How this works row in Settings")
        for _ in 0..<12 where !row.isHittable { app.swipeUp() }
        row.tap()
        let picture = app.buttons["guidePicture-today"]
        XCTAssertTrue(picture.waitForExistence(timeout: 15), "the guide has no Today picture")
        picture.tap()
        let viewer = app.descendants(matching: .any)["guideViewer"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), "the picture did not open big")
        let done = app.buttons["guideViewerDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no Done in the big picture")
        done.tap()
        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: viewer)], timeout: 5)
        XCTAssertTrue(picture.waitForExistence(timeout: 5), "the guide did not come back")
    }
}
