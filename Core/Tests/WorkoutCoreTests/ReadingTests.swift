import XCTest
@testable import WorkoutCore

/*
 * The reading and writing logic on its own — no simulator, no workbook, no
 * network. Every one of these is a thing the app gets wrong silently if it
 * breaks: a duration typed his way, a week that starts on the right Monday,
 * a number written the way the sheet writes it.
 */
final class ReadingTests: XCTestCase {

    // MARK: what he types

    func testDurationsHeWouldType() {
        XCTAssertEqual(parseDuration("35"), 35 * 60)          // a bare number is minutes
        XCTAssertEqual(parseDuration("1:15"), 75 * 60)
        XCTAssertEqual(parseDuration("1h20"), 80 * 60)
        XCTAssertEqual(parseDuration("90min"), 90 * 60)
        XCTAssertEqual(parseDuration("2h30min"), 150 * 60)
        XCTAssertEqual(parseDuration("45,5"), 45.5 * 60)      // a decimal comma is Swedish
        XCTAssertEqual(parseDuration(" 40 "), 40 * 60)
    }

    func testDurationsThatAreNotDurations() {
        XCTAssertNil(parseDuration(""))
        XCTAssertNil(parseDuration(nil))
        XCTAssertNil(parseDuration("   "))
        XCTAssertNil(parseDuration("easy"))
    }

    func testDurationsAreWrittenBackAsTheSheetWritesThem() {
        XCTAssertEqual(formatDuration(35 * 60), "35m")
        XCTAssertEqual(formatDuration(90 * 60), "1h 30m")
        XCTAssertEqual(formatDuration(0), "0s")
        XCTAssertEqual(formatDuration(nil), "")
    }

    func testNumbersAreWrittenAsExcelWouldWriteThem() {
        XCTAssertEqual(jsNumberString(5), "5")
        XCTAssertEqual(jsNumberString(5.4), "5.4")
        XCTAssertEqual(jsNumberString(1.025), "1.025")
        XCTAssertEqual(jsNumberString(0), "0")
    }

    // MARK: the week

    func testTheWeekStartsOnMonday() {
        XCTAssertEqual(PlanView.weekStart("2026-09-30"), "2026-09-28")   // a Wednesday
        XCTAssertEqual(PlanView.weekStart("2026-09-28"), "2026-09-28")   // the Monday itself
        XCTAssertEqual(PlanView.weekStart("2026-10-04"), "2026-09-28")   // the Sunday after
    }

    func testTheWeekStartsRightAcrossAMonthAndAYear() {
        XCTAssertEqual(PlanView.weekStart("2027-01-01"), "2026-12-28")
        XCTAssertEqual(PlanView.weekStart("2026-03-01"), "2026-02-23")
    }

    func testDaysAreCountedAcrossMonthEnds() {
        XCTAssertEqual(PlanView.addDays("2026-09-30", 1), "2026-10-01")
        XCTAssertEqual(PlanView.addDays("2026-01-01", -1), "2025-12-31")
        XCTAssertEqual(PlanView.addDays("2028-02-28", 1), "2028-02-29")   // a leap year
    }

    func testADayKeyThatIsNotOneIsRefused() {
        XCTAssertNil(parseDayKey(""))
        XCTAssertNil(parseDayKey(nil))
        XCTAssertNil(parseDayKey("2026-13-01"))      // a thirteenth month is not next January
        XCTAssertNil(parseDayKey("2026-02-31"))      // nor is the 31st of February the 3rd of March
        XCTAssertNil(parseDayKey("2026-00-10"))
        XCTAssertNil(parseDayKey("2026-9-30"))       // the sheet writes two digits
        XCTAssertNotNil(parseDayKey("2026-09-30"))
    }

    // MARK: only what changed is written

    func testOnlyAnAlteredBoxIsWritten() {
        let opened = ["actualDuration": "35", "avgHr": "122", "notes": ""]
        XCTAssertTrue(LogForm.changedOnly(opened, openedWith: opened).isEmpty)

        var typed = opened
        typed["avgHr"] = "126"
        XCTAssertEqual(LogForm.changedOnly(typed, openedWith: opened), ["avgHr": "126"])
    }

    func testEmptyingABoxIsAChange() {
        let opened = ["avgHr": "122"]
        let emptied = ["avgHr": ""]
        XCTAssertEqual(LogForm.changedOnly(emptied, openedWith: opened), ["avgHr": ""])
    }

    // MARK: extras

    func testAnExtraKnowsWhetherItCountsByItsKind() {
        XCTAssertEqual(Extras.activity("rowing").kind, "training")
        XCTAssertEqual(Extras.activity("walk").kind, "everyday")
        XCTAssertEqual(Extras.activity("meditation").kind, "restorative")
    }

    func testAnUnknownActivityDoesNotLoseItsRow() {
        // An extra logged under an activity later removed still has to render.
        XCTAssertEqual(Extras.activity("kitesurfing").id, "other")
    }

    func testEveryActivityHasItsOwnMark() {
        let icons = Extras.defaultActivities.map(\.icon)
        XCTAssertEqual(icons.count, Set(icons).count + duplicatesAllowed,
                       "two activities share an icon that were not meant to: \(icons)")
    }
    /* Swim, bike, run and strength deliberately wear the plan's own sport icons,
       and no two others may share. */
    private var duplicatesAllowed: Int { 0 }

    // MARK: the patterns the reader is built on

    func testEveryPatternInTheReaderCompiles() {
        // Xlsx.swift builds its regexes with try!, which is only safe while
        // every pattern in the package is valid. Reading a workbook exercises
        // them; this says so out loud.
        XCTAssertNotNil(parseDayKey("2026-09-30"))
        XCTAssertNotNil(parseDuration("1:15"))
        XCTAssertEqual(normalise("  Weekly  Schedules "), "weekly schedules")
    }
}
