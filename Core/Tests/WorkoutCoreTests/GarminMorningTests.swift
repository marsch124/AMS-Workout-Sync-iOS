import XCTest
@testable import WorkoutCore

/*
 * Garmin's morning numbers, from invented answers shaped like the ones in
 * Garmin's Personal API description. No network, no key.
 */
final class GarminMorningTests: XCTestCase {

    private func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /* 14 invented days before 25 Nov, 2026, one value each. */
    private func days(_ values: [Double], endingBefore day: String = "2026-11-25") -> [String: Double] {
        var out: [String: Double] = [:]
        for (i, v) in values.enumerated() { out[GarminMorning.addDays(day, -(i + 1))] = v }
        return out
    }

    func testLastNightIsTodaysDateButNotBeforeFour() {
        // 07:12 in Norrkoping: the night that ended this morning.
        XCTAssertEqual(GarminMorning.morningDay(now: at("2026-11-25T06:12:00Z"), calendar: cal), "2026-11-25")
        // 02:30: that night is not over; the last finished one is yesterday's.
        XCTAssertEqual(GarminMorning.morningDay(now: at("2026-11-25T01:30:00Z"), calendar: cal), "2026-11-24")
        XCTAssertEqual(GarminMorning.addDays("2026-03-01", -1, calendar: cal), "2026-02-28")
    }

    func testGarminsGMTStampsWithoutAZ() {
        XCTAssertEqual(GarminMorning.parseGMT("2026-11-25T06:12:00.0"), at("2026-11-25T06:12:00Z"))
        XCTAssertEqual(GarminMorning.parseGMT("2026-11-25T06:12:00"), at("2026-11-25T06:12:00Z"))
        XCTAssertEqual(GarminMorning.parseGMT("2026-11-25T06:12:00Z"), at("2026-11-25T06:12:00Z"))
        XCTAssertNil(GarminMorning.parseGMT(nil))
        XCTAssertNil(GarminMorning.parseGMT("soon"))
    }

    func testTokenExpiryComesFromTheMiddlePart() {
        // {"exp":1795000000} as the middle part, no signature worth reading.
        let payload = Data(#"{"exp":1795000000}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(GarminMorning.tokenExpiry("aaa.\(payload).bbb"), Date(timeIntervalSince1970: 1_795_000_000))
        XCTAssertNil(GarminMorning.tokenExpiry("not a token"))
    }

    func testSleepHrvAndSummaryAreReadFromTheirShapes() {
        let sleep = GarminMorning.sleep(json(#"{"dailySleepDTO":{"calendarDate":"2026-11-25","sleepTimeSeconds":26400}}"#))
        XCTAssertEqual(sleep.day, "2026-11-25")
        XCTAssertEqual(sleep.hours!, 7 + 20.0 / 60, accuracy: 0.001)
        // The flat shape of the description reads the same.
        XCTAssertEqual(GarminMorning.sleep(json(#"{"calendarDate":"2026-11-25","sleepTimeSeconds":"27000"}"#)).hours!, 7.5, accuracy: 0.001)

        let hrv = GarminMorning.hrv(json(#"{"hrvSummary":{"calendarDate":"2026-11-25","weeklyAvg":60,"lastNightAvg":64,"baseline":{"balancedLow":52,"balancedUpper":68},"status":"BALANCED"}}"#))
        XCTAssertEqual(hrv.lastNight, 64)
        XCTAssertEqual(hrv.rangeLow, 52)
        XCTAssertEqual(hrv.rangeHigh, 68)

        let s = GarminMorning.summary(json(#"{"calendarDate":"2026-11-25","restingHeartRate":47,"bodyBatteryAtWakeTime":71,"averageStressLevel":-1,"lastSyncTimestampGMT":"2026-11-25T06:05:00.0"}"#))
        XCTAssertEqual(s.resting, 47)
        XCTAssertEqual(s.bodyBatteryAtWake, 71)
        XCTAssertNil(s.stress, "-1 means Garmin could not tell")
        XCTAssertEqual(s.watchSynced, at("2026-11-25T06:05:00Z"))
    }

    func testRangesAreReadByDay() {
        let sleep = GarminMorning.sleepDays(json(#"[{"calendarDate":"2026-11-23","sleepTimeSeconds":25200},{"calendarDate":"2026-11-24","sleepTimeSeconds":0}]"#))
        XCTAssertEqual(sleep.count, 1, "a night with no sleep recorded is no night")
        XCTAssertEqual(sleep["2026-11-23"]!, 7, accuracy: 0.001)

        let hrv = GarminMorning.hrvDays(json(#"{"hrvSummaries":[{"calendarDate":"2026-11-23","lastNightAvg":61},{"calendarDate":"2026-11-24","lastNightAvg":58}]}"#))
        XCTAssertEqual(hrv, ["2026-11-23": 61, "2026-11-24": 58])

        let v2 = GarminMorning.summaryDays(json(#"{"data":[{"calendarDate":"2026-11-24","heartRate":{"restingValue":49},"stress":{"avgLevel":33}},{"calendarDate":"2026-11-23","heartRate":{"restingValue":50},"stress":{"avgLevel":-1}}]}"#))
        XCTAssertEqual(v2.resting, ["2026-11-24": 49, "2026-11-23": 50])
        XCTAssertEqual(v2.stress, ["2026-11-24": 33])
    }

    func testBrokenAnswersGiveNoNumbersAndNoCrash() {
        XCTAssertNil(GarminMorning.sleep(nil).hours)
        XCTAssertNil(GarminMorning.sleep(json(#"[1,2,3]"#)).hours)
        XCTAssertNil(GarminMorning.hrv(json(#"{"hrvSummary":"none"}"#)).lastNight)
        XCTAssertNil(GarminMorning.summary(json(#"{"restingHeartRate":null}"#)).resting)
        XCTAssertTrue(GarminMorning.hrvDays(json(#"{"x":1}"#)).isEmpty)
        XCTAssertTrue(GarminMorning.summaryDays("text").resting.isEmpty)
    }

    func testTheNormalIsTheFortnightBeforeAndNeedsFourDays() {
        let few = days([60, 62, 64])
        XCTAssertNil(GarminMorning.normal(of: few, before: "2026-11-25").normal)
        XCTAssertEqual(GarminMorning.normal(of: few, before: "2026-11-25").days, 3)

        var many = days([60, 62, 64, 58, 56])
        many["2026-11-25"] = 99                      // this morning is never part of its own normal
        many["2026-11-01"] = 5                       // older than a fortnight
        let n = GarminMorning.normal(of: many, before: "2026-11-25")
        XCTAssertEqual(n.normal!, 60, accuracy: 0.001)
        XCTAssertEqual(n.days, 5)
    }

    func testTheMorningIsPutTogetherWithItsTrend() {
        let numbers = GarminMorning.build(
            day: "2026-11-25", readAt: at("2026-11-25T06:12:00Z"),
            sleep: GarminMorning.sleep(json(#"{"dailySleepDTO":{"calendarDate":"2026-11-25","sleepTimeSeconds":26400}}"#)),
            hrv: GarminMorning.hrv(json(#"{"hrvSummary":{"calendarDate":"2026-11-25","lastNightAvg":64,"baseline":{"balancedLow":52,"balancedUpper":68}}}"#)),
            summary: GarminMorning.summary(json(#"{"calendarDate":"2026-11-25","restingHeartRate":47,"bodyBatteryAtWakeTime":71}"#)),
            sleepDays: days([7, 7, 7, 7]), hrvDays: days([60, 60, 60, 60]),
            restingDays: days([49, 49, 49, 49]), stressDays: days([30, 30, 30, 30], endingBefore: "2026-11-24").merging(["2026-11-24": 36]) { $1 },
            bodyBatteryDays: days([60, 60]))
        XCTAssertEqual(numbers.hrv?.value, 64)
        XCTAssertEqual(numbers.hrv?.normal, 60)
        XCTAssertEqual(numbers.hrvRangeLow, 52)
        XCTAssertEqual(numbers.sleepHours?.normal, 7)
        XCTAssertEqual(numbers.resting?.value, 47)
        XCTAssertEqual(numbers.bodyBattery?.value, 71)
        XCTAssertNil(numbers.bodyBattery?.normal, "two days are not a normal")
        XCTAssertEqual(numbers.stress?.value, 36, "yesterday's stress")
        XCTAssertEqual(numbers.stress?.normal, 30)
        XCTAssertFalse(numbers.isEmpty)
    }

    func testANightFiledUnderAnotherDayIsNotThisMornings() {
        let numbers = GarminMorning.build(
            day: "2026-11-25", readAt: Date(),
            sleep: GarminMorning.sleep(json(#"{"calendarDate":"2026-11-24","sleepTimeSeconds":26400}"#)),
            hrv: GarminMorning.HRVNight(), summary: GarminMorning.DaySummary(),
            sleepDays: [:], hrvDays: [:], restingDays: [:], stressDays: [:], bodyBatteryDays: [:])
        XCTAssertNil(numbers.sleepHours)
        XCTAssertTrue(numbers.isEmpty)
    }

    func testGreenOnlyForThisMorningAndReadingAtMostEveryHalfHour() {
        let n = MorningNumbers(day: "2026-11-25", readAt: Date(), hrv: .init(value: 64))
        XCTAssertTrue(GarminMorning.isFromThisMorning(n, today: "2026-11-25"))
        XCTAssertFalse(GarminMorning.isFromThisMorning(n, today: "2026-11-26"))
        XCTAssertFalse(GarminMorning.isFromThisMorning(MorningNumbers(day: "2026-11-25", readAt: Date()), today: "2026-11-25"))

        let t = at("2026-11-25T06:00:00Z")
        XCTAssertTrue(GarminMorning.mayRead(lastTried: nil, now: t))
        XCTAssertFalse(GarminMorning.mayRead(lastTried: t, now: t.addingTimeInterval(29 * 60)))
        XCTAssertTrue(GarminMorning.mayRead(lastTried: t, now: t.addingTimeInterval(30 * 60)))
    }

    func testTheFileKeepsNumbersOnly() throws {
        let file = GarminMorningFile(numbers: MorningNumbers(day: "2026-11-25", readAt: at("2026-11-25T06:12:00Z"), hrv: .init(value: 64, normal: 60, days: 9)),
                                     bodyBatteryDays: ["2026-11-24": 66], lastTried: at("2026-11-25T06:12:00Z"))
        let data = try JSONEncoder().encode(file)
        XCTAssertEqual(try JSONDecoder().decode(GarminMorningFile.self, from: data), file)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("key") || text.contains("token"))
    }
}
