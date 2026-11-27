import XCTest
@testable import WorkoutCore

/* The gym file's reading rules, on an invented file. */
final class Gym29Tests: XCTestCase {
    private let file = """
    {"app":"x","format":1,"written":"2026-11-25T10:00:00Z","sessions":[
      {"id":"a","date":"2026-11-20","start":"2026-11-20T17:00:00Z","minutes":70,"gym":"Test Gym","feel":"good","machines":2,"sets":6,"liftedKg":3000,
       "bests":["Leg curl"],"entries":[
         {"name":"Leg curl","muscle":"Legs","sets":"30 × 15, 32,5 × 12, 32,5 × 10 kg","setCount":3,"topKg":32.5,"pain":false},
         {"name":"Rower","sets":"20 min · level 5","setCount":1}]},
      {"id":"b","date":"2026-11-23","minutes":82,"sets":6,"liftedKg":2360,"feel":"weird","entries":[
         {"name":"Press","sets":"50 kg × 12, 10","setCount":2,"topKg":50},{"name":"","sets":"x"}]},
      {"date":"not a day","minutes":5},
      {"id":"c","date":"2026-11-10","minutes":-4}
    ]}
    """.data(using: .utf8)!

    func testSessionsAreCheckedAndNewestFirst() {
        let l = GymSessions.parse(file)
        XCTAssertEqual(l.map(\.id), ["b", "a", "c"])
        XCTAssertNil(l[0].feel)                    // an unknown feeling is dropped
        XCTAssertEqual(l[0].entries.count, 1)      // a machine without a name is dropped
        XCTAssertNil(l[2].minutes)                 // a negative number is dropped
        XCTAssertTrue(GymSessions.parse(Data("nope".utf8)).isEmpty)
    }

    func testLinesAndCompare() {
        let l = GymSessions.parse(file)
        let a = l[1]
        XCTAssertEqual(GymSessions.headLine(a), "Fri 20 Nov · Test Gym · 1h\u{00A0}10m")
        XCTAssertEqual(GymSessions.countsLine(a, today: "2026-11-22"), "2 machines · 6 sets · felt good · 2 days ago")
        XCTAssertEqual(GymSessions.compareLine(l[0], a), "vs the one before: +0 sets · +12 min")
        XCTAssertNil(GymSessions.compareLine(l[2], nil))
        // 2.19: the card shows the time as its big figure, then day · gym.
        XCTAssertEqual(GymSessions.timeFigure(a), "1h\u{00A0}10m")
        XCTAssertEqual(GymSessions.dayGymLine(a), "Fri 20 Nov · Test Gym")
        XCTAssertEqual(GymSessions.timeFigure(GymSession(id: "x", date: "2026-11-21")), "\u{2013}")
    }

    func testBestSetPerMachine() {
        let e = GymSessions.parse(file)[1].entries
        XCTAssertEqual(GymSessions.machineLine(e[0]), "Leg curl · best 32.5 kg × 12")
        XCTAssertEqual(GymSessions.machineLine(e[1]), "Rower · 20 min · level 5")
        // 2.19.1: the same line in three parts, so the figure can stand out.
        XCTAssertTrue(GymSessions.machineParts(e[0]) == ("Leg curl", " · best ", "32.5 kg × 12"))
        XCTAssertTrue(GymSessions.machineParts(e[1]) == ("Rower", " · ", "20 min · level 5"))
        XCTAssertEqual(GymSessions.bestSet(GymSessions.parse(file)[0].entries[0]), "50 kg × 12")
        XCTAssertEqual(GymSessions.bestSet(GymEntry(name: "Dips", sets: "BW × 12, BW × 10", setCount: 2)), "BW × 12, BW × 10")
    }

    func testOnDay() {
        XCTAssertEqual(GymSessions.onDay(GymSessions.parse(file), "2026-11-20").map(\.id), ["a"])
    }
}
