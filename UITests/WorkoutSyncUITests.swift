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
    private func launch(canLog: Bool = false, garmin: Bool = false, extraForm: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        if canLog { app.launchEnvironment["AMSWS_SHOW_BUTTONS"] = "1" }
        // Pretend Health: a ride, a walk, and his pool swim of 21 September —
        // 46.5 minutes in all, 1,275 m, of which 24.7 minutes swimming.
        if garmin { app.launchEnvironment["AMSWS_FAKE_HEALTH"] = "1" }
        // "1" opens the extra form on today; a day key opens it on that day.
        if let extraForm { app.launchEnvironment["AMSWS_EXTRAFORM"] = extraForm }
        app.launch()
        return app
    }

    /* 13. Settings says what Health hands over for today and for yesterday,
           behind a toggle — so a silent refusal is visible. */
    func testSettingsSaysWhatHealthHandsOver() {
        let app = launch(garmin: true)
        XCTAssertTrue(app.buttons["tab-settings"].waitForExistence(timeout: 15))
        app.buttons["tab-settings"].tap()

        let toggle = app.buttons["health-what"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settings has no way to see what Health hands over")
        let today = app.descendants(matching: .any).matching(identifier: "health-today-row")
        XCTAssertEqual(today.count, 0, "the lists are behind the toggle until it is tapped")
        toggle.tap()

        XCTAssertTrue(today.firstMatch.waitForExistence(timeout: 10), "today is not listed")
        XCTAssertEqual(today.count, 3, "all of today's workouts belong in the list")
        let yesterday = app.descendants(matching: .any).matching(identifier: "health-yesterday-row")
        XCTAssertEqual(yesterday.count, 3, "yesterday has a heading and a list of its own")
        XCTAssertTrue(app.staticTexts["health-probe"].exists,
                      "pressing Ask again must leave something on screen that says Health answered")
    }

    /* 12. A session offers the day's workouts even when Health filed them
           under another sport — his run of 29 September was in Health and the
           form said there was none. */
    func testTheFormOffersWorkoutsOfAnotherSport() {
        let app = launch(canLog: true, garmin: true)
        // The strength session of 13 September: behind him, and none of the
        // day's Health workouts is a strength session.
        let strength = app.buttons["today-session-2026-09-13-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 15), "the strength session behind today is not on Today")
        strength.tap()
        let details = app.buttons["session-log-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        XCTAssertTrue(app.buttons["health-use-bike"].waitForExistence(timeout: 5),
                      "the day's other workouts are not offered, so a mis-filed one cannot be used")
    }

    /* 11. With Apple Health off, the form says so and offers to put it back on. */
    func testTheFormSaysWhenAppleHealthIsOff() {
        let app = launch(canLog: true, extraForm: "1")
        let turnOn = app.buttons["health-turn-on"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 15),
                      "with Health off the form says nothing about it, and the missing suggestions look like a fault")
    }

    /* 10. Save is never a dead grey button: pressed early it says what is missing. */
    func testTheExtraFormNeverGoesDead() {
        let app = launch(canLog: true, extraForm: "1")
        let save = app.buttons["extra-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        XCTAssertTrue(save.isEnabled, "the main button must never be grey")
        save.tap()
        XCTAssertTrue(app.staticTexts["extra-problem"].waitForExistence(timeout: 3),
                      "pressed with nothing typed, Save must say what it wants")
        XCTAssertTrue(app.textFields["extra-field-duration"].exists, "the form closed without saving anything")
    }

    /* 9. An extra done yesterday, marked as counting, is in the week's blocks today. */
    func testAnExtraDoneYesterdayCountsInThisWeek() {
        let app = launch(canLog: true, extraForm: "2026-09-15")
        let minutes = app.textFields["extra-field-duration"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 15))
        // Rowing, so this row cannot be confused with the fixture's walk of the same day.
        app.buttons["extra-activity"].tap()
        let rowing = app.buttons["extra-activity-rowing"]
        XCTAssertTrue(rowing.waitForExistence(timeout: 5), "Rowing is not among the activities")
        rowing.tap()
        minutes.tap()
        minutes.typeText("40")
        app.buttons["extra-counts-yes"].tap()
        app.buttons["extra-save"].tap()

        let blocks = app.otherElements["week-extra-blocks"]
        XCTAssertTrue(blocks.waitForExistence(timeout: 5), "yesterday's extra is not under this week's bar")
        XCTAssertTrue(blocks.label.contains("40m"), "the week does not count it: \(blocks.label)")

        app.buttons["tab-plan"].tap()
        app.buttons["sessions-filter-done"].tap()
        XCTAssertTrue(app.buttons["sessions-extra-2026-09-15-rowing"].waitForExistence(timeout: 5),
                      "the extra was not kept on the day it was done")
    }

    /* 8. The four lists stay under the thumb: the filter row does not scroll away. */
    func testTheSessionsFiltersStayWhileScrolling() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab-plan"].waitForExistence(timeout: 15))
        app.buttons["tab-plan"].tap()

        let all = app.buttons["sessions-filter-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()

        let title = app.staticTexts["sessions-title"]
        let done = app.buttons["sessions-filter-done"]
        XCTAssertTrue(done.isHittable, "the filter row is not on screen to begin with")
        let list = app.scrollViews.firstMatch
        for _ in 0..<4 { list.swipeUp(velocity: .fast) }

        XCTAssertFalse(title.isHittable, "the list did not scroll at all")
        XCTAssertTrue(done.isHittable, "the filter buttons scrolled away with the list")
    }

    /* 7. An extra listed under Sessions → Done carries the done tick, as a done session does. */
    func testExtrasUnderDoneCarryTheTick() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab-plan"].waitForExistence(timeout: 15))
        app.buttons["tab-plan"].tap()
        let done = app.buttons["sessions-filter-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let walk = app.buttons["sessions-extra-2026-09-15-walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5), "the extra walk of 15 September is not under Done")
        XCTAssertTrue(walk.label.contains("Done"), "the extra carries no done tick: \(walk.label)")
    }

    /* 6. An extra's form offers what Garmin sent to Apple Health, as a session's does. */
    func testExtraFormOffersGarminFromHealth() {
        let app = launch(canLog: true, garmin: true, extraForm: "1")
        let use = app.buttons["health-use-walk"]
        XCTAssertTrue(use.waitForExistence(timeout: 15), "the extra's form does not offer the walk from Health")
        let minutes = app.textFields["extra-field-duration"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        use.tap()
        XCTAssertEqual(minutes.value as? String, "35", "Use should fill the walk's 35 minutes")
    }

    /* 5. The app never works out a pace: Use fills time, distance and heart rate, and the pace stays his. */
    func testUseFromGarminLeavesThePaceAlone() {
        let app = launch(canLog: true, garmin: true)
        let swim = app.buttons["today-session-2026-09-14-swim"]
        XCTAssertTrue(swim.waitForExistence(timeout: 15), "the swim behind today is not on Today")
        swim.tap()
        let details = app.buttons["session-log-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        let pace = app.textFields["field-avgPace"]
        let duration = app.textFields["field-actualDuration"]
        XCTAssertTrue(pace.waitForExistence(timeout: 5), "the swim form has no pace box")
        let paceBefore = pace.value as? String
        let durationBefore = duration.value as? String

        let use = app.buttons["health-use-swim"]
        XCTAssertTrue(use.waitForExistence(timeout: 5), "the form does not offer the pool swim from Health")
        use.tap()

        XCTAssertNotEqual(duration.value as? String, durationBefore, "Use should fill the time")
        XCTAssertEqual(duration.value as? String, "47")
        XCTAssertEqual(pace.value as? String, paceBefore, "the pace must be left for him — never 3:39, never any sum")
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
