import XCTest

/*
 * Round 30, race-plan lane: the race-day forecast, the age-group card and the
 * course pacing page, with invented sample data (AMSWS_RACE_PAGE + AMSWS_RACEPLAN_FAKE).
 * Found by identifier only.
 */
final class Raceplan30UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(open: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let plan = Bundle(for: Self.self).url(forResource: "plan", withExtension: "xlsx")!
        app.launchEnvironment["AMSWS_FILE"] = plan.path
        app.launchEnvironment["AMSWS_TODAY"] = "2026-09-16"
        app.launchEnvironment["AMSWS_RESET"] = "1"
        app.launchEnvironment["AMSWS_RACE_PAGE"] = "1"
        app.launchEnvironment["AMSWS_RACEPLAN_FAKE"] = "1"
        if let open { app.launchEnvironment["AMSWS_RACEPLAN_OPEN"] = open }
        app.launch()
        return app
    }

    func testTheForecastAndTheAgeGroupCardsShowARangePerPart() {
        let app = launch()
        XCTAssertTrue(any(app, "race-forecast").waitForExistence(timeout: 15), "no forecast card")
        XCTAssertTrue(any(app, "race-forecast-total").label.contains("\u{2013}"), "the total is not a range: \(any(app, "race-forecast-total").label)")
        for leg in ["swim", "t1", "bike", "t2", "run"] { XCTAssertTrue(any(app, "race-forecast-" + leg).exists, "no range for \(leg)") }
        XCTAssertTrue(any(app, "race-forecast-note").label.contains("Narrows as the race gets closer"))
        XCTAssertTrue(any(app, "race-forecast-trend").exists)
        XCTAssertTrue(any(app, "race-gap-bike").label.contains("age group"), "no bike line")
        XCTAssertTrue(any(app, "race-agegroup").exists)
        XCTAssertTrue(any(app, "race-pacing-open").exists)
    }

    func testTheAgeGroupPageHasCancelAndSave() {
        let app = launch(open: "agegroup")
        XCTAssertTrue(any(app, "race-agegroup-picker").waitForExistence(timeout: 15))
        XCTAssertTrue(any(app, "race-agegroup-cancel").exists)
        XCTAssertTrue(any(app, "race-agegroup-save").exists)
    }

    func testCoursePacingCutsTheBikeAndTheRunIntoSections() {
        let app = launch()
        XCTAssertTrue(any(app, "race-pacing-open").waitForExistence(timeout: 15))
        any(app, "race-pacing-open").tap()
        XCTAssertTrue(any(app, "race-pacing-page").waitForExistence(timeout: 10))
        XCTAssertTrue(any(app, "race-pacing-bike-0").exists, "no first bike section")
        XCTAssertTrue(any(app, "race-pacing-bike-1").label.contains("bpm"), "no pulse on a bike section")
        XCTAssertTrue(any(app, "race-pacing-run-0").exists, "no first run lap")
        XCTAssertTrue(any(app, "race-pacing-legend").exists)
    }
}
