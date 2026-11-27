import XCTest
@testable import WorkoutCore

/* Round 30, lane raceweek: the room for a tune-up, race week, the race morning and the race report. All numbers invented. */
final class Raceweek30Tests: XCTestCase {

    private func book(extraWeek: String = "") throws -> PlanBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        var b = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        b.weeks = (1...3).map { n in PlanWeek(number: n, monday: PlanView.addDays("2030-01-07", 7 * (n - 1)), phase: "Build", tag: n == 1 ? extraWeek : "") }
        func add(_ day: String, _ sport: String, _ title: String, _ m: Double, _ intensity: String) throws {
            try b.add(SessionDraft(dayKey: day, sport: sport, title: title, minutes: m, intensity: intensity, purpose: "Invented", isKey: true))
        }
        try add("2030-01-10", "run", "Tempo run", 60, "Hard")     // Thu
        try add("2030-01-11", "bike", "Long ride", 90, "RPE 7")  // Fri
        try add("2030-01-12", "swim", "Swim set", 45, "RPE 6")   // Sat
        try add("2030-01-14", "run", "Hill run", 60, "Hard")     // Mon
        try add("2030-01-15", "bike", "Bike", 120, "RPE 7")      // Tue
        b.changes = []
        return b
    }

    private func room(_ b: PlanBook, _ day: String = "2030-01-13", main: String? = "2030-07-14", today: String = "2030-01-01") -> TuneUpRoom.Change {
        TuneUpRoom.plan(TuneUp(id: "t", day: day), sessions: b.sessions, weeks: b.weeks, mainRaceDay: main, mapping: b.mapping, today: today)
    }

    func testRoomMakesThuFriShorterSatRestMonTueEasyAndOneUndoTakesItBack() throws {
        var b = try book()
        let c = room(b)
        XCTAssertEqual(c.headline, "Make room for the tune-up: Thu and Fri shorter and easy, Sat rest, Mon and Tue easy")
        XCTAssertEqual(c.edits.count, 4)
        XCTAssertEqual(c.removals.count, 1)
        let thu = try XCTUnwrap(c.edits.first { $0.day == "2030-01-10" })
        XCTAssertEqual(thu.draft.minutes, 35)           // 60 -> 36 -> 35
        XCTAssertEqual(thu.draft.intensity, "Easy")
        let tue = try XCTUnwrap(c.edits.first { $0.day == "2030-01-15" })
        XCTAssertEqual(tue.draft.minutes, 60)           // at most 60
        let before = b.sessions.map(\.key).sorted()
        let ids = try TuneUpRoom.apply(c, to: &b, why: TuneUpRoom.why(batch: "b1"))
        XCTAssertEqual(ids.count, 5)
        XCTAssertFalse(b.sessions.contains { $0.dayKey == "2030-01-12" })
        XCTAssertEqual(try TuneUpRoom.undo(batch: "b1", in: &b), 5)
        XCTAssertEqual(b.sessions.map(\.key).sorted(), before)
        XCTAssertEqual(b.draft(of: thu.key)?.minutes, 60)
    }

    func testRoomNeverTouchesDoneTestsTheRaceOrDaysGone() throws {
        var b = try book()
        let fri = try XCTUnwrap(b.sessions.first { $0.dayKey == "2030-01-11" })
        b.sessions[b.sessions.firstIndex { $0.key == fri.key }!].results["done"] = ResultValue(text: "\u{2713}", number: nil, date: nil)
        let c = room(b, today: "2030-01-10")     // Thursday is today: gone
        XCTAssertFalse(c.edits.contains { $0.key == fri.key || $0.day <= "2030-01-10" })
        XCTAssertFalse(c.headline.contains("Thu"))
        // A test week: nothing changes, one grey line.
        let t = try book(extraWeek: "TEST WEEK")
        let g = room(t)
        XCTAssertTrue(g.isEmpty); XCTAssertEqual(g.grey, TuneUpRoom.testWeekWords)
    }

    func testRoomRefusesInsideThreeWeeksOfTheMainRaceAndAfterNothingToChange() throws {
        let b = try book()
        let near = room(b, main: "2030-02-02")   // 20 days later
        XCTAssertTrue(near.isEmpty); XCTAssertEqual(near.grey, TuneUpRoom.tooCloseWords)
        XCTAssertFalse(room(b, main: "2030-02-03").isEmpty)  // 21 days: fine
        let far = room(b, "2030-03-03")     // a Sunday with nothing around it
        XCTAssertEqual(far.grey, TuneUpRoom.nothingWords)
    }

    func testRaceWeekListsAreShorterForShortRaces() {
        let full = RaceWeek.allItems(raceDay: "2030-07-14", size: .half)
        let short = RaceWeek.allItems(raceDay: "2030-07-14", size: .sprint)
        XCTAssertGreaterThan(full.count, short.count)
        XCTAssertEqual(Set(full.map(\.id)).count, full.count)
        XCTAssertEqual(RaceWeek.days(raceDay: "2030-07-14", size: .half).last?.day, "2030-07-13")
        XCTAssertEqual(RaceWeek.cardWords(days: 5), "Race week \u{00B7} 5 days to go")
        XCTAssertTrue(RaceWeek.isOn(days: 7)); XCTAssertFalse(RaceWeek.isOn(days: 8)); XCTAssertFalse(RaceWeek.isOn(days: -1))
        XCTAssertEqual(RaceWeek.tickedCount(["d1-rack", "nonsense"], raceDay: "2030-07-14", size: .half), 1)
    }

    func testRaceMorningIsWorkedBackFromTheStart() {
        let m = RaceWeek.morning(start: "07:30")
        XCTAssertEqual(m.map(\.clock), ["04:30", "04:45", "05:30", "05:45", "07:05", "07:30"])
        XCTAssertEqual(m.first?.text, "Wake up")
        XCTAssertEqual(RaceWeek.morning(start: "rubbish").last?.clock, "08:00")
        XCTAssertEqual(RaceWeek.morning(start: "01:00").first?.clock, "22:00")
    }

    func testReportComparesLegsToThePlanAndWritesPlainLines() {
        let r = RaceReport(day: "2030-07-14", legs: [
            RaceLegResult(leg: .swim, seconds: 2500, metres: 1900, speedMps: 0.76, avgHr: 130),
            RaceLegResult(leg: .t1, seconds: 250),
            RaceLegResult(leg: .bike, seconds: 10_920, metres: 90_000, speedMps: 8.2, avgHr: 138),
            RaceLegResult(leg: .t2, seconds: 140),
            RaceLegResult(leg: .run, seconds: 8_100, metres: 21_100, speedMps: 2.6, avgHr: 150)])
        let plan = RacePacing(swim: 2400, t1: 270, bike: 10_800, t2: 150, run: 7_500)
        let rows = r.rows(plan: plan)
        XCTAssertEqual(rows.map(\.leg), RaceLeg.allCases)
        XCTAssertEqual(RaceReport.line(rows[2]), "Bike 3h\u{00A0}02m \u{00B7} planned 3h\u{00A0}00m")
        XCTAssertEqual(rows[2].difference, 120)
        XCTAssertEqual(rows[4].fillFraction, 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(rows[4].plannedFraction), 7500.0 / 8100, accuracy: 0.001)
        let keep = r.keep(plan: plan)
        XCTAssertEqual(keep.count, 3)
        XCTAssertTrue(keep[0].contains("bike"), keep[0])
        XCTAssertTrue(keep[1].contains("run") && keep[1].contains("8 % over"), keep[1])
        XCTAssertTrue(keep[2].hasPrefix("The changeovers: T1 4m"))
        XCTAssertEqual(RaceReport.speedWords(.bike, mps: 8.2), "29.5 km/h")
        XCTAssertEqual(RaceReport.speedWords(.run, mps: 2.5), "6:40 /km")
        // No plan typed: the line is the time alone, and the lines say how to get a comparison.
        XCTAssertEqual(RaceReport(day: "d", legs: [RaceLegResult(leg: .bike, seconds: 3600)]).keep(plan: RacePacing()),
                       ["Type your times on the race page to see each leg against your plan."])
    }

    func testGarminMultisportLegsFromTheParentAndItsChildren() {
        let parent: [String: Any] = ["metadataDTO": ["childIds": [11, 12, 13, 14, 15]]]
        XCTAssertEqual(GarminMultisport.childIds(parent: parent), [11, 12, 13, 14, 15])
        func child(_ type: String, _ start: String, _ secs: Double) -> GarminMultisport.Child {
            GarminMultisport.child(detail: ["activityTypeDTO": ["typeKey": type],
                                            "summaryDTO": ["startTimeGMT": start, "duration": secs, "distance": 1000.0, "averageSpeed": 2.0, "averageHR": 120.0]])!
        }
        let kids = [child("running", "2030-07-14T09:00:00.0", 3000), child("transition_v2", "2030-07-14T07:30:00.0", 200),
                    child("open_water_swimming", "2030-07-14T06:40:00.0", 1800), child("road_biking", "2030-07-14T07:35:00.0", 5000),
                    child("transition_v2", "2030-07-14T08:58:00.0", 100)]
        let legs = GarminMultisport.legs(kids)
        XCTAssertEqual(legs.map(\.leg), ["swim", "t1", "bike", "t2", "run"])
        XCTAssertEqual(legs[1].seconds, 200)
        XCTAssertNil(GarminMultisport.child(detail: ["summaryDTO": ["duration": 0]]))
        XCTAssertTrue(GarminMultisport.isMultisport(typeKey: "multi_sport"))
    }

    func testTuneUpSurvivesOddShelfValues() throws {
        let t = try JSONDecoder().decode(TuneUp.self, from: Data(#"{"day":"2030-05-04","size":"weird"}"#.utf8))
        XCTAssertEqual(t.size, .other); XCTAssertEqual(t.title, "Tune-up race")
        XCTAssertEqual(TuneUp(day: "x", size: .other, km: 12).distanceWords, "12 km")
        XCTAssertEqual(ClockText.minutes("07:30"), 450); XCTAssertNil(ClockText.minutes("25:00"))
    }
}
