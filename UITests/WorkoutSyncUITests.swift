import XCTest

/*
 * The app driven the way he uses it, found by accessibility identifier and
 * never by its words — a label can be improved without a test noticing.
 *
 * Every test opens the same small workbook (UITests/Fixtures/plan.xlsx: the
 * web app's "plain" fortnight plus an invented zones sheet — never his real
 * plan) on a fixed day, Wednesday 16 September 2026, whose one session is a
 * 35-minute run at Z2.
 *
 * Grown one test at a time; each was seen to go red when the thing it names
 * was broken on purpose.
 */
final class WorkoutSyncUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /* Every test starts clean: nothing waiting to sync, nothing remembered. */
    private func launch(canLog: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        if canLog { app.launchEnvironment["AMSWS_SHOW_BUTTONS"] = "1" }
        app.launch()
        return app
    }

    /* 4. Once a session is logged, Missed and Move are gone and only a small Adjust stays. */
    func testLoggingLeavesOnlyAdjust() {
        let app = launch(canLog: true)
        let run = app.buttons["today-session-2026-09-16-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 15))
        run.tap()

        XCTAssertTrue(app.buttons["session-missed"].waitForExistence(timeout: 5), "a session to do offers Missed")
        XCTAssertTrue(app.buttons["session-move"].exists, "a session to do offers Move")
        XCTAssertFalse(app.buttons["session-adjust"].exists, "Adjust is for a session already logged")

        app.buttons["session-done-as-planned"].tap()

        XCTAssertTrue(app.buttons["session-adjust"].waitForExistence(timeout: 5), "a logged session keeps a way to fix a typo")
        XCTAssertFalse(app.buttons["session-missed"].exists, "Missed makes no sense on a logged session")
        XCTAssertFalse(app.buttons["session-move"].exists, "Move makes no sense on a logged session")
        XCTAssertFalse(app.buttons["session-done-as-planned"].exists)
    }

    /* 1. It opens on Today with today's session, and Settings carries the version. */
    func testOpensOnTodayAndSettingsShowsTheVersion() {
        let app = launch()

        let run = app.buttons["today-session-2026-09-16-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 15), "Today does not show the day's run")
        XCTAssertTrue(run.isHittable, "the day's run is not on screen")

        let title = app.staticTexts["settings-title"]
        XCTAssertFalse(title.exists && title.isHittable, "Settings is already on screen before its tab was tapped")
        app.buttons["tab-settings"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let shown = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: title)
        wait(for: [shown], timeout: 5)

        let whatsNew = app.buttons["settings-whats-new"]
        XCTAssertTrue(whatsNew.waitForExistence(timeout: 5))
        XCTAssertNotNil(whatsNew.label.range(of: #"AMS Workout Sync \d+\.\d+ \(\d+\)"#, options: .regularExpression),
                        "the version is missing from What's new: \(whatsNew.label)")
    }

    /* 3. The race's words are behind the flag on Progress, not on the screen. */
    func testTheRaceIsBehindTheFlag() {
        let app = launch()
        XCTAssertTrue(app.buttons["today-session-2026-09-16-run"].waitForExistence(timeout: 15))
        app.buttons["tab-progress"].tap()

        let flag = app.buttons["race-what"]
        XCTAssertTrue(flag.waitForExistence(timeout: 5), "Progress has no race flag")
        XCTAssertFalse(app.staticTexts["race-title"].exists, "the race description is on the screen before the flag was tapped")
        flag.tap()
        let title = app.staticTexts["race-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "the flag did not show what the race is")
        XCTAssertFalse(title.label.isEmpty)
        flag.tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2), "the race description did not go away again")
    }

    /* 2. A session's Z2 opens what Z2 is for him: one heart-rate row, from the zones sheet. */
    func testASessionsZoneOpensWhatItMeans() {
        let app = launch()

        let run = app.buttons["today-session-2026-09-16-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 15))
        run.tap()
        XCTAssertTrue(app.staticTexts["session-title"].waitForExistence(timeout: 5), "the session did not open")

        let pill = app.buttons["zone-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the session has no zone pill")
        pill.tap()
        XCTAssertTrue(app.staticTexts["zone-sheet-title"].waitForExistence(timeout: 5), "the zone sheet did not open")

        let rows = app.descendants(matching: .any).matching(identifier: "zone-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the zone sheet shows no rows")
        XCTAssertEqual(rows.count, 1, "a run at Z2 should show exactly the Z2 heart-rate row")
        let label = rows.firstMatch.label
        XCTAssertTrue(label.contains("Z2") && label.contains("122–134"), "wrong row: \(label)")
    }
}
