import XCTest

/*
 * Round 30, lane planmaker: the plan maker (pick 1) and My week shape (pick 5),
 * on the invented plan. Found by identifier only. No network: AMSWS_FAKE_CLAUDE.
 * Written and compiled; not run by the helper that wrote it.
 */
final class PlanMaker30UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String: String], today: String = "2026-09-16") -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_HOME"] = "app"
        app.launchEnvironment["AMSWS_TODAY"] = today
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_FAKE_CLAUDE"] = "1"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /* From the Sessions page: the plan maker's form, then a draft beside his plan, then one week of it. */
    func testMakingADraftFromThePlanPage() {
        let app = launch([:])
        let tab = app.buttons["tab-plan"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        let open = any(app, "plan-maker-open")
        XCTAssertTrue(open.waitForExistence(timeout: 5), "no Make a new plan button")
        open.tap()
        XCTAssertTrue(any(app, "pm-form").waitForExistence(timeout: 5), "the plan maker did not open")
        XCTAssertTrue(any(app, "pm-race-name").exists)
        XCTAssertTrue(any(app, "pm-distance-half").exists)
        XCTAssertTrue(any(app, "pm-cancel").exists && any(app, "pm-save").exists)
        let make = any(app, "pm-make")
        XCTAssertTrue(make.exists)
        make.tap()
        XCTAssertTrue(any(app, "pm-draft-head").waitForExistence(timeout: 10), "no draft after Make the draft")
        XCTAssertTrue(any(app, "pm-draft-title").exists)
        XCTAssertTrue(any(app, "pm-season").exists)
        XCTAssertTrue(any(app, "pm-tile-weeks").exists)
        let week = any(app, "pm-week-1")
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        XCTAssertTrue(any(app, "pm-week-page").waitForExistence(timeout: 5), "a week did not open")
        XCTAssertTrue(any(app, "pm-week-session").exists)
    }

    /* Claude's look on an invented draft: three lines, its picks, and the two answers. */
    func testClaudesLookShowsThreeLinesAndItsPicks() {
        let app = launch(["AMSWS_PLANMAKER": "claude"])
        XCTAssertTrue(any(app, "pm-claude-card").waitForExistence(timeout: 15))
        for n in 1...3 { XCTAssertTrue(any(app, "pm-claude-line-\(n)").exists, "line \(n) missing") }
        XCTAssertTrue(any(app, "pm-claude-use").exists)
        XCTAssertTrue(any(app, "pm-claude-keep").exists)
        XCTAssertTrue(any(app, "pm-switch-open").exists)
        XCTAssertTrue(any(app, "pm-delete").exists)
    }

    /* Switching: the page says what happens, switches in one tap and offers the one Undo. */
    func testSwitchingSaysWhatHappensAndOffersOneUndo() {
        let app = launch(["AMSWS_PLANMAKER": "switch"])
        XCTAssertTrue(any(app, "pm-switch-page").waitForExistence(timeout: 15))
        XCTAssertTrue(any(app, "pm-switch-words").exists, "the page does not say what happens")
        XCTAssertTrue(any(app, "pm-switch-day").exists)
        let go = any(app, "pm-switch-go")
        XCTAssertTrue(go.exists)
        go.tap()
        XCTAssertTrue(any(app, "pm-switch-done").waitForExistence(timeout: 10), "no word that the plan switched")
        XCTAssertTrue(any(app, "pm-switch-undo").exists)
        XCTAssertFalse(go.exists, "the button stayed after the switch")
        XCTAssertEqual(app.buttons["pm-switch-cancel"].label, "Done")
    }

    /* My week shape: Cancel and Save; a change can be saved, then the coming weeks can be laid out. */
    func testWeekShapeSavesAndOffersTheLayOut() {
        let app = launch(["AMSWS_WEEKSHAPE": "1"])
        XCTAssertTrue(any(app, "ws-page").waitForExistence(timeout: 15))
        XCTAssertTrue(any(app, "ws-cancel").exists)
        XCTAssertTrue(any(app, "ws-long-ride").exists && any(app, "ws-rest").exists)
        let chip = any(app, "ws-chip-0-strength")
        XCTAssertTrue(chip.exists)
        chip.tap()
        let save = app.buttons["ws-save"]
        XCTAssertTrue(save.isEnabled, "a change cannot be saved")
        save.tap()
        XCTAssertTrue(any(app, "ws-layout-open").waitForExistence(timeout: 5), "no Lay out button after Save")
    }

    /* The lay-out preview: what moves, Take it, and the one Undo. */
    func testTheLayOutShowsWhatMovesAndTakesItInOneTap() {
        let app = launch(["AMSWS_WEEKSHAPE": "layout"], today: "2026-09-08")
        XCTAssertTrue(any(app, "lo-page").waitForExistence(timeout: 15))
        XCTAssertTrue(any(app, "lo-count").exists)
        let take = any(app, "lo-take")
        guard take.waitForExistence(timeout: 5) else {
            XCTAssertTrue(any(app, "lo-nothing").exists, "neither moves nor a word why there are none")
            return
        }
        XCTAssertTrue(any(app, "lo-week-1").exists, "no week is spelled out")
        XCTAssertTrue(any(app, "lo-keep").exists)
        take.tap()
        XCTAssertTrue(any(app, "lo-done").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "lo-undo").exists)
    }
}
