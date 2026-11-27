import XCTest
@testable import WorkoutCore

/* 2.20: the Progress navigation's words and rules, and the quicker retry after a Garmin read failed. */
final class ProgressNav220Tests: XCTestCase {

    func testFiguresAndActivePart() {
        XCTAssertEqual(ProgressNav.Part.allCases.map(\.name), ["Race", "Fitness", "Load", "Zones", "Routes", "Kept", "Bests", "Month"])
        XCTAssertEqual(ProgressNav.raceFigure(daysToGo: 230, weeksToGo: 33), "33 weeks")
        XCTAssertEqual(ProgressNav.raceFigure(daysToGo: 12, weeksToGo: 2), "12 days")
        XCTAssertEqual(ProgressNav.raceFigure(daysToGo: 1, weeksToGo: 0), "1 day")
        XCTAssertEqual(ProgressNav.raceFigure(daysToGo: 0, weeksToGo: 0), "Today")
        XCTAssertEqual(ProgressNav.raceFigure(daysToGo: -3, weeksToGo: 0), "—")
        XCTAssertEqual(ProgressNav.monthName("2026-10"), "October")
        XCTAssertEqual(ProgressNav.monthShort("2026-11"), "Nov")
        // Nothing has reached the line yet; then the lowest top at or above it wins, in two columns too.
        XCTAssertNil(ProgressNav.active(tops: [.race: 140, .fitness: 600], line: 90))
        XCTAssertEqual(ProgressNav.active(tops: [.race: -400, .fitness: 40, .load: 80, .zones: 300], line: 90), .load)
        XCTAssertEqual(ProgressNav.active(tops: [.fitness: 20, .kept: 20], line: 90), .kept)
    }

    func testFailedReadRetriesSooner() {
        let tried = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(GarminMorning.mayRead(lastTried: tried, failed: false, now: tried.addingTimeInterval(3 * 60)))
        XCTAssertTrue(GarminMorning.mayRead(lastTried: tried, failed: true, now: tried.addingTimeInterval(3 * 60)))
        XCTAssertFalse(GarminMorning.mayRead(lastTried: tried, failed: true, now: tried.addingTimeInterval(60)))
        XCTAssertTrue(GarminMorning.mayRead(lastTried: nil, failed: true, now: tried))
    }
}
