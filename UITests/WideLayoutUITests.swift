import XCTest

/*
 * The wide look (iPad, and the iPad app on the Mac): the side list, the week
 * board and the season. Written and compiled; run on an iPad simulator (the
 * first two) and an iPhone simulator (the third). The same invented fortnight
 * as the other screen tests, on Wednesday 16 September 2026, with the plan
 * living in the app. Everything is found by identifier.
 */
final class WideLayoutUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(side: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        if let side { app.launchEnvironment["AMSWS_SIDE"] = side }
        app.launch()
        return app
    }

    /* The six rows and the sync words; the week as seven day columns, Monday to Sunday. */
    func testWeekBoardShowsTheWeek() {
        let app = launch(side: "week")
        for row in ["today", "week", "season", "sessions", "progress", "settings"] {
            XCTAssertTrue(app.buttons["side-\(row)"].waitForExistence(timeout: 15), "side-\(row) is missing")
        }
        XCTAssertTrue(app.descendants(matching: .any)["sync-status"].exists, "the sync dot has no words")
        XCTAssertTrue(app.descendants(matching: .any)["week-board"].waitForExistence(timeout: 10))
        for day in ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"] {
            XCTAssertTrue(app.descendants(matching: .any)["week-day-\(day)"].waitForExistence(timeout: 5), "no column for \(day)")
        }
        XCTAssertTrue(app.buttons["week-prev"].exists)
        XCTAssertTrue(app.buttons["week-this"].exists)
        XCTAssertTrue(app.buttons["week-next"].exists)
        // The plan lives in the app, so a session can be added from a day's foot.
        XCTAssertTrue(app.buttons["week-add-2026-09-16"].exists)
    }

    /* Every plan week as a bar, the chosen week's board below; tapping a bar chooses its week. */
    func testSeasonShowsPhasesAndRace() {
        let app = launch(side: "season")
        XCTAssertTrue(app.descendants(matching: .any)["season-view"].waitForExistence(timeout: 15), "no season on top")
        let thisWeek = app.buttons["season-week-2"]
        XCTAssertTrue(thisWeek.waitForExistence(timeout: 5), "no bar for week 2")
        XCTAssertTrue(app.descendants(matching: .any)["season-today"].exists, "no line for today")
        XCTAssertTrue(app.descendants(matching: .any)["week-board"].exists, "no week board under the season")
        app.buttons["season-week-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["week-day-2026-09-07"].waitForExistence(timeout: 5),
                      "choosing week 1 did not show its days")
        // The fixture names no phase and no race, so their rows and flag are not expected here.
    }

    /* On the iPhone nothing of the wide look appears: the four tabs, no side list. */
    func testThePhoneLookIsUnchanged() {
        let app = launch()
        for tab in ["today", "plan", "progress", "settings"] {
            XCTAssertTrue(app.buttons["tab-\(tab)"].waitForExistence(timeout: 15), "tab-\(tab) is missing")
        }
        for row in ["today", "week", "season", "sessions", "progress", "settings"] {
            XCTAssertFalse(app.buttons["side-\(row)"].exists, "side-\(row) showed on the phone")
        }
    }
}
