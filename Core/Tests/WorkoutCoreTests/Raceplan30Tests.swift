import XCTest
@testable import WorkoutCore

/* Round 30, race-plan lane: forecast, range, course pacing, age-group comparison. Every number is invented. */
final class Raceplan30Tests: XCTestCase {
    private func rides(_ n: Int) -> [RaceEffort] {
        (0..<n).map { _ in RaceEffort(family: "bike", typeKey: "road_biking", seconds: 7200, metres: 7200 * 7.5, avgHr: 140) }  // 27 km/h
    }
    private func runs(_ n: Int) -> [RaceEffort] {
        (0..<n).map { _ in RaceEffort(family: "run", typeKey: "running", seconds: 3600, metres: 3600 * 3.0, avgHr: 145, avgPowerW: 220) }
    }
    private func basis(rides r: Int = 5, runs u: Int = 5) -> ForecastBasis {
        ForecastBasis(css: 110, lthr: 165, efforts: rides(r) + runs(u))
    }
    private var flat: RaceCourse { RaceCourse.flatDefault }

    func testForecastWorksEachPartFromTheTestAndTheSteadySessions() {
        let f = RaceForecastRules.make(basis(), course: flat, days: 30, today: "2027-06-11")
        // Swim: (110 + 4) s per 100 m over 1900 m = 2166 s.
        XCTAssertEqual(f.leg(.swim)?.mid, 2166)
        // Bike: 90 km at 27 km/h = 12000 s; flat, 18 °C: no heat, no climb.
        XCTAssertEqual(f.leg(.bike)?.mid, 12000)
        // Run: 21100 m at 3 m/s = 7033 s, +4 % off the bike, +15 °C..18 °C heat 1.5 %.
        let run = 21100 / 3.0 * 1.04 * (1 + 3 * 0.005)
        XCTAssertEqual(f.leg(.run)?.mid, Int(run.rounded()))
        XCTAssertEqual(f.leg(.t1)?.mid, 240)
        XCTAssertNotNil(f.total)
        XCTAssertTrue(f.total!.low <= f.total!.mid && f.total!.mid <= f.total!.high)
        XCTAssertEqual(f.total!.low % 300, 0); XCTAssertEqual(f.total!.high % 300, 0)
        XCTAssertEqual(f.workedOut, "2027-06-07", "a Monday")
        XCTAssertTrue(f.missing.isEmpty)
    }

    func testClimbingAndHeatSlowTheBikeAndTheRun() {
        var hilly = flat
        hilly.bikeClimbM = 900; hilly.julyTempC = 26
        let f = RaceForecastRules.make(basis(), course: hilly, days: 30, today: "2027-06-11")
        let climb = 900.0 / 90
        let expected = 12000.0 * (1 + climb * 0.003) * (1 + 6 * 0.004)
        XCTAssertEqual(f.leg(.bike)?.mid, Int(expected.rounded()))
        XCTAssertGreaterThan(f.leg(.bike)!.mid, 12000)
    }

    func testOnlySteadySessionsCount() {
        let lthr = 165.0
        let all = [
            RaceEffort(family: "bike", typeKey: "indoor_cycling", seconds: 7200, metres: 60_000, avgHr: 140),     // indoors
            RaceEffort(family: "bike", typeKey: "road_biking", seconds: 1800, metres: 15_000, avgHr: 140),        // too short
            RaceEffort(family: "bike", typeKey: "road_biking", seconds: 7200, metres: 54_000, avgHr: 120),        // too easy
            RaceEffort(family: "bike", typeKey: "road_biking", seconds: 7200, metres: 54_000, avgHr: 170),        // too hard
            RaceEffort(family: "bike", typeKey: "road_biking", seconds: 7200, metres: 54_000, avgHr: 140),        // counts
        ]
        XCTAssertEqual(RaceForecastRules.steady(all, family: "bike", lthr: lthr).count, 1)
        // With no steady runs there is no run, and so no total.
        let f = RaceForecastRules.make(ForecastBasis(css: 110, lthr: 165, efforts: rides(4)), course: flat, days: 30, today: "2027-06-11")
        XCTAssertNil(f.leg(.run)); XCTAssertNil(f.total); XCTAssertEqual(f.missing, [.run])
    }

    func testTheRangeIsWideFarOutAndNarrowsEveryWeek() {
        var lastWidth = Int.max
        for days in [300, 240, 180, 120, 60, 14, 0] {
            let t = RaceForecastRules.make(basis(), course: flat, days: days, today: "2026-11-30").total!
            let width = t.high - t.low
            XCTAssertLessThanOrEqual(width, lastWidth, "wider at \(days) days")
            lastWidth = width
        }
        let far = RaceForecastRules.make(basis(), course: flat, days: 300, today: "2026-11-30").total!
        let near = RaceForecastRules.make(basis(), course: flat, days: 3, today: "2027-07-05").total!
        XCTAssertGreaterThan(far.high - far.low, 2 * (near.high - near.low))
        // Few steady sessions: wider than with plenty.
        let thin = RaceForecastRules.make(basis(rides: 1, runs: 1), course: flat, days: 60, today: "2027-05-10").leg(.bike)!
        let thick = RaceForecastRules.make(basis(), course: flat, days: 60, today: "2027-05-10").leg(.bike)!
        XCTAssertGreaterThan(thin.high - thin.low, thick.high - thick.low)
        XCTAssertEqual(RaceForecastRules.words(LegRange(low: 19800, mid: 20000, high: 21300)), "5h\u{00A0}30m \u{2013} 5h\u{00A0}55m")
    }

    func testOneSnapshotAWeekAndTheTrendBars() {
        XCTAssertEqual(ForecastShelf.weekKey("2026-11-30"), "2026-49")
        XCTAssertEqual(ForecastShelf.weekKey("2026-12-02"), "2026-49")
        XCTAssertEqual(ForecastShelf.key("2027-01-01"), "raceplan/forecast/2026-53")
        let a = RaceForecastRules.make(basis(), course: flat, days: 200, today: "2026-12-28")
        var b = RaceForecastRules.make(basis(), course: flat, days: 193, today: "2027-01-04")
        b.total = LegRange(low: 1, mid: a.total!.mid - 600, high: 3)
        let rows = ForecastTrend.rows([b, a])
        XCTAssertEqual(rows.map(\.workedOut), ["2026-12-28", "2027-01-04"], "oldest first")
        XCTAssertEqual(rows[0].fraction, 1.0, accuracy: 0.001); XCTAssertEqual(rows[1].fraction, 0.15, accuracy: 0.001)
        let encoded = try! JSONEncoder().encode(a)
        XCTAssertEqual(try! JSONDecoder().decode(RaceForecast.self, from: encoded), a)
    }

    func testGarminListIsReadForBikeAndRunOnly() {
        let json: [String: Any] = ["activities": [
            ["activityType": ["typeKey": "road_biking"], "duration": 7200.0, "distance": 54000.0, "averageHR": 140.0],
            ["activityType": ["typeKey": "running"], "duration": 3000.0, "distance": 9000.0, "averageHR": 150.0, "avgPower": 230.0],
            ["activityType": ["typeKey": "lap_swimming"], "duration": 2000.0, "distance": 1500.0, "averageHR": 120.0],
            ["activityType": ["typeKey": "running"], "duration": 0.0, "distance": 9000.0, "averageHR": 150.0],
        ]]
        let read = RaceEffort.read(json)
        XCTAssertEqual(read.map(\.family), ["bike", "run"])
        XCTAssertEqual(read[1].avgPowerW, 230)
        XCTAssertNil(read[0].avgPowerW)
    }

    func testPacingTargetsFollowHisZonesAndAreEasierOnClimbs() {
        var course = flat
        course.bike = [CourseSection(0, 30, .flat), CourseSection(30, 45, .climb), CourseSection(45, 90, .descent)]
        course.run = [CourseSection(0, 7, .flat), CourseSection(7, 14, .climb), CourseSection(14, 21.1, .flat)]
        let bike = RaceSectionRules.bike(course, lthr: 160, ftp: 200)
        XCTAssertEqual(bike[0].pulseLow, 136); XCTAssertEqual(bike[0].pulseHigh, 144)   // 85–90 %
        XCTAssertEqual(bike[0].powerLow, 150); XCTAssertEqual(bike[0].powerHigh, 164)   // 75–82 %
        XCTAssertLessThan(bike[1].pulseHigh!, bike[0].pulseHigh!)
        XCTAssertLessThan(bike[1].powerHigh!, bike[0].powerHigh!)
        XCTAssertEqual(bike[2].powerHigh, 120)
        // A different test moves every target; no test, no pulse.
        XCTAssertEqual(RaceSectionRules.bike(course, lthr: 170, ftp: nil)[0].pulseLow, 145)
        XCTAssertNil(RaceSectionRules.bike(course, lthr: nil, ftp: 200)[0].pulseLow)
        XCTAssertNil(RaceSectionRules.bike(course, lthr: 160, ftp: nil)[0].powerLow)
        let run = RaceSectionRules.run(course, lthr: 160, runPowerW: 220)
        XCTAssertEqual(run[0].pulseLow, 131)                    // first lap 82 %
        XCTAssertLessThan(run[1].pulseHigh!, run[2].pulseHigh!)
        XCTAssertEqual(run[2].pulseHigh, 149)                   // last lap 93 %
        XCTAssertEqual(run[0].powerLow, 207)
        XCTAssertNil(RaceSectionRules.run(course, lthr: 160, runPowerW: nil)[0].powerLow)
    }

    func testAgeGroupAndComparisonNameTheBiggestGain() {
        XCTAssertEqual(AgeBracket.containing(age: 47)?.label, "45\u{2013}49")
        XCTAssertEqual(AgeBracket.containing(age: 77)?.label, "75+")
        XCTAssertEqual(AgeBracket.atRace(ageNow: 44, thisYear: 2026, raceYear: 2027)?.label, "45\u{2013}49")
        XCTAssertEqual(AgeBracket.from(label: "40\u{2013}44"), AgeBracket(lo: 40, hi: 44))
        XCTAssertTrue(RaceCourse.forRace(title: "IRONMAN 70.3 Jönköping").name.contains("Jönköping"))
        XCTAssertTrue(RaceCourse.forRace(title: "ironman 70.3 jonkoping").name.contains("Jönköping"))
        XCTAssertEqual(RaceCourse.forRace(title: "Half-distance triathlon"), RaceCourse.flatDefault)

        var course = flat
        course.ageGroups = [CourseAgeGroup(bracket: "45\u{2013}49",
                                           middle: LegTimes(swim: 2100, t1: 240, bike: 11000, t2: 120, run: 7600),
                                           topThird: LegTimes(swim: 1900, t1: 200, bike: 10200, t2: 100, run: 6900))]
        let f = RaceForecastRules.make(basis(), course: course, days: 30, today: "2027-06-11")   // swim 2166, bike 12000
        let c = RaceComparison.make(f, course: course, bracket: AgeBracket(lo: 45, hi: 49))!
        XCTAssertEqual(c.biggest, .bike)
        let bike = c.gaps.first { $0.leg == .bike }!
        XCTAssertEqual(bike.behindMiddle, 1000)
        XCTAssertEqual(c.line(bike), "Bike: 17 min behind the middle of your age group \u{2014} the biggest gain")
        XCTAssertEqual(c.line(c.gaps.first { $0.leg == .swim }!), "Swim: 1 min behind the middle of your age group")
        XCTAssertEqual(c.topLine(bike), "30 min from the fastest quarter")
        XCTAssertEqual(c.gaps.count, 4); XCTAssertEqual(c.line(c.gaps[3]), "Changeovers: level with the middle of your age group")
        XCTAssertNotNil(RaceCourse.jonkoping.ageGroup(AgeBracket(lo: 45, hi: 49)))
        XCTAssertEqual(RaceCourse.jonkoping.bike.last?.toKm, 90); XCTAssertEqual(RaceCourse.jonkoping.run.last!.toKm, 21.1, accuracy: 0.01)
        XCTAssertNil(RaceComparison.make(f, course: course, bracket: AgeBracket(lo: 30, hi: 34)), "no past times for that group")
        // Everyone ahead of the middle: nothing is marked.
        course.ageGroups[0].middle = LegTimes(swim: 3000, t1: 240, bike: 15000, t2: 120, run: 9000)
        XCTAssertNil(RaceComparison.make(f, course: course, bracket: AgeBracket(lo: 45, hi: 49))!.biggest)
    }
}
