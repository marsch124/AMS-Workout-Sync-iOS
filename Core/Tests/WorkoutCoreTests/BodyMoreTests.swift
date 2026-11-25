import XCTest
@testable import WorkoutCore

/* Round 28's Body rules, on invented numbers only. */
final class BodyMoreTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let day = "2030-03-13"   // a Wednesday
    private var midnight: Date { cal.startOfDay(for: GarminMorning.date(day, calendar: cal)!) }
    private func at(_ h: Double, dayOffset: Int = 0) -> Date { midnight.addingTimeInterval((Double(dayOffset) * 24 + h) * 3600) }
    private func pt(_ h: Double, _ v: Double, dayOffset: Int = 0) -> BodyDay.Point { .init(time: at(h, dayOffset: dayOffset), value: v) }
    private func json(_ text: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(text.utf8)) }

    func testNightsChargeFromTheEveningBeforeToTheMorningsHigh() {
        let evening = [pt(19, 40, dayOffset: -1), pt(23, 18, dayOffset: -1)]
        let today = [pt(0.5, 22), pt(3, 50), pt(7, 66), pt(9, 61), pt(12, 99)]   // the noon reading is after 11:00: not the morning
        XCTAssertEqual(BodyPage.charge(yesterday: evening, today: today, day: day, calendar: cal), 48)   // 66 - 18
        XCTAssertEqual(BodyPage.chargeLine(48), "Charged +48 overnight")
        // Yesterday's evening is not there: since midnight (low 22 at 00:30).
        XCTAssertEqual(BodyPage.charge(yesterday: [pt(10, 80, dayOffset: -1)], today: today, day: day, calendar: cal), 44)
        XCTAssertEqual(BodyPage.charge(yesterday: nil, today: today, day: day, calendar: cal), 44)
        // A morning high that is before the low does not count; no rise, no line.
        XCTAssertNil(BodyPage.charge(yesterday: nil, today: [pt(1, 80), pt(5, 60)], day: day, calendar: cal))
        XCTAssertNil(BodyPage.charge(yesterday: nil, today: [], day: day, calendar: cal))
        XCTAssertNil(BodyPage.chargeLine(nil))
    }

    func testTheCalmLineStatesWhereTheNumbersSitAndNothingMore() {
        let all = BodyPage.Calm(hrv: 60, hrvLow: 52, hrvHigh: 68, resting: 48, restingNormal: 49, wake: 70, wakeNormal: 68)
        XCTAssertEqual(BodyPage.calmLine(all), "3 of 3 in your normal range")
        var low = all; low.hrv = 47
        XCTAssertEqual(BodyPage.calmLine(low), "2 of 3 in your normal range · HRV below it")
        // Only the ones with a normal are counted.
        let two = BodyPage.Calm(hrv: 60, hrvLow: nil, hrvHigh: nil, resting: 56, restingNormal: 49, wake: 70, wakeNormal: nil)
        XCTAssertEqual(BodyPage.calmLine(two), "0 of 1 in your normal range · resting pulse above it")
        XCTAssertNil(BodyPage.calmLine(BodyPage.Calm(hrv: 60, resting: 48, wake: 70)))
        // Pulse: 4 % of 50 is 2, so 51.9 sits inside and 52 does not.
        XCTAssertTrue(BodyPage.within(51.9, normal: 50))
        XCTAssertFalse(BodyPage.within(52, normal: 50))
        // No judging words.
        for line in [BodyPage.calmLine(all), BodyPage.calmLine(low), BodyPage.calmLine(two)].compactMap({ $0 }) {
            for bad in ["good", "bad", "ready", "should", "rest "] { XCTAssertFalse(line.lowercased().contains(bad), line) }
        }
    }

    func testWeeklyAveragesCountOnlyTheDaysWithReadings() {
        // Weeks start on Monday: this week is Mon 11 – Wed 13 so far.
        XCTAssertEqual(BodyPage.weekStart(of: day, calendar: cal), "2030-03-11")
        XCTAssertEqual(BodyPage.weekStart(of: "2030-03-17", calendar: cal), "2030-03-11")   // a Sunday
        let v: [String: Double] = ["2030-03-04": 6, "2030-03-06": 8, "2030-03-11": 7, "2030-03-13": 9, "2030-02-20": 5]
        let w = BodyPage.weekly(v, weeks: 4, endingOn: day)
        XCTAssertEqual(w.map(\.day), ["2030-02-18", "2030-02-25", "2030-03-04", "2030-03-11"])
        XCTAssertEqual(w[0].value, 5)
        XCTAssertNil(w[1].value)            // a week with no readings: nil, never 0
        XCTAssertEqual(w[2].value, 7)       // (6 + 8) / 2, the five days without readings left out
        XCTAssertEqual(w[3].value, 8)       // this week so far
        XCTAssertEqual(BodyPage.weekly(v, weeks: 12, endingOn: day).count, 12)
        XCTAssertEqual(BodyPage.spanAverage(v, weeks: 4, endingOn: day) ?? 0, 7, accuracy: 0.001)   // 5, 6, 8, 7, 9
    }

    func testTheLongerViewsKeepTodaysFigureAndSayTheirAverage() {
        var h = BodyHistory()
        h.sleep = ["2030-03-04": 6, "2030-03-06": 8, "2030-03-11": 7]
        let b = BodyDay(day: day, readAt: at(12), sleep: .init(lastNight: 7.5, nights: BodyPage.weekly([:], weeks: 0, endingOn: day) + [.init(day: day, value: 7.5)]))
        let t = BodyPage.tile(.sleep, b, span: .weeks4, history: h)
        XCTAssertEqual(t.figure, "7h\u{00A0}30m")
        XCTAssertEqual(t.days.count, 4)
        XCTAssertEqual(t.note, "4-week average 7h\u{00A0}08m")   // 6, 8, 7, 7.5
        XCTAssertEqual(BodyPage.tile(.sleep, b, span: .weeks12, history: h).days.count, 12)
        // The rows follow the span, newest first, and a week without a reading has no value.
        let rows = BodyPage.rows(.sleep, b, span: .weeks4, history: h)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].day, "2030-03-11")
        XCTAssertNil(rows[2].value)
        XCTAssertEqual(BodyPage.rows(.sleep, b).count, 1)
    }

    func testTheNormalBandIsInsideTheBarsScale() {
        let days = (0..<3).map { BodyDay.DayValue(day: "d\($0)", value: [50, 60, nil][$0]) }
        let plain = BodyPage.bars(days, band: nil)
        XCTAssertNil(plain.band)
        XCTAssertEqual(plain.heights[1], 1)
        // A band above the highest bar lifts the scale: the bars get shorter and the band's top is the top.
        let with = BodyPage.bars(days, band: 55...75)
        XCTAssertNil(with.heights[2])
        XCTAssertLessThan(with.heights[1]!, 1)
        XCTAssertEqual(with.band?.upperBound, 1)
        XCTAssertGreaterThan(with.band!.lowerBound, 0)
        XCTAssertLessThan(with.band!.lowerBound, with.band!.upperBound)
        // The old call is unchanged.
        XCTAssertEqual(BodyPage.bars(days), plain.heights)
    }

    func testStepsAndIntensityTilesAndTheirParsing() {
        let answer = json("""
        {"data":[
         {"calendarDate":"2030-03-10","movement":{"steps":{"value":9000,"goal":8000}},"intensityMinutes":{"moderate":30,"vigorous":10,"goal":150}},
         {"calendarDate":"2030-03-11","movement":{"steps":{"value":0}},"intensityMinutes":{"moderate":0,"vigorous":0}},
         {"calendarDate":"2030-03-12","movement":{"steps":{"value":7000,"goal":8000}},"intensityMinutes":{"moderate":20,"vigorous":0,"goal":150}},
         {"calendarDate":"2030-03-13","movement":{"steps":{"value":8400,"goal":8000}},"intensityMinutes":{"moderate":10,"vigorous":5,"goal":150}}]}
        """)
        let a = GarminBody.activityDays(answer)
        XCTAssertNil(a.steps["2030-03-11"])         // a day without the watch is left out
        XCTAssertEqual(a.intensity["2030-03-13"], 20)   // 10 + 2 x 5
        XCTAssertEqual(a.weeklyGoal, 150)
        let b = GarminBody.build(day: day, nightDay: day, readAt: at(12), battery: nil, sleepDays: [:], hrv: .init(), hrvDays: [:],
                                 summaries: ([:], [:], [:]), activity: a)
        let steps = BodyPage.tile(.steps, b)
        XCTAssertEqual(steps.figure, "8,400")
        XCTAssertEqual(steps.unit, "steps")
        XCTAssertEqual(steps.note, "7-day average 8,133")           // 9000, 7000, 8400
        XCTAssertEqual(steps.days.count, 7)
        // Only this week counts (Mon 11 – Wed 13): 0 + 20 + 20; moderate 30 and vigorous 5.
        let n = BodyPage.tile(.intensity, b)
        XCTAssertEqual(n.figure, "40")
        XCTAssertEqual(n.unit, "of 150")
        XCTAssertEqual(n.note, "moderate 30 · vigorous 5")
        XCTAssertEqual(BodyPage.rows(.steps, b).first?.value, "8,400 steps")
        XCTAssertEqual(BodyPage.rows(.intensity, b).first?.value, "20 min")
        // Nothing at all: a dash, no crash.
        XCTAssertEqual(BodyPage.tile(.steps, BodyDay(day: day, readAt: at(1))).figure, "–")
        XCTAssertEqual(BodyPage.grouped(1234567), "1,234,567")
        XCTAssertEqual(BodyPage.Instrument.allCases.count, 6)
        // A quiet week of zeros still has short bars, not dashes.
        XCTAssertEqual(BodyPage.bars([.init(day: "a", value: 0), .init(day: "b", value: 0)]), [0.15, 0.15])
    }

    func testTheBatteryWeekFilesEachReadingUnderItsOwnDay() {
        func ms(_ h: Double, _ off: Int) -> Double { at(h, dayOffset: off).timeIntervalSince1970 * 1000 }
        let answer = json("""
        [{"date":"2030-03-07","bodyBatteryValuesArray":[[\(ms(8, -6)), 70],[\(ms(14, -6)), 40],[\(ms(14.5, -6)), null]]},
         {"date":"2030-03-09","bodyBatteryValuesArray":[[\(ms(2, -4)), 30],[\(ms(9, -4)), 88]]},
         {"date":"2030-03-12","bodyBatteryValuesArray":[[\(ms(23, -1)), 35],[\(ms(23, -1)), 35]]}]
        """)
        let today = [pt(1, 20), pt(8, 75)]
        let w = GarminBody.batteryWeek(answer, day: day, todayPoints: today, calendar: cal)
        XCTAssertEqual(w.count, 7)
        XCTAssertEqual(w.first?.day, "2030-03-07")
        XCTAssertEqual(w.last?.day, day)
        XCTAssertEqual(w[0].high, 70); XCTAssertEqual(w[0].low, 40)
        XCTAssertTrue(w[1].points.isEmpty)            // a day without readings stays, empty, with no figures
        XCTAssertNil(w[1].high)
        XCTAssertNil(BodyPage.weekFigures(w[1]))
        XCTAssertEqual(BodyPage.weekFigures(w[2])?.high, "88")
        XCTAssertEqual(w[5].points.count, 1)          // the same reading twice is one
        XCTAssertEqual(w[6].high, 75)                 // today's own curve
        XCTAssertTrue(GarminBody.weekIsHeld(w, day: day))
        XCTAssertFalse(GarminBody.weekIsHeld(w, day: "2030-03-14"))
        let many = (0..<400).map { pt(Double($0) / 20, Double($0 % 100)) }
        XCTAssertEqual(GarminBody.thin(many, to: 48).count, 48)
        XCTAssertEqual(GarminBody.thin(many, to: 48).last, many.last)
    }

    func testTheDaysKeptPerDayDecodeFromAnOldFileAndAskOnlyForWhatIsMissing() throws {
        // An older Body file has none of the new fields.
        let old = #"{"day":"2030-03-13","readAt":0}"#
        let d = try JSONDecoder().decode(BodyDay.self, from: Data(old.utf8))
        XCTAssertNil(d.steps); XCTAssertNil(d.batteryWeek)
        var h = BodyHistory()
        // Nothing held: a four-week read starts at the oldest Monday.
        XCTAssertEqual(h.readFrom(.weeks4, today: day), "2030-02-18")
        XCTAssertEqual(h.readFrom(.weeks12, today: day), "2029-12-24")
        for i in 0..<30 { h.sleep[GarminMorning.addDays("2030-02-18", i)] = 7 }
        XCTAssertEqual(h.readFrom(.weeks4, today: day), day)   // every day held: nothing older to ask for
        h.sleep["2030-03-05"] = nil
        XCTAssertEqual(h.readFrom(.weeks4, today: day), "2030-03-05")
        h.prune(before: "2030-03-01")
        XCTAssertNil(h.sleep["2030-02-18"])
    }
}
