import XCTest
@testable import WorkoutCore

final class Workouts29Tests: XCTestCase {
    private func a(_ id: Int, _ type: String, _ local: String, gmt: String, secs: Double, dist: Double? = nil, hr: Double? = nil) -> [String: Any] {
        var d: [String: Any] = ["activityId": id, "activityName": "Sample \(id)", "activityType": ["typeKey": type],
                                "startTimeLocal": local, "startTimeGMT": gmt, "duration": secs]
        if let dist { d["distance"] = dist }
        if let hr { d["averageHR"] = hr }
        return d
    }

    func testMonthTotalsAndNewestFirst() {
        let json: [[String: Any]] = [
            a(1, "running", "2026-11-03 07:00:00", gmt: "2026-11-03T06:00:00.0", secs: 3600, dist: 10000, hr: 150),
            a(2, "walking", "2026-11-25 18:12:00", gmt: "2026-11-25T17:12:00.0", secs: 1800, dist: 2500),
            a(3, "breathwork", "2026-10-30 08:00:00", gmt: "2026-10-30T07:00:00.0", secs: 600),
        ]
        let all = MonthWorkouts.parse(json)
        XCTAssertEqual(all.count, 3)
        let month = MonthWorkouts.ofMonth(all, day: "2026-11-25")
        XCTAssertEqual(month.map(\.id), ["2", "1"])
        XCTAssertEqual(month[0].time, "18:12")
        XCTAssertEqual(MonthWorkouts.totalsLine(month), "1h\u{00A0}30m · 12.5 km")
        XCTAssertEqual(MonthWorkouts.whenText(month[0]), "Wed 25 · 18:12")
        XCTAssertNil(MonthWorkouts.colourSport("walking"))
        XCTAssertEqual(MonthWorkouts.colourSport("lap_swimming"), "swim")
        XCTAssertEqual(MonthWorkouts.monthName("2026-11-25"), "NOVEMBER")
    }

    func testADaysWorkoutsComeEarliestFirst() {
        let json: [[String: Any]] = [
            a(1, "running", "2026-11-25 18:00:00", gmt: "2026-11-25T17:00:00.0", secs: 600),
            a(2, "walking", "2026-11-25 07:00:00", gmt: "2026-11-25T06:00:00.0", secs: 600),
            a(3, "cycling", "2026-11-24 12:00:00", gmt: "2026-11-24T11:00:00.0", secs: 600),
        ]
        let day = MonthWorkouts.ofDay(MonthWorkouts.parse(json), day: "2026-11-25")
        XCTAssertEqual(day.map(\.id), ["2", "1"])
        XCTAssertEqual(MonthWorkouts.asBodyWorkout(day[0]).type, "walking")
        XCTAssertNil(MonthWorkouts.asBodyWorkout(day[0]).drain)
    }
}
