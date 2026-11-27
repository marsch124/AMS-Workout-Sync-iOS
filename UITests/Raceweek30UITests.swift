import XCTest

/* Round 30, lane raceweek: the tune-up page, race week and the race report, with invented data. Found by identifier only. Written, not run here. */
final class Raceweek30UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ switches: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        for s in switches { app.launchEnvironment[s] = "1" }
        app.launch()
        return app
    }

    func testTheTuneUpPageHasCancelAndSave() {
        let app = launch(["AMSWS_TUNEUP_EDIT"])
        XCTAssertTrue(any(app, "tuneup-name").waitForExistence(timeout: 15))
        for id in ["tuneup-date", "tuneup-size", "tuneup-place", "tuneup-start", "tuneup-cancel", "tuneup-save"] {
            XCTAssertTrue(any(app, id).exists, "missing \(id)")
        }
    }

    func testTheRoomCardOffersTakeItAndKeepMyPlanOrOneGreyLine() {
        let app = launch(["AMSWS_TUNEUP_ROOM"])
        XCTAssertTrue(any(app, "tuneup-tile-" + "2026-10-11").waitForExistence(timeout: 15))
        let card = any(app, "tuneup-room-card"), grey = any(app, "tuneup-room-grey")
        XCTAssertTrue(card.waitForExistence(timeout: 5) || grey.exists, "neither the card nor the grey line")
        if card.exists {
            XCTAssertTrue(any(app, "tuneup-room-take").exists)
            XCTAssertTrue(any(app, "tuneup-room-keep").exists)
            any(app, "tuneup-room-take").tap()
            XCTAssertTrue(any(app, "tuneup-room-undo").waitForExistence(timeout: 5))
        }
    }

    func testRaceWeekShowsDaysTicksAndTheMorningTimeline() {
        let app = launch(["AMSWS_RACEWEEK"])
        XCTAssertTrue(any(app, "raceweek-page").waitForExistence(timeout: 15))
        XCTAssertTrue(any(app, "raceweek-day-1").exists)
        XCTAssertEqual(any(app, "raceweek-item-d7-bike-check").value as? String, "done")
        let tick = any(app, "raceweek-item-d1-rack")
        tick.tap()
        XCTAssertEqual(tick.value as? String, "done")
        XCTAssertTrue(any(app, "raceweek-morning-04:30").exists, "wake-up is 3 hours before a 07:30 start")
        XCTAssertTrue(any(app, "raceweek-kit").exists)
    }

    func testRaceWeekCardAlone() {
        let app = launch(["AMSWS_RACEWEEK_CARD"])
        XCTAssertTrue(any(app, "raceweek-card").waitForExistence(timeout: 15))
    }

    func testTheRaceReportShowsEveryLegAndWhatToKeep() {
        let app = launch(["AMSWS_RACE_REPORT"])
        XCTAssertTrue(any(app, "race-report-page").waitForExistence(timeout: 15))
        for leg in ["swim", "t1", "bike", "t2", "run"] { XCTAssertTrue(any(app, "race-report-leg-" + leg).exists, "no tile for \(leg)") }
        XCTAssertTrue(any(app, "race-report-keep").exists)
        XCTAssertTrue(any(app, "race-report-share").exists)
    }
}
