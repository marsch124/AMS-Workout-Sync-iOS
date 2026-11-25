import XCTest

/*
 * The plan shared through iCloud (2.1), with a plain folder standing in for
 * iCloud (AMSWS_FAKE_CLOUD) — no Apple account, no real iCloud. Found by
 * identifier only.
 */
final class ICloudUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func freshFolder() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("amsws-cloud-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private var plan: URL { Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")! }

    /* The iPhone, its plan in the app: Settings → iCloud says the plan is the same on all devices, and lists this one. */
    func testICloudPageShowsStatus() {
        let app = XCUIApplication()
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_DEVICE"] = "phone"
        app.launchEnvironment["AMSWS_FAKE_CLOUD"] = freshFolder()
        app.launchEnvironment["AMSWS_TAB"] = "settings"
        app.launchEnvironment["AMSWS_CLOUD_PAGE"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["icloud-title"].waitForExistence(timeout: 15), "the iCloud page did not open")
        let status = app.descendants(matching: .any)["icloud-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let same = NSPredicate(format: "label CONTAINS 'Same on all devices'")
        expectation(for: same, evaluatedWith: status)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.descendants(matching: .any)["icloud-device-iPhone"].waitForExistence(timeout: 10), "this iPhone is not listed")
        XCTAssertTrue(app.buttons["icloud-sync-now"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["icloud-detail"].exists)
    }

    /* An iPad with nothing of its own: it waits for the plan, then takes it from iCloud and opens it. */
    func testDeviceTwoWaitsThenOpensThePlan() {
        let folder = freshFolder()
        let app = XCUIApplication()
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_DEVICE"] = "ipad"
        app.launchEnvironment["AMSWS_FAKE_CLOUD"] = folder
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["waiting-plan-none"].waitForExistence(timeout: 15),
                      "with nothing in iCloud it should say the plan lives on the iPhone")
        app.terminate()

        // The iPhone has put the plan in iCloud meanwhile (the fixture workbook, taken in).
        app.launchEnvironment["AMSWS_CLOUD_SEED"] = plan.path
        app.launch()
        // The "ready" words stand for two seconds only, so the proof is the opened plan itself.
        let session = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'today-session'")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30), "the plan did not arrive and open")
        XCTAssertFalse(app.staticTexts["waiting-plan-title"].exists, "still waiting after the plan arrived")
    }

    /*
     * 2.4.1. An iPad (or Mac) that still shows an old workbook, as his Mac did
     * from a link made in September: once the iPhone's plan is in iCloud, it
     * takes that plan by itself and no longer offers Dropbox.
     */
    func testADeviceShowingTheOldWorkbookTakesThePlanFromICloud() {
        let app = XCUIApplication()
        app.launchEnvironment["AMSWS_FILE"] = plan.path          // the workbook on screen, the plan NOT living in the app
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_DEVICE"] = "ipad"
        app.launchEnvironment["AMSWS_FAKE_CLOUD"] = freshFolder()
        app.launchEnvironment["AMSWS_CLOUD_SEED"] = plan.path     // the iPhone has put the plan in iCloud
        app.launch()

        let session = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'today-session'")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30), "no plan on screen")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["today-connect-dropbox"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 30), .completed,
                       "still on the old workbook: Today offers Dropbox although the plan is in iCloud")
        // The plan lives in the app now: it can be added to here.
        XCTAssertTrue(app.buttons["today-add-extra"].waitForExistence(timeout: 10) || app.buttons["not-well"].waitForExistence(timeout: 5),
                      "the plan from iCloud did not become the plan here")
    }
}
