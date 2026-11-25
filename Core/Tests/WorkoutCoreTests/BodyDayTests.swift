import XCTest
@testable import WorkoutCore

/* Invented answers only: no real numbers in this file. */
final class BodyDayTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let day = "2030-03-10"
    /* 2030-03-10 12:00 UTC */
    private var noon: Date { Date(timeIntervalSince1970: 1_899_374_400) }
    private func ms(_ hour: Double) -> Double { (noon.timeIntervalSince1970 + (hour - 12) * 3600) * 1000 }

    private func json(_ text: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(text.utf8)) }

    private func curve(events: String = "[]") -> Any? {
        json("""
        [{"date":"2030-03-10","bodyBatteryValuesArray":[[\(ms(-1)), 99],[\(ms(1)), 80],[\(ms(2))  , 70],[\(ms(3))  , 60],[\(ms(5))  , 55],[\(ms(6)) , null],[\(ms(8)), 40]],
          "bodyBatteryActivityEvent": \(events)}]
        """)
    }

    /* Yesterday's line (2.7): only the readings inside yesterday's 24 hours, whatever day the answer files them under. */
    func testYesterdaysCurveIsCutToYesterdays24Hours() {
        let answer = json("""
        [{"date":"2030-03-09","bodyBatteryValuesArray":[[\(ms(-25)), 11],[\(ms(-24)), 30],[\(ms(-12)), 75],[\(ms(-10)), null],[\(ms(-0.5)), 42]]},
         {"date":"2030-03-10","bodyBatteryValuesArray":[[\(ms(-3)), 66],[\(ms(0)), 41],[\(ms(1)), 44]]}]
        """)
        let y = GarminBody.yesterday(answer, day: day, calendar: cal)
        XCTAssertEqual(y.map(\.value), [30, 75, 66, 42])   // oldest first; the day before, the empty one and today's are left out
        XCTAssertEqual(GarminBody.yesterday(nil, day: day, calendar: cal), [])
        // It runs to 23:30, so it is whole and kept for the day; one that stops in the evening is read again.
        XCTAssertTrue(GarminBody.yesterdayIsWhole(y, day: day, calendar: cal))
        XCTAssertFalse(GarminBody.yesterdayIsWhole(Array(y.dropLast()), day: day, calendar: cal))
        XCTAssertFalse(GarminBody.yesterdayIsWhole(nil, day: day, calendar: cal))
        // An older file without yesterday still reads, and yesterday survives a round trip.
        let old = try? JSONDecoder().decode(BodyDay.Battery.self, from: Data(#"{"points":[],"workouts":[]}"#.utf8))
        XCTAssertNotNil(old)
        XCTAssertNil(old?.yesterday)
        let kept = BodyDay.Battery(points: [], yesterday: y)
        XCTAssertEqual(try? JSONDecoder().decode(BodyDay.Battery.self, from: JSONEncoder().encode(kept)), kept)
    }

    func testBatteryPointsNowHighLow() {
        let b = GarminBody.battery(curve(), activities: nil, day: day, now: noon.addingTimeInterval(-3 * 3600), calendar: cal)
        // "Now" is 09:00: the reading from before midnight, the empty one and the later one are left out.
        XCTAssertEqual(b?.points.count, 5)
        XCTAssertEqual(b?.now, 40)
        XCTAssertEqual(b?.highest, 80)
        XCTAssertEqual(b?.lowest, 40)
    }

    private let run = """
    [{"activityId":123,"activityName":"Morning run","activityType":{"typeKey":"running"},
      "startTimeGMT":"2030-03-10 02:00:00","startTimeLocal":"2030-03-10 02:00:00","duration":3600},
     {"activityId":9,"activityName":"Yesterday","activityType":{"typeKey":"cycling"},
      "startTimeGMT":"2030-03-09 20:00:00","startTimeLocal":"2030-03-09 20:00:00","duration":600}]
    """

    func testDrainFromGarminEvent() {
        let ev = #"[{"eventType":"ACTIVITY","eventStartTimeGmt":"2030-03-10T02:05:00.0","durationInMilliseconds":3600000,"bodyBatteryImpact":-17}]"#
        let b = GarminBody.battery(curve(events: ev), activities: json(run), day: day, now: noon, calendar: cal)
        XCTAssertEqual(b?.workouts.count, 1)   // yesterday's is left out
        XCTAssertEqual(b?.workouts.first?.name, "Morning run")
        XCTAssertEqual(b?.workouts.first?.type, "running")
        XCTAssertEqual(b?.workouts.first?.drain, 17)
        XCTAssertEqual(b?.workouts.first?.end.timeIntervalSince(b!.workouts[0].start), 3600)
    }

    func testDrainFromReadingsWhenNoEvent() {
        // Start 02:00 UTC = reading 70 at hour 2 (<= start); end 03:00 = reading 60 at hour 3 (>= end).
        let b = GarminBody.battery(curve(), activities: json(run), day: day, now: noon, calendar: cal)
        XCTAssertEqual(b?.workouts.first?.drain, 10)
        // An event far from the start does not count.
        let far = #"[{"eventType":"ACTIVITY","eventStartTimeGmt":"2030-03-10T05:00:00.0","bodyBatteryImpact":-40}]"#
        let c = GarminBody.battery(curve(events: far), activities: json(run), day: day, now: noon, calendar: cal)
        XCTAssertEqual(c?.workouts.first?.drain, 10)
        // No reading after the end: no drain, not 0.
        let d = GarminBody.battery(curve(), activities: json(run), day: day, now: noon.addingTimeInterval(-9.5 * 3600), calendar: cal)
        XCTAssertNil(d?.workouts.first?.drain)
    }

    func testSleepSevenNightsWithGap() {
        let range = json("""
        {"dailySleepDTOs":[{"calendarDate":"2030-03-10","sleepTimeSeconds":27000},{"calendarDate":"2030-03-09","sleepTimeSeconds":0},
        {"calendarDate":"2030-03-08","sleepTimeSeconds":23400},{"calendarDate":"2030-03-04","sleepTimeSeconds":25200}]}
        """)
        let b = GarminBody.build(day: day, nightDay: day, readAt: noon, battery: nil, sleepDays: GarminBody.sleepDays(range),
                                 hrv: .init(), hrvDays: [:], summaries: ([:], [:], [:]))
        XCTAssertEqual(b.sleep?.lastNight, 7.5)
        XCTAssertEqual(b.sleep?.nights.count, 7)
        XCTAssertEqual(b.sleep?.nights.first?.day, "2030-03-04")
        XCTAssertEqual(b.sleep?.nights.first?.value, 7)
        XCTAssertNil(b.sleep?.nights[5].value)   // 03-09 had 0 seconds: no data, not 0
        XCTAssertNil(b.sleep?.nights[1].value)
    }

    func testHRVWithRangeAndStillLearning() {
        let today = GarminMorning.hrv(json(#"{"hrvSummary":{"calendarDate":"2030-03-10","lastNightAvg":55,"baseline":{"balancedLow":45,"balancedUpper":62}}}"#))
        let days = GarminBody.hrvDays(json(#"{"hrvSummaries":[{"calendarDate":"2030-03-09","lastNightAvg":50},{"calendarDate":"2030-03-08","lastNightAvg":52}]}"#))
        let b = GarminBody.build(day: day, nightDay: day, readAt: noon, battery: nil, sleepDays: [:], hrv: today, hrvDays: days, summaries: ([:], [:], [:]))
        XCTAssertEqual(b.hrv?.lastNight, 55)
        XCTAssertEqual(b.hrv?.rangeLow, 45)
        XCTAssertEqual(b.hrv?.rangeHigh, 62)
        XCTAssertEqual(b.hrv?.stillLearning, false)
        XCTAssertEqual(b.hrv?.days.last?.value, 55)
        XCTAssertEqual(b.hrv?.days[5].value, 50)

        let learning = GarminMorning.hrv(json(#"{"hrvSummary":{"calendarDate":"2030-03-10","lastNightAvg":48,"baseline":{}}}"#))
        let l = GarminBody.build(day: day, nightDay: day, readAt: noon, battery: nil, sleepDays: [:], hrv: learning, hrvDays: [:], summaries: ([:], [:], [:]))
        XCTAssertEqual(l.hrv?.stillLearning, true)
        XCTAssertNil(l.hrv?.rangeLow)
    }

    func testRestingAndStress() {
        var items: [String] = []
        for i in 0..<9 {
            let d = GarminMorning.addDays(day, -i)
            items.append(#"{"calendarDate":"\#(d)","heartRate":{"restingValue":\#(50 + i)},"stress":{"avgLevel":\#(30 + i),"maxLevel":\#(80 + i)}}"#)
        }
        let s = GarminBody.summaryDays(json("[" + items.joined(separator: ",") + "]"))
        let b = GarminBody.build(day: day, nightDay: day, readAt: noon, battery: nil, sleepDays: [:], hrv: .init(), hrvDays: [:], summaries: s)
        XCTAssertEqual(b.resting?.today, 50)
        XCTAssertEqual(b.resting?.normal ?? 0, 54.5, accuracy: 0.001)   // the eight days before: 51...58
        XCTAssertEqual(b.resting?.days.count, 7)
        XCTAssertEqual(b.stress?.average, 30)
        XCTAssertEqual(b.stress?.highest, 80)
        XCTAssertEqual(b.stress?.days.last?.value, 30)
        XCTAssertEqual(b.stress?.days.first?.value, 36)
    }

    func testEverythingMissing() {
        for junk: Any? in [nil, NSNull(), "nope", [Any](), [String: Any](), ["a": 1] as [String: Any], [[1, 2]] as [Any]] {
            XCTAssertNil(GarminBody.battery(junk, activities: junk, day: day, now: noon, calendar: cal))
            let s = GarminBody.summaryDays(junk)
            let b = GarminBody.build(day: day, nightDay: day, readAt: noon, battery: nil, sleepDays: GarminBody.sleepDays(junk),
                                     hrv: GarminMorning.hrv(junk), hrvDays: GarminBody.hrvDays(junk), summaries: s)
            XCTAssertTrue(b.isEmpty)
        }
        // Odd values inside a real shape never become NaN or a crash.
        let odd = json(#"[{"date":"2030-03-10","bodyBatteryValuesArray":[[1,2,3],["x","y"],[5],[1899374400000,"150"],[1899374400000,"42"]]}]"#)
        let b = GarminBody.battery(odd, activities: nil, day: day, now: noon, calendar: cal)
        XCTAssertEqual(b?.points.count, 1)
        XCTAssertEqual(b?.now, 42)
    }

    func testCodableRoundTrip() throws {
        let b = GarminBody.battery(curve(), activities: json(run), day: day, now: noon, calendar: cal)
        let full = BodyDay(day: day, readAt: noon, battery: b)
        let back = try JSONDecoder().decode(BodyDay.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(back, full)
    }
}
