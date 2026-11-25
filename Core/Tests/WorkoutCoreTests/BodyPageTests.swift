import XCTest
@testable import WorkoutCore

/* The Body page's words, on invented numbers. */
final class BodyPageTests: XCTestCase {
    private func days(_ v: [Double?]) -> [BodyDay.DayValue] {
        v.enumerated().map { BodyDay.DayValue(day: "2026-09-\(10 + $0.offset)", value: $0.element) }
    }

    private func at(_ h: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + h * 3600) }

    func testTheTilesSayWhatTheyShow() {
        let b = BodyDay(day: "2026-09-16", readAt: at(17),
                        sleep: .init(lastNight: 6.17, nights: days([5, 6, nil, 6, 6, 6, 6.17])),
                        hrv: .init(lastNight: 48.4, rangeLow: 42, rangeHigh: 55, days: days([44, 51, nil, 46, 49, 45, 48])),
                        resting: .init(today: 52, normal: 51.2, days: days([51, 50, 52, 53, 51, 52, 52])),
                        stress: .init(average: 31, highest: 74, days: days([28, 35, 41, 26, 30, 38, 31])))
        let sleep = BodyPage.tile(.sleep, b)
        XCTAssertEqual(sleep.figure, "6h\u{00A0}10m")
        XCTAssertTrue(sleep.note.hasPrefix("7-night average 5h"), sleep.note)   // the night without a reading is left out
        XCTAssertEqual(BodyPage.tile(.hrv, b).figure, "48")
        XCTAssertEqual(BodyPage.tile(.hrv, b).note, "your normal 42–55")
        XCTAssertEqual(BodyPage.tile(.resting, b).note, "your normal 51")
        XCTAssertEqual(BodyPage.tile(.stress, b).note, "highest today 74")
        // Newest first, and a day without a reading has no value rather than a zero.
        let rows = BodyPage.rows(.hrv, b)
        XCTAssertEqual(rows.first?.value, "48 ms")
        XCTAssertNil(rows[4].value)
    }

    func testNoNormalYetIsSaidPlainly() {
        let b = BodyDay(day: "2026-09-16", readAt: at(8), hrv: .init(lastNight: 50, stillLearning: true))
        XCTAssertEqual(BodyPage.tile(.hrv, b).note, "still learning your normal")
        // Nothing at all: a dash, no unit, no crash.
        let empty = BodyPage.tile(.resting, BodyDay(day: "2026-09-16", readAt: at(8)))
        XCTAssertEqual(empty.figure, "–")
        XCTAssertEqual(empty.unit, "")
    }

    func testWorkoutsOnTheCurve() {
        let run = BodyDay.Workout(id: "1", name: "Lunch Running", type: "trail_running", start: at(8), end: at(9), drain: 17.6)
        let swim = BodyDay.Workout(id: "2", name: "Pool", type: "lap_swimming", start: at(12), end: at(13), drain: 9)
        let unknown = BodyDay.Workout(id: "3", name: "Padel evening", type: "other", start: at(18), end: at(19), drain: nil)
        XCTAssertEqual(BodyPage.label(run), "Run −18")
        XCTAssertEqual(BodyPage.label(unknown), "Padel")
        // Only the workouts with a known cost are counted.
        let b = BodyDay.Battery(points: [], workouts: [run, swim, unknown])
        XCTAssertEqual(BodyPage.workoutsLine(b), "2 workouts took 27")
        XCTAssertNil(BodyPage.workoutsLine(.init(points: [], workouts: [unknown])))
    }

    func testBarsLeaveAGapWhereThereIsNoReading() {
        let h = BodyPage.bars(days([47, nil, 52, .infinity, 47]))
        XCTAssertEqual(h.count, 5)
        XCTAssertNil(h[1])
        XCTAssertNil(h[3])
        XCTAssertEqual(h[2], 1)
        XCTAssertLessThan(h[0]!, 1)
        XCTAssertGreaterThanOrEqual(h[0]!, 0.15)
        XCTAssertEqual(BodyPage.bars(days([nil, nil])), [nil, nil])
    }
}
