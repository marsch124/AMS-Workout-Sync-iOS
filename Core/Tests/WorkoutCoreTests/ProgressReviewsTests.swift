import XCTest
@testable import WorkoutCore

/* Round 28, Progress: month in review, steady weeks, bests, test history, report facts — with invented numbers. */
final class ProgressReviewsTests: XCTestCase {
    private let mapping = Mapping(sheets: ["S"], headerRow: 1, firstDataRow: 2, lastDataRow: 40, mode: "simple", sectionColumn: nil,
                                  columns: [:], units: Units(duration: "minutes", distance: "km", paceIsTime: false),
                                  doneValue: "Yes", missedValue: "Missed")

    private func session(_ day: String, _ sport: String = "run", planned: Double = 60, did: Double? = nil, km: Double? = nil,
                         rpe: Double? = nil, missed: Bool = false) -> Workout {
        var results: [String: ResultValue] = [:]
        if let did { results["actualDuration"] = ResultValue(text: "", number: did, date: nil) }
        if let km { results["actualDistance"] = ResultValue(text: "", number: km, date: nil) }
        if let rpe { results["rpe"] = ResultValue(text: "", number: rpe, date: nil) }
        let logged = did != nil || missed
        return Workout(key: day + sport, sheet: "S", row: 1, rows: [1], date: parseDayKey(day)!, dayKey: day, disciplineRaw: sport,
                       discipline: Discipline(id: sport, label: sport.capitalized, synonyms: []), title: "Invented", phase: "",
                       sections: [], planned: Planned(durationRaw: planned, distanceRaw: nil, intensity: "", description: ""),
                       results: results, loggedInSheet: logged, missed: missed, logged: logged)
    }

    /* Four weeks of two sessions each; the second week is half done. */
    private var plan: [Workout] {
        [session("2026-09-07", "run", did: 60), session("2026-09-09", "bike", planned: 120, did: 150, km: 60),
         session("2026-09-14", "run", did: 60), session("2026-09-16", "bike", planned: 120),
         session("2026-09-21", "run", did: 60), session("2026-09-23", "swim", did: 45, km: 2),
         session("2026-09-28", "run", did: 60), session("2026-09-30", "bike", planned: 120, did: 120, km: 50)]
    }

    func testMonthInReviewAgreesWithPlanFollowed() {
        var feel = FeelLog()
        feel.set(.good, on: "2026-09-08"); feel.set(.good, on: "2026-09-09"); feel.set(.tired, on: "2026-09-10")
        let f = MonthReview.facts(plan, mapping, month: "2026-09", today: "2026-10-02", feel: feel)
        XCTAssertEqual(MonthReview.months(plan, today: "2026-10-02"), ["2026-09"])
        XCTAssertEqual(f.sessionsPlanned, 8)
        XCTAssertEqual(f.sessionsDone, 7)
        XCTAssertEqual(f.followed, PlanOverview.followed(plan, from: "2026-09-01", to: "2026-09-30", today: "2026-10-02"))
        XCTAssertEqual(f.followed.percent, 88)
        XCTAssertEqual(f.longest?.seconds, 150 * 60)
        XCTAssertEqual(f.feelings.first { $0.feel == .good }?.count, 2)
        XCTAssertEqual(f.feelAnswered, 3)
        let line = MonthReview.closing(f) { $0 }
        XCTAssertFalse(line.contains("!"))
        XCTAssertTrue(line.hasPrefix("7 of 8 sessions done"))
    }

    func testSteadyWeeksUseTheThresholdAndTheCurrentWeekNeverBreaksTheRow() {
        XCTAssertEqual(SteadyWeeks.threshold, 90)
        // Today is Wednesday 30 Sep: weeks of 7, 21 and 28 Sep are followed, 14 Sep is not (one of two).
        let squares = SteadyWeeks.squares(plan, today: "2026-09-30", count: 4)
        XCTAssertEqual(squares.map(\.followed), [true, false, true, true])
        XCTAssertEqual(squares.last?.isNow, true)
        XCTAssertEqual(SteadyWeeks.row(plan, today: "2026-09-30"), 2)
        // Monday 5 Oct, nothing due this week yet: the row is the two finished weeks, not broken.
        XCTAssertEqual(SteadyWeeks.row(plan, today: "2026-10-05"), 2)
        XCTAssertEqual(SteadyWeeks.longest(plan, today: "2026-09-30")?.weeks, 2)
    }

    func testBestsOnlyFromLoggedSessionsAndTheBiggestWeek() {
        let bests = PersonalBests.all(plan + [session("2026-09-02", "run", did: 200, missed: true)], mapping, today: "2026-09-30")
        let ride = bests.first { $0.kind == .ride }
        XCTAssertEqual(ride?.seconds, 150 * 60)
        XCTAssertEqual(ride?.km, 60)
        XCTAssertEqual(bests.first { $0.kind == .run }?.seconds, 60 * 60)
        XCTAssertEqual(bests.first { $0.kind == .run }?.dayKey, "2026-09-07")   // a tie goes to the earliest
        XCTAssertEqual(bests.first { $0.kind == .swim }?.km, 2)
        XCTAssertEqual(bests.first { $0.kind == .week }?.dayKey, "2026-09-07")  // 60 + 150 minutes
        XCTAssertEqual(bests.first { $0.kind == .row }?.weeks, 2)
    }

    func testTestHistoryShowsEqualAsEqualAndNeverJudges() {
        let tests = [TestResult(name: "Test 1", dates: "14 Sep–16 Sep 2026", lthr: 160, ftp: 200, css: 110),
                     TestResult(name: "Test 2", dates: "02 Nov–04 Nov 2026", lthr: 160, ftp: 210, css: nil)]
        let s = TestHistory.series(tests)
        XCTAssertEqual(s.map(\.measure), [.pulse, .power, .swim])
        XCTAssertEqual(s[0].line, "Steady since Test 1")
        XCTAssertEqual(s[1].line, "Was 200 at Test 1")
        XCTAssertEqual(s[2].line, "First value, Test 1")
        XCTAssertEqual(s[0].dots.map(\.label), ["14 Sep", "02 Nov"])
        XCTAssertFalse(s.map(\.line).joined().lowercased().contains("improve"))
    }

    func testReportFactsClipWeeksToTheMonthAndListEverySession() {
        let weeks = MonthReport.weeks(plan, mapping, month: "2026-09")
        XCTAssertEqual(weeks.first?.start, "2026-09-01")
        XCTAssertEqual(weeks.last?.end, "2026-09-30")
        XCTAssertEqual(weeks.reduce(0) { $0 + $1.hours.planned }, PlanOverview.hours(plan, mapping, from: "2026-09-01", to: "2026-09-30").planned)
        let lines = MonthReport.lines(plan, mapping, month: "2026-09")
        XCTAssertEqual(lines.count, 8)
        XCTAssertEqual(lines.first { $0.key == "2026-09-16bike" }?.done, nil)
        XCTAssertEqual(MonthReport.feelDays(FeelLog(), month: "2026-09").count, 30)
    }
}
