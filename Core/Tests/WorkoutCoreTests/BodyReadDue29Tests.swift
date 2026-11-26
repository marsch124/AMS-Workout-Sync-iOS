import XCTest
@testable import WorkoutCore

final class BodyReadDue29Tests: XCTestCase {
    private func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = GarminMorning.calendar().timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    func testANewDayReadsAtOnceButOnlyOnce() {
        // Tried 23:50, now 00:05 with yesterday's numbers: read at once.
        XCTAssertTrue(GarminMorning.bodyReadDue(lastTried: at("2030-03-04 23:50"), heldDay: "2030-03-04", now: at("2030-03-05 00:05")))
        // Already tried at 00:05 today and Garmin answered empty: wait the half hour again.
        XCTAssertFalse(GarminMorning.bodyReadDue(lastTried: at("2030-03-05 00:05"), heldDay: "2030-03-04", now: at("2030-03-05 00:10")))
        // Same day, ten minutes after a read: not due.
        XCTAssertFalse(GarminMorning.bodyReadDue(lastTried: at("2030-03-05 09:00"), heldDay: "2030-03-05", now: at("2030-03-05 09:10")))
        // Half an hour later: due as before.
        XCTAssertTrue(GarminMorning.bodyReadDue(lastTried: at("2030-03-05 09:00"), heldDay: "2030-03-05", now: at("2030-03-05 09:31")))
    }
}
