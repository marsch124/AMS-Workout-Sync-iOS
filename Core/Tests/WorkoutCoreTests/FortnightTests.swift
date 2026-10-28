import XCTest
@testable import WorkoutCore

/*
 * The resting heart rate on Today and the normal it is held against. Before
 * 28 October 2026 the normal averaged every reading Health held, this
 * morning's included, so a day held twice counted twice and the morning was
 * partly measured against itself.
 */
final class FortnightTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }()

    /* Seven in the morning, a number of days before 28 October 2026. */
    private func morning(_ daysAgo: Int, hour: Int = 7) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: hour))!
        return calendar.date(byAdding: .day, value: -daysAgo, to: day)!
    }

    private var now: Date { morning(0, hour: 9) }

    private func sample(_ daysAgo: Int, _ value: Double, hour: Int = 7) -> Fortnight.Sample {
        Fortnight.Sample(end: morning(daysAgo, hour: hour), value: value)
    }

    func testThisMorningAgainstTheDaysBefore() {
        let r = Fortnight.reading([sample(0, 46), sample(1, 50), sample(2, 52), sample(3, 50), sample(4, 48)],
                                  now: now, calendar: calendar)
        XCTAssertEqual(r.latest, 46)
        XCTAssertEqual(r.normal, 50, "the four days before, not this morning as well")
        XCTAssertEqual(r.days, 4)
    }

    /* A day Health holds twice is still one day. */
    func testADayHeldTwiceCountsOnce() {
        let r = Fortnight.reading([sample(0, 48), sample(1, 60), sample(1, 60), sample(1, 60),
                                   sample(2, 50), sample(3, 50), sample(4, 50)],
                                  now: now, calendar: calendar)
        XCTAssertEqual(r.normal!, 52.5, accuracy: 0.001, "60 once beside three fifties")
    }

    /* Garmin writes a day again as it goes on: the last word for a day stands. */
    func testTheLastReadingOfADayStands() {
        let r = Fortnight.reading([sample(0, 55, hour: 6), sample(0, 48, hour: 8),
                                   sample(1, 50), sample(2, 50), sample(3, 50), sample(4, 50)],
                                  now: now, calendar: calendar)
        XCTAssertEqual(r.latest, 48)
    }

    /* Two or three days are not a normal; a trend made from them would be invented. */
    func testNoNormalUntilThereAreEnoughDays() {
        let r = Fortnight.reading([sample(0, 48), sample(1, 52), sample(2, 50)], now: now, calendar: calendar)
        XCTAssertEqual(r.latest, 48)
        XCTAssertNil(r.normal)
        XCTAssertEqual(r.days, 2)
    }

    /* Nothing yet this morning: yesterday's reading is still last night's news. */
    func testYesterdayStandsUntilTodayArrives() {
        let r = Fortnight.reading([sample(1, 47), sample(2, 50), sample(3, 50), sample(4, 50), sample(5, 50)],
                                  now: now, calendar: calendar)
        XCTAssertEqual(r.latest, 47)
        XCTAssertEqual(r.normal, 50)
    }

    func testAnOldReadingIsNotThisMorning() {
        let r = Fortnight.reading([sample(3, 47), sample(4, 50), sample(5, 50), sample(6, 50), sample(7, 50)],
                                  now: now, calendar: calendar)
        XCTAssertNil(r.latest)
    }

    /* At most the fortnight before the morning shown. */
    func testOlderThanAFortnightIsLeftOut() {
        let r = Fortnight.reading([sample(0, 48), sample(1, 50), sample(2, 50), sample(3, 50), sample(4, 50),
                                   sample(20, 90)],
                                  now: now, calendar: calendar)
        XCTAssertEqual(r.normal, 50)
        XCTAssertEqual(r.days, 4)
    }
}
