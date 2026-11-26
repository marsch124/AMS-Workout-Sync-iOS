import XCTest
@testable import WorkoutCore

/* Round 29, lane health: invented answers only. */
final class Health29Tests: XCTestCase {
    private func json(_ t: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(t.utf8)) }

    func testSleepDebtSumsRecordedNightsAgainstGarminsNeedAndSkipsDashes() {
        let a = json("""
        [{"calendarDate":"2030-03-12","sleepTimeSeconds":25200,"napTimeSeconds":1800,"sleepNeed":{"actual":480}},
         {"calendarDate":"2030-03-13","sleepTimeSeconds":21600,"sleepNeed":{"baseline":420}},
         {"calendarDate":"2030-03-11","sleepNeed":{"actual":480}}]
        """)
        let n = BodyHealth.nights(a, endingOn: "2030-03-13")
        XCTAssertEqual(n.count, 7)
        XCTAssertEqual(n.last?.needMinutes, 420)
        XCTAssertNil(n[4].sleptMinutes)                      // 11th: need but no sleep = dash
        XCTAssertEqual(n[5].sleptMinutes, 450)               // 7h + 30m nap
        // (450-480) + (360-420) = -90
        XCTAssertEqual(BodyHealth.balance(n), -90)
        XCTAssertEqual(BodyHealth.balanceFigure(-90), "\u{2212}1h\u{00A0}30m")
        XCTAssertEqual(BodyHealth.balanceFigure(65), "+1h\u{00A0}05m")
        XCTAssertEqual(BodyHealth.missingNights(n), 5)
        XCTAssertTrue(BodyHealth.sleepLine(n).hasSuffix("5 nights without the watch"))
        XCTAssertNil(BodyHealth.balance(BodyHealth.nights(nil, endingOn: "2030-03-13")))
        XCTAssertEqual(BodyHealth.nights(nil, endingOn: "2030-03-13")[0].needMinutes, 480)   // the Board's rule
    }

    func testWeightChangeOverNinetyDaysAndItsLine() {
        let r = json("""
        {"dailyWeightSummaries":[{"summaryDate":"2030-03-10","latestWeight":{"weight":80300}},
        {"summaryDate":"2030-01-02","latestWeight":{"weight":80000}}]}
        """)
        let g = json(#"{"userGoals":[{"userGoalType":"WEIGHT_GRAMS","goalValue":78000,"startDate":"2029-01-01"}]}"#)
        let t = BodyHealth.weightTrend(range: r, goal: g)
        XCTAssertEqual(t.points.map(\.day), ["2030-01-02", "2030-03-10"])
        XCTAssertEqual(BodyHealth.weightChange(t.points), 0.3)
        XCTAssertEqual(BodyHealth.weightLine(dayWords: "Sun 10 Mar", change: 0.6, goalKg: nil), "Weighed Sun 10 Mar \u{00B7} +0.6 kg in 90 days")
        XCTAssertEqual(t.goalKg, 78.0)
        let single = BodyHealth.weightTrend(range: json(#"{"previousDateWeight":{"calendarDate":"2030-02-01","weight":79700}}"#), goal: nil)
        XCTAssertEqual(single.points.count, 1)
        XCTAssertNil(BodyHealth.weightChange(single.points))
        XCTAssertTrue(BodyHealth.weightTrend(range: nil, goal: nil).points.isEmpty)
    }

    func testWaterAndEnergyFromTheDaysSummary() {
        let s = json("""
        {"data":[{"calendarDate":"2030-03-13","calories":{"burnedResting":2000,"burnedActive":500,"burnedTotal":2500},
        "hydration":{"goalInMl":3000,"consumedInMl":0}}]}
        """)
        let f = BodyHealth.dayFacts(s, day: "2030-03-13")
        XCTAssertEqual(BodyHealth.energyLine(f.energy!), "Active 500 \u{00B7} resting 2,000")
        XCTAssertNil(BodyHealth.waterFigure(f.water))
        XCTAssertEqual(BodyHealth.waterLine(f.water), "No water logged today. Log it in Garmin Connect.")
        let w = BodyHealth.Water(ml: 1250, goalMl: 3000)
        XCTAssertEqual(BodyHealth.waterFigure(w), "1,250")
        XCTAssertEqual(BodyHealth.waterLine(w), "Goal 3,000 ml \u{00B7} 42%")
        XCTAssertEqual(BodyHealth.waterFill(w)!, 1250.0 / 3000, accuracy: 0.001)
        XCTAssertNil(BodyHealth.dayFacts(s, day: "2030-03-14").energy)
    }

    /* 2.9 look-over: "about" is rounded to a quarter of an hour, a whole hour written "8h". */
    func testNeedIsRoundedToAQuarter() {
        let n = (0..<7).map { BodyHealth.Night(day: "2030-01-0\($0 + 1)", sleptMinutes: 420, needMinutes: $0 == 0 ? 459 : 480) }
        XCTAssertEqual(BodyHealth.sleepLine(n), "Need about 8h a night")
        let m = (0..<7).map { BodyHealth.Night(day: "2030-01-0\($0 + 1)", sleptMinutes: 420, needMinutes: 455) }
        XCTAssertEqual(BodyHealth.sleepLine(m), "Need about 7h\u{00A0}30m a night")
    }
}
