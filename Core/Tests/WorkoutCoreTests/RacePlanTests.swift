import XCTest
@testable import WorkoutCore

/* Round 28, pick 25: the race page only adds up what he typed. All numbers are invented. */
final class RacePlanTests: XCTestCase {
    func testFinishAddsOnlyWhatWasTyped() {
        var p = RacePacing()
        XCTAssertNil(p.finish)
        p.set(.swim, 40 * 60); p.set(.t1, 270); p.set(.bike, 3 * 3600 + 10 * 60)
        XCTAssertEqual(p.finish, RacePacing.Finish(seconds: 2400 + 270 + 11400, typed: 3))
        XCTAssertFalse(p.finish!.complete)
        p.set(.t2, 150); p.set(.run, 2 * 3600)
        XCTAssertTrue(p.finish!.complete)
        XCTAssertEqual(p.finish!.seconds, 2400 + 270 + 11400 + 150 + 7200)
        XCTAssertEqual(formatDuration(Double(p.finish!.seconds)), "5h\u{00A0}57m")
        p.set(.swim, nil)
        XCTAssertEqual(p.finish?.typed, 4)
    }

    func testTimesAreReadFromWhatHeTypes() {
        XCTAssertEqual(RacePacing.parse("1:10", changeOver: false), 4200)
        XCTAssertEqual(RacePacing.parse("1h 10m", changeOver: false), 4200)
        XCTAssertEqual(RacePacing.parse("70", changeOver: false), 4200)
        XCTAssertEqual(RacePacing.parse("4:30", changeOver: true), 270)
        XCTAssertEqual(RacePacing.parse("4m 30s", changeOver: true), 270)
        XCTAssertEqual(RacePacing.parse("5", changeOver: true), 300)
        XCTAssertNil(RacePacing.parse("", changeOver: false))
        XCTAssertNil(RacePacing.parse("soon", changeOver: false))
        XCTAssertNil(RacePacing.parse("0", changeOver: false))
        XCTAssertEqual(RacePacing.words(270, changeOver: true), "4m\u{00A0}30s")
        XCTAssertEqual(RacePacing.words(4200, changeOver: false), "1h\u{00A0}10m")
    }

    func testCountdownWords() {
        let far = RaceCountdown.make(days: 228, doneDate: "Sun 11 Jul")
        XCTAssertEqual(far.figure, "228 days"); XCTAssertEqual(far.beside, "32 weeks and 4 days")
        XCTAssertEqual(RaceCountdown.make(days: 14, doneDate: "").beside, "2 weeks")
        XCTAssertEqual(RaceCountdown.make(days: 8, doneDate: "").beside, "1 week and 1 day")
        let week = RaceCountdown.make(days: 5, doneDate: "")
        XCTAssertEqual(week.figure, "5 days"); XCTAssertNil(week.beside); XCTAssertEqual(week.phase, .raceWeek)
        XCTAssertEqual(RaceCountdown.make(days: 1, doneDate: "").figure, "1 day")
        XCTAssertEqual(RaceCountdown.make(days: 0, doneDate: "").figure, "Today")
        XCTAssertEqual(RaceCountdown.make(days: -3, doneDate: "Sun 11 Jul").figure, "Done \u{00B7} Sun 11 Jul")
    }

    func testFuelGramsPerLegAndPerHourFromHisTimes() {
        let fuel = RaceFuel(rows: [
            RaceFuelRow(leg: .before, when: "Breakfast", what: "porridge", carbs: 80),
            RaceFuelRow(leg: .bike, when: "every 20 min", what: "1 gel", carbs: 180),
            RaceFuelRow(leg: .bike, when: "hour 2", what: "bar", carbs: 30),
            RaceFuelRow(leg: .run, when: "every 5 km", what: "1 gel", carbs: 66),
        ])
        XCTAssertEqual(fuel.grams(.bike), 210)
        XCTAssertEqual(fuel.grams(.before), 80)
        XCTAssertEqual(fuel.totalGrams, 356)
        var p = RacePacing()
        XCTAssertNil(fuel.gramsPerHour(.bike, pacing: p), "no time typed, no figure")
        p.set(.bike, 3 * 3600); p.set(.run, 2 * 3600)
        XCTAssertEqual(fuel.gramsPerHour(.bike, pacing: p), 70)
        XCTAssertEqual(fuel.gramsPerHour(.run, pacing: p), 33)
        XCTAssertNil(fuel.gramsPerHour(.before, pacing: p))
    }

    func testKitListStartsFullTicksUntickAndMoves() {
        var list = RaceChecklist.starting
        XCTAssertGreaterThanOrEqual(list.items.count, 20)
        XCTAssertEqual(Set(list.items.map(\.id)).count, list.items.count)
        XCTAssertEqual(list.packedCount, 0)
        let first = list.items[0].id, second = list.items[1].id
        list = list.toggled(first).toggled(second)
        XCTAssertEqual(list.packedCount, 2)
        XCTAssertEqual(list.unticked().packedCount, 0)
        let before = list.items.filter { $0.group == .before }
        let moved = RaceOrder.move(before, before[0].id, onto: before[2].id)
        XCTAssertEqual(moved.map(\.id), [before[1].id, before[2].id, before[0].id] + before.dropFirst(3).map(\.id))
        XCTAssertEqual(RaceOrder.move(before, "nobody", onto: before[2].id), before)
    }

    func testTolerantReading() throws {
        // an older value without fields, and a newer one with extras
        let p = try JSONDecoder().decode(RacePacing.self, from: Data(#"{"swim":2400,"later":1}"#.utf8))
        XCTAssertEqual(p.swim, 2400); XCTAssertNil(p.bike)
        let f = try JSONDecoder().decode(RaceFuel.self, from: Data(#"{"rows":[{"carbs":20,"leg":"swim"}]}"#.utf8))
        XCTAssertEqual(f.rows.count, 1); XCTAssertEqual(f.rows[0].leg, .bike)
        let c = try JSONDecoder().decode(RaceChecklist.self, from: Data("{}".utf8))
        XCTAssertTrue(c.items.isEmpty)
    }

    func testDistancesInWordsOnlyWhenThePlanNamesTheKind() {
        XCTAssertEqual(RaceKind.distances(fromTitle: "Race day: half distance triathlon")?[.run], "21.1 km")
        XCTAssertNil(RaceKind.distances(fromTitle: "Race day"))
    }
}
