import XCTest
@testable import WorkoutCore

final class Routes31Tests: XCTestCase {
    func testOutdoorTypesAndTheirSport() {
        XCTAssertEqual(Routes31.sport(ofGarmin: "trail_running"), "run")
        XCTAssertEqual(Routes31.sport(ofGarmin: "gravel_cycling"), "bike")
        XCTAssertEqual(Routes31.sport(ofGarmin: "open_water_swimming"), "swim")
        XCTAssertEqual(Routes31.sport(ofGarmin: "hiking"), "hike")
        for k in ["treadmill_running", "indoor_cycling", "lap_swimming", "strength_training", "virtual_ride"] {
            XCTAssertNil(Routes31.sport(ofGarmin: k), k)
        }
    }

    func testThinKeepsFirstAndLast() {
        let t = (0..<1000).map { GarminCoordinate(lat: Double($0), lon: 0) }
        let thin = Routes31.thin(t)
        XCTAssertEqual(thin.count, 400)
        XCTAssertEqual(thin.first, t.first)
        XCTAssertEqual(thin.last, t.last)
        XCTAssertEqual(Routes31.thin(Array(t.prefix(5))).count, 5)
    }

    func testMonthsAndRegion() {
        XCTAssertEqual(Routes31.lastDay("2028-02"), "2028-02-29")
        XCTAssertEqual(Routes31.shift("2026-01", by: -1), "2025-12")
        XCTAssertEqual(Routes31.shift("2026-11", by: 2), "2027-01")
        XCTAssertEqual(Routes31.monthTitle("2026-11"), "November 2026")
        let r = Routes31.region(of: [[GarminCoordinate(lat: 1, lon: 2)], [GarminCoordinate(lat: 3, lon: -1)]])
        XCTAssertEqual(r, Routes31.Region(minLat: 1, maxLat: 3, minLon: -1, maxLon: 2))
        XCTAssertNil(Routes31.region(of: []))
    }

    /* 2.19.3: one far-away route does not decide the frame. Invented places only. */
    func testTheFrameFollowsTheUsualArea() {
        func loop(_ lat: Double, _ lon: Double) -> [GarminCoordinate] {
            (0..<10).map { GarminCoordinate(lat: lat + 0.005 * sin(Double($0)), lon: lon + 0.005 * cos(Double($0))) }
        }
        let home = [loop(47.00, 8.00), loop(47.02, 8.03), loop(46.99, 7.98), loop(47.01, 8.01)]
        let far = loop(47.45, 8.00)                       // about 50 km north
        let framed = Routes31.focus(home + [far])
        XCTAssertEqual(framed.count, 4, "the far route is left out of the frame")
        XCTAssertEqual(Routes31.focus([loop(47, 8), far]).count, 2, "too few to tell: all")
    }
}
