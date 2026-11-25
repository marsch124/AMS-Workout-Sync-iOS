import XCTest
@testable import WorkoutCore

/* Round 28, pick 37: kilometres are the starting figure plus logged distance while in use. All numbers invented. */
final class GearTests: XCTestCase {
    private let runs = [
        GearSession(day: "2027-03-02", sport: "run", km: 10),
        GearSession(day: "2027-03-09", sport: "run", km: 12),
        GearSession(day: "2027-03-12", sport: "run", km: nil),      // no distance logged
        GearSession(day: "2027-03-16", sport: "run", km: 8),
        GearSession(day: "2027-03-16", sport: "bike", km: 40),     // another sport
    ]

    func testAShoeCountsOnlyItsSportFromItsDayAndSaysWhatWasLeftOut() {
        let shoe = GearItem(name: "Blue", kind: .shoes, since: "2027-03-05", startKm: 100, limitKm: 700)
        let c = shoe.count(runs)
        XCTAssertEqual(c.km, 100 + 12 + 8)            // the 2 March run was before the date
        XCTAssertEqual(c.sessions, 3); XCTAssertEqual(c.withoutDistance, 1)
        XCTAssertEqual(shoe.countWords(c), "3 runs, 1 without a distance")
    }

    func testSwitchingTheShoeInUseMidMonthSplitsTheRuns() {
        let a = GearItem(id: "a", name: "Blue", kind: .shoes, since: "2027-03-01", startKm: 50)
        let b = GearItem(id: "b", name: "Red", kind: .shoes, startKm: 0)
        let bike = GearItem(id: "k", name: "Road", kind: .bike, since: "2027-03-01")
        var items = GearSet.using("b", from: "2027-03-10", in: [a, b, bike])
        XCTAssertFalse(items[0].inUse); XCTAssertTrue(items[1].inUse); XCTAssertTrue(items[2].inUse, "another kind is untouched")
        XCTAssertEqual(items[0].count(runs).km, 50 + 10 + 12)   // 2 and 9 March
        XCTAssertEqual(items[1].count(runs).km, 8)              // 16 March; the 12th had no distance and was the other's
        XCTAssertEqual(items[2].count(runs).km, 40, "the ride counts for the bike")
        // back to the first one: both stretches count
        items = GearSet.using("a", from: "2027-03-15", in: items)
        XCTAssertEqual(items[0].count(runs).km, 50 + 10 + 12 + 8)
        XCTAssertEqual(items[1].count(runs).km, 0)
        // switching on the day it began leaves no empty stretch
        let once = GearSet.using("b", from: "2027-03-15", in: items)
        XCTAssertEqual(once[0].periods.count, 1)
    }

    func testARetiredShoeKeepsItsFinalFigure() {
        let a = GearItem(id: "a", name: "Blue", kind: .shoes, since: "2027-03-01", startKm: 50)
        let items = GearSet.retired("a", on: "2027-03-10", in: [a], sessions: runs)
        XCTAssertTrue(items[0].retired); XCTAssertFalse(items[0].inUse)
        XCTAssertEqual(items[0].finalKm, 72)
        // runs logged later change nothing
        let later = runs + [GearSession(day: "2027-03-20", sport: "run", km: 30)]
        XCTAssertEqual(items[0].count(later).km, 72)
        XCTAssertEqual(GearSet.using("a", from: "2027-03-20", in: items)[0].retired, true, "a retired one is not brought back")
    }

    func testTolerantReadingAndOtherCountsNothing() throws {
        let g = try JSONDecoder().decode(GearItem.self, from: Data(#"{"name":"Old","kind":"scooter","limitKm":0}"#.utf8))
        XCTAssertEqual(g.kind, .other); XCTAssertNil(g.limitKm)
        XCTAssertEqual(g.count(runs).km, 0)
        XCTAssertEqual(g.countWords(g.count(runs)), "Counts only the kilometres you gave it")
    }
}
