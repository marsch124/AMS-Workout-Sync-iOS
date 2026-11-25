import XCTest

/*
 * The wide look (iPad, and the iPad app on the Mac): the side list and the
 * Plan page — the season on top, the switch Week · Month · Year, the numbers. Written and compiled; run on an iPad simulator (the
 * first two) and an iPhone simulator (the third). The same invented fortnight
 * as the other screen tests, on Wednesday 16 September 2026, with the plan
 * living in the app. Everything is found by identifier.
 */
final class WideLayoutUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(side: String? = nil, planView: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        if let side { app.launchEnvironment["AMSWS_SIDE"] = side }
        if let planView { app.launchEnvironment["AMSWS_PLAN"] = planView }
        app.launch()
        return app
    }

    /* The five rows and the sync words; the Plan page's week as seven day columns, Monday to Sunday. */
    func testPlanWeekShowsTheWeek() {
        let app = launch(side: "plan", planView: "week")
        for row in ["today", "plan", "sessions", "progress", "settings"] {
            XCTAssertTrue(app.buttons["side-\(row)"].waitForExistence(timeout: 15), "side-\(row) is missing")
        }
        XCTAssertFalse(app.buttons["side-week"].exists, "Week is no longer a row of its own")
        XCTAssertTrue(app.descendants(matching: .any)["sync-status"].exists, "the sync dot has no words")
        XCTAssertTrue(app.descendants(matching: .any)["plan-switch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["season-view"].exists, "no season on top")
        XCTAssertTrue(app.descendants(matching: .any)["week-board"].waitForExistence(timeout: 10))
        for day in ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"] {
            XCTAssertTrue(app.descendants(matching: .any)["week-day-\(day)"].waitForExistence(timeout: 5), "no column for \(day)")
        }
        XCTAssertTrue(app.buttons["week-prev"].exists)
        XCTAssertTrue(app.buttons["week-this"].exists)
        XCTAssertTrue(app.buttons["week-next"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["plan-numbers"].exists, "no numbers beside or under the plan")
        // The plan lives in the app, so a session can be added from a day's foot.
        XCTAssertTrue(app.buttons["week-add-2026-09-16"].exists)
    }

    /* The month as a calendar; the switch moves between the three views; a bar chooses its week. */
    func testPlanMonthYearAndTheSeasonBars() {
        let app = launch(side: "plan", planView: "month")
        XCTAssertTrue(app.descendants(matching: .any)["month-grid"].waitForExistence(timeout: 15), "no month grid")
        XCTAssertTrue(app.descendants(matching: .any)["month-day-2026-09-16"].exists, "no cell for today")
        XCTAssertTrue(app.buttons["month-prev"].exists)
        XCTAssertTrue(app.buttons["month-this"].exists)
        XCTAssertTrue(app.buttons["month-next"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["season-today"].exists, "no line for today")

        app.buttons["plan-switch-year"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["year-view"].waitForExistence(timeout: 5), "no year view")
        let september = app.buttons["year-month-2026-09"]
        XCTAssertTrue(september.waitForExistence(timeout: 5), "no block for September")
        september.tap()
        XCTAssertTrue(app.descendants(matching: .any)["month-grid"].waitForExistence(timeout: 5), "a month block did not open its month")

        app.buttons["season-week-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["week-day-2026-09-07"].waitForExistence(timeout: 5),
                      "choosing week 1 did not show its days")
        // The fixture names no phase and no race, so their rows and flag are not expected here.
    }

    /* On a wide window (an iPad on its side) Progress stands in two columns. */
    func testProgressStandsInTwoColumns() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(side: "progress")
        XCTAssertTrue(app.descendants(matching: .any)["progress-two-columns"].waitForExistence(timeout: 15),
                      "Progress is not in two columns on a wide window")
    }

    /* On the iPhone nothing of the wide look appears: the four tabs, no side list. */
    func testThePhoneLookIsUnchanged() {
        let app = launch()
        for tab in ["today", "plan", "progress", "settings"] {
            XCTAssertTrue(app.buttons["tab-\(tab)"].waitForExistence(timeout: 15), "tab-\(tab) is missing")
        }
        for row in ["today", "plan", "sessions", "progress", "settings"] {
            XCTAssertFalse(app.buttons["side-\(row)"].exists, "side-\(row) showed on the phone")
        }
    }
}
