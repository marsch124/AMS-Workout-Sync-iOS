import XCTest
@testable import WorkoutCore

final class SessionAdviceTests: XCTestCase {
    func testFuelLineOnlyOverNinetyMinutes() {
        XCTAssertNil(SessionAdvice.fuelLine(seconds: 90 * 60, sport: "bike"))
        XCTAssertNotNil(SessionAdvice.fuelLine(seconds: 91 * 60, sport: "bike"))
        XCTAssertNotNil(SessionAdvice.fuelLine(seconds: 120 * 60, sport: "run"))
        XCTAssertNil(SessionAdvice.fuelLine(seconds: nil, sport: "run"))
        XCTAssertNil(SessionAdvice.fuelLine(seconds: 200 * 60, sport: "rest"))
    }

    func testProteinLineOnlyForStrength() {
        XCTAssertNotNil(SessionAdvice.proteinLine(sport: "strength"))
        for s in ["run", "bike", "swim", "mobility", "rest"] { XCTAssertNil(SessionAdvice.proteinLine(sport: s)) }
    }

    func testRepeatWithNamedRecovery() throws {
        let p = try XCTUnwrap(SessionAdvice.intervalSteps(text: "Cruise intervals: 4\u{00D7}6 min at Z4, 2 min jog", sport: "run", totalMinutes: 50))
        XCTAssertEqual(p.repeats, 4)
        XCTAssertEqual(p.steps.map(\.kind), [.warmup, .work, .recovery, .cooldown])
        XCTAssertEqual(p.steps[1].minutes, 6)
        XCTAssertEqual(p.steps[1].target, "Z4")
        XCTAssertEqual(p.steps[2].minutes, 2)
        XCTAssertEqual(p.steps[2].target, "jog")
        // 15 min warm-up would leave 3 for the cool-down, so the 10-minute warm-up: 50 - 10 - 32 = 8.
        XCTAssertEqual(p.steps[0].minutes, 10)
        XCTAssertEqual(p.steps[3].minutes, 8)
    }

    func testBikeBlocksWithAsciiLetters() throws {
        let p = try XCTUnwrap(SessionAdvice.intervalSteps(text: "Trainer sweet spot: 2x12 min at 88-93% FTP, 4 min easy", sport: "bike", totalMinutes: 60))
        XCTAssertEqual(p.repeats, 2)
        XCTAssertEqual(p.steps.map(\.kind), [.warmup, .work, .recovery, .cooldown])
        XCTAssertEqual(p.steps[1].target, "88-93% FTP")
        XCTAssertEqual(p.steps[0].minutes, 15)
        XCTAssertEqual(p.steps[3].minutes, 13)
        XCTAssertEqual(SessionAdvice.garminText(for: p).contains("Cycling"), true)
    }

    func testWrongCardsAreNotShown() {
        let none: [(String, Int?)] = [
            ("4x10 min at Z3; 30 min Z2 tempo", 100),                                   // text after a ;
            ("45 min Z2 then 20 min tempo with 3x10 min at Z4, 2 min easy", 120),        // two sequences
            ("2x20 min at FTP", 90),                                                     // blocks back to back
            ("3x10 min at Z3, 2 min jog", 40),                                           // too little time left
        ]
        for (t, m) in none { XCTAssertNil(SessionAdvice.intervalSteps(text: t, sport: "bike", totalMinutes: m), t) }
        XCTAssertNil(SessionAdvice.intervalSteps(text: "45 min Z2 with 2x10 min at Z4, 2 min easy", sport: "run", totalMinutes: 90))
        XCTAssertNotNil(SessionAdvice.intervalSteps(text: "2x20 min at FTP, easy between", sport: "bike", totalMinutes: 90))
    }

    func testOverUnders() throws {
        let p = try XCTUnwrap(SessionAdvice.intervalSteps(text: "Trainer over-unders: 3\u{00D7}(8 min steady effort / 2 min Z4)", sport: "bike", totalMinutes: 60))
        XCTAssertEqual(p.repeats, 3)
        let inside = p.steps.filter(\.inRepeat)
        XCTAssertEqual(inside.map(\.minutes), [8, 2])
        XCTAssertEqual(inside.map(\.target), ["steady effort", "Z4"])
    }

    func testLeadingEasyMinutesAndWithPrefix() throws {
        let a = try XCTUnwrap(SessionAdvice.intervalSteps(text: "20 min easy + 3\u{00D7}5 min at Z4, 3 min easy", sport: "run", totalMinutes: 50))
        XCTAssertEqual(a.steps[0].minutes, 20)
        XCTAssertEqual(a.steps.last?.minutes, 6)
        let b = try XCTUnwrap(SessionAdvice.intervalSteps(text: "Z2 run with 4\u{00D7}3 min at Z3, jog recoveries", sport: "run", totalMinutes: nil))
        XCTAssertEqual(b.steps[2].kind, .recovery)
        XCTAssertNil(b.steps[2].minutes)
        XCTAssertEqual(b.steps[0].minutes, 10)
        // Recovery length not given: the last step runs until the planned time is up.
        let c = try XCTUnwrap(SessionAdvice.intervalSteps(text: "Z2 run with 4\u{00D7}3 min at Z3, jog recoveries", sport: "run", totalMinutes: 50))
        XCTAssertEqual(c.steps[0].minutes, 15)
        XCTAssertNil(c.steps[2].minutes)
        XCTAssertEqual(c.steps.last?.untilMinutes, 50)
        XCTAssertTrue(SessionAdvice.garminLines(for: c).contains { $0.contains("until the 50 minutes are up") })
    }

    func testNoCardWhenNothingIsLeftForTheCoolDown() {
        // 4 x (10 + 2) = 48 of 50 minutes: even a 10-minute warm-up leaves nothing.
        XCTAssertNil(SessionAdvice.intervalSteps(text: "4x10 min at Z3, 2 min jog", sport: "run", totalMinutes: 50))
    }

    func testGarminLinesAreNumberedAndNameTheRepeat() throws {
        let p = try XCTUnwrap(SessionAdvice.intervalSteps(text: "3x8 min at Z3, 2 min jog", sport: "run", totalMinutes: 45))
        let lines = SessionAdvice.garminLines(for: p)
        XCTAssertTrue(lines[0].hasPrefix("1. "))
        XCTAssertTrue(lines.contains { $0.contains("repeat: 3 times") })
        XCTAssertTrue(SessionAdvice.garminText(for: p).hasSuffix(SessionAdvice.garminTemplateLine))
    }

    func testUnreadableTextsGiveNothing() {
        let texts = [
            "Easy run + 4\u{00D7}20 s strides",                       // seconds
            "Long ride with 2\u{2013}3\u{00D7}30\u{2013}45 min blocks at race effort", // ranges
            "CSS set: 10\u{2013}12\u{00D7}100 at threshold",           // distances, range
            "Trainer: 3\u{00D7}10 min at race watts, last 2 min of each at Z4, 3 min easy between", // extra clause
            "Easy run, conversational the whole way",
            "Z2 run with 4\u{00D7}3 min at Z3 and then some strides", // trailing words
            "3\u{00D7}3 min at Z4",                                    // short efforts, no recovery named
        ]
        for t in texts { XCTAssertNil(SessionAdvice.intervalSteps(text: t, sport: "run", totalMinutes: 50), t) }
        XCTAssertNil(SessionAdvice.intervalSteps(text: "3x8 min at Z3, 2 min jog", sport: "swim", totalMinutes: 50))
        XCTAssertNil(SessionAdvice.intervalSteps(text: "3x8 min at Z3, 2 min jog", sport: "brick", totalMinutes: 50))
    }
}
