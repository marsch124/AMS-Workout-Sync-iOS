import XCTest
@testable import WorkoutCore

/*
 * Last night's sleep on Today. His 5h 20m read 10h 40m on 27 October 2026:
 * the same night reached Health twice and every piece was added up. These
 * pin the counting to nights that can be checked on a clock.
 */
final class SleepTests: XCTestCase {

    private let garmin = "com.garmin.connect.mobile"
    private let watch = "com.apple.health.watch"

    /* 23:00 on the evening before plus a number of minutes. */
    private func at(_ minutes: Double) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(minutes * 60)
    }

    private func span(_ source: String, _ from: Double, _ to: Double) -> Sleep.Span {
        Sleep.Span(source: source, start: at(from), end: at(to))
    }

    private func hours(_ spans: [Sleep.Span]) -> Double? {
        Sleep.asleepSeconds(spans).map { $0 / 3600 }
    }

    func testOneNightIsItsOwnLength() {
        XCTAssertEqual(hours([span(garmin, 0, 320)])!, 320.0 / 60, accuracy: 0.001)
    }

    /* The bug as he saw it: the same night handed over twice. */
    func testTheSameNightTwiceCountsOnce() {
        let night = [span(garmin, 0, 90), span(garmin, 90, 200), span(garmin, 200, 320)]
        XCTAssertEqual(hours(night + night)!, 320.0 / 60, accuracy: 0.001, "5h 20m, not 10h 40m")
    }

    /* Phases inside a plain "asleep" that covers the whole night. */
    func testPhasesInsideAWholeNightCountOnce() {
        let spans = [span(garmin, 0, 320), span(garmin, 0, 100), span(garmin, 100, 180), span(garmin, 180, 320)]
        XCTAssertEqual(hours(spans)!, 320.0 / 60, accuracy: 0.001)
    }

    /* Lying awake in the middle of the night is not sleep. */
    func testAWakingStaysOut() {
        let spans = [span(garmin, 0, 180), span(garmin, 210, 360)]
        XCTAssertEqual(hours(spans)!, 330.0 / 60, accuracy: 0.001, "6 h in bed less half an hour awake")
    }

    /* Garmin and a watch both worn to bed: two opinions of one night, never two nights. */
    func testTwoDevicesAreNotAddedTogether() {
        let spans = [span(garmin, 0, 320), span(watch, 10, 310)]
        XCTAssertEqual(hours(spans)!, 320.0 / 60, accuracy: 0.001, "the fuller of the two, whole")
    }

    func testNothingRecordedIsNothing() {
        XCTAssertNil(Sleep.asleepSeconds([]))
        XCTAssertNil(Sleep.asleepSeconds([span(garmin, 60, 60)]), "a piece with no length is not sleep")
    }
}
