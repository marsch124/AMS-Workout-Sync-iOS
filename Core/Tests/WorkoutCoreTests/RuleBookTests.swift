import XCTest
@testable import WorkoutCore

/*
 * The rule book: one test per hard limit, one per trigger, the five open
 * questions switched both ways, and what must stay silent. All on an invented
 * plan (RuleBookFixture); the worked examples are in RuleBookExampleTests.
 */
final class RuleBookTests: XCTestCase {

    let d = Fixture.day

    // MARK: classing

    func testClassesFromThePlansOwnWords() {
        func s(_ title: String, _ zone: String, _ sport: RBSport = .bike, star: Bool = false) -> RBSession {
            RBSession(id: "x", day: d(2, 1), sport: sport, title: title, plannedMin: 60, intensity: zone, star: star, originalWeek: 2)
        }
        XCTAssertEqual(RuleBook.sessionClass(s("Trainer sweet spot", "Z3–Z4")), .hard)
        XCTAssertEqual(RuleBook.sessionClass(s("Tempo", "Z3 (70.3 effort)")), .hard)
        XCTAssertEqual(RuleBook.sessionClass(s("Run with reps", "Z2–Z3", .run)), .moderate)
        XCTAssertEqual(RuleBook.sessionClass(s("Easy run", "Z2", .run)), .easy)
        XCTAssertEqual(RuleBook.sessionClass(s("Long ride", "Z2", star: true)), .other)
        XCTAssertEqual(RuleBook.sessionClass(s("Strength A", "RPE 6–7", .strength)), .heavyStrength)
        XCTAssertEqual(RuleBook.sessionClass(s("Strength B", "RPE 6", .strength)), .moderate)
        XCTAssertEqual(RuleBook.sessionClass(s("Light", "RPE 4–5", .strength)), .easy)
        XCTAssertTrue(RuleBook.labels(s("Brick run at race pace", "Z2–Z3", .run, star: true)).brick)
        XCTAssertEqual(RuleBook.expectedEffort(s("Long ride", "Z2")), 5)
        XCTAssertEqual(RuleBook.expectedEffort(s("Easy", "Z1–Z2")), 3)
        XCTAssertEqual(RuleBook.expectedEffort(s("TEST — bike", "Z4–Z5")), 9)
        XCTAssertEqual(RuleBook.roundTo5(7), 5)
        XCTAssertEqual(RuleBook.roundTo5(8), 10)
    }

    func testSlotsFollowRowOrderNotTheDay() {
        var f = Fixture.standard()
        f.move(f.id(2, "Steady easy run"), to: d(2, 0))          // the Thursday run moved to Monday
        let slots = Dictionary(uniqueKeysWithValues: f.input(d(2, 0)).sessions.filter { $0.originalWeek == 2 }.map { ($0.title, $0.slot) })
        XCTAssertEqual(slots["Steady easy run with pickups"], .easyRun)
        XCTAssertEqual(slots["Run with short Z3 reps"], .runQuality)
        XCTAssertEqual(slots["Strength A: main lifts"], .strengthA)
        XCTAssertEqual(slots["Strength B: single leg and core"], .strengthB)
        XCTAssertEqual(slots["Long ride, even pace"], .longRide)
        XCTAssertEqual(slots["Drill swim with pull sets"], .swim)
    }

    // MARK: hard limits, one each

    func testL1FridayIsRest() {
        let f = Fixture.standard()
        let fails = RuleBook.check(.moveToDay(session: f.id(2, "Steady easy run"), day: d(2, 4)), for: .backToBack, input: f.input(d(2, 0)))
        XCTAssertTrue(limits(fails).contains(.l1))
    }

    func testL2NoNewHardPairsButThePlansOwnStay() {
        var f = Fixture()
        f.addWeek(1, .load, Fixture.load(hardBike: true, hardRun: true))   // Tue bike + Wed run: the plan's own pair
        f.addWeek(2, .load, Fixture.load(hardBike: true, hardRun: false))
        // Easing something else in the week with the plan's own pair is fine.
        XCTAssertFalse(limits(RuleBook.check(.makeEasier(session: f.id(1, "Steady easy run"), instead: nil), for: .t1, input: f.input(d(1, 0)))).contains(.l2))
        // A hard run moved next to the hard bike makes a new pair.
        var g = f
        g.sessions[g.index(g.id(2, "Steady easy run"))].intensity = "Z4"
        let fails = RuleBook.check(.moveToDay(session: g.id(2, "Steady easy run"), day: d(2, 2)), for: .backToBack, input: g.input(d(2, 0)))
        XCTAssertTrue(limits(fails).contains(.l2))
    }

    func testL3WeekCap() {
        let f = Fixture.standard()
        // Next week's easy run pulled into this week: this week goes over what it was planned at.
        let fails = RuleBook.check(.moveToDay(session: f.id(3, "Steady easy run"), day: d(2, 3)), for: .backToBack, input: f.input(d(2, 0)))
        XCTAssertTrue(limits(fails).contains(.l3))
    }

    func testL4RampCeiling() {
        var f = Fixture.standard()
        // Three quiet weeks behind: half the plan done.
        for w in 1...3 { for s in f.sessions where s.originalWeek == w && !s.isRest && s.title.hasPrefix("Long") { f.done(s.id) } }
        let input = f.input(d(4, 0))
        let fails = RuleBook.check(.moveToDay(session: f.id(5, "Long ride"), day: d(4, 6)), for: .backToBack, input: input)
        XCTAssertTrue(limits(fails).contains(.l4))
    }

    func testL5LongSessionsOneStepAtATime() {
        var f = Fixture.standard(longRides: [6: 130])
        f.allDone(before: d(6, 0))
        for w in 4...5 { f.done(f.sessions.first { $0.originalWeek == w && $0.sport == .bike && $0.title.contains("ong ride") }!.id, 80) }
        f.done(f.id(3, "Long ride"), 80)
        let fails = RuleBook.check(.moveToDay(session: f.id(6, "Long ride"), day: d(6, 5)), for: .backToBack, input: f.input(d(6, 0)))
        XCTAssertTrue(limits(fails).contains(.l5))
        // Q4 off: no step limit.
        f.settings.longSessionsGrowSlowly = false
        XCTAssertFalse(limits(RuleBook.check(.moveToDay(session: f.id(6, "Long ride"), day: d(6, 5)), for: .backToBack, input: f.input(d(6, 0)))).contains(.l5))
    }

    func testL6ProtectedAndEasyWeeksOnlyGetEasier() {
        let f = Fixture.standard()
        let test = f.id(5, "TEST — threshold run")
        XCTAssertTrue(limits(RuleBook.check(.drop(session: test), for: .t1, input: f.input(d(5, 0)))).contains(.l6))
        XCTAssertTrue(limits(RuleBook.check(.makeEasier(session: test, instead: nil), for: .t1, input: f.input(d(5, 0)))).contains(.l6))
        let easyRun = f.id(4, "Short shakeout run")
        XCTAssertTrue(limits(RuleBook.check(.drop(session: easyRun), for: .t1, input: f.input(d(4, 0)))).contains(.l6))
        XCTAssertFalse(limits(RuleBook.check(.shorten(session: easyRun, minutes: 20), for: .t1, input: f.input(d(4, 0)))).contains(.l6))
    }

    func testL7NothingHarderOrLonger() {
        let f = Fixture.standard()
        let run = f.id(2, "Steady easy run")
        XCTAssertTrue(limits(RuleBook.check(.shorten(session: run, minutes: 60), for: .t5, input: f.input(d(2, 0)))).contains(.l7))
        XCTAssertFalse(limits(RuleBook.check(.shorten(session: run, minutes: 30), for: .t5, input: f.input(d(2, 0)))).contains(.l7))
    }

    func testL8NoMakeUpExceptT2sSwap() {
        var f = Fixture.standard()
        f.missed(f.id(2, "Long run"))
        let fails = RuleBook.check(.moveToDay(session: f.id(2, "Long run"), day: d(3, 0)), for: .backToBack, input: f.input(d(3, 0)))
        XCTAssertTrue(limits(fails).contains(.l8))
        var g = Fixture.standard()
        g.missed(g.id(2, "Run with short"))
        let t2: [Move] = [.moveToDay(session: g.id(2, "Run with short"), day: d(2, 3)), .drop(session: g.id(2, "Steady easy run"))]
        XCTAssertFalse(limits(RuleBook.check(t2, for: .t2, input: g.input(d(2, 3)))).contains(.l8))
    }

    func testL9MondaySwimNeverTwiceRunning() {
        var f = Fixture.standard()
        f.missed(f.id(2, "Drill swim"))
        XCTAssertTrue(limits(RuleBook.check(.drop(session: f.id(3, "Drill swim")), for: .hurts, input: f.input(d(3, 0)))).contains(.l9))
        XCTAssertFalse(limits(RuleBook.check(.makeEasier(session: f.id(3, "Drill swim"), instead: nil), for: .t1, input: f.input(d(3, 0)))).contains(.l9))
    }

    func testL10FortyEightHoursAfterFever() {
        var f = Fixture.standard()
        f.health = RBHealthTaps(illSince: d(2, 0), illness: .belowNeck)
        XCTAssertTrue(limits(RuleBook.check(.makeEasier(session: f.id(2, "Steady easy run"), instead: nil), for: .t1, input: f.input(d(2, 1)))).contains(.l10))
    }

    func testL11Calm() {
        var f = Fixture.standard()
        let move = Move.makeEasier(session: f.id(3, "Steady easy run"), instead: nil)
        func record(_ day: String, closes: String, answer: RBAnswer?) -> SuggestionRecord {
            SuggestionRecord(day: day, trigger: .t4, step: 0, key: day, headline: "", why: "", choices: [], tried: [],
                             sessions: [], closesOn: closes, answer: answer, answeredOn: answer == nil ? nil : day)
        }
        f.log = [record(d(3, 0), closes: d(3, 1), answer: nil)]
        XCTAssertTrue(limits(RuleBook.check(move, for: .t1, input: f.input(d(3, 1)))).contains(.l11))   // one open card
        f.log = [record(d(2, 6), closes: d(2, 6), answer: .keptPlan), record(d(3, 0), closes: d(3, 0), answer: .keptPlan)]
        XCTAssertTrue(limits(RuleBook.check(move, for: .t1, input: f.input(d(3, 1)))).contains(.l11))   // two this week
        f.log = []
        XCTAssertFalse(limits(RuleBook.check(move, for: .t1, input: f.input(d(3, 1)))).contains(.l11))
        f.settings.raceWeek = 3
        XCTAssertTrue(limits(RuleBook.check(move, for: .t1, input: f.input(d(3, 1)))).contains(.l11))   // race week
    }

    func testL12MenuOnly() {
        let f = Fixture.standard()
        // A drop is not on T4's menu: an AI that picks it is refused.
        XCTAssertTrue(limits(RuleBook.check(.drop(session: f.id(2, "Long ride")), for: .t4, input: f.input(d(2, 5)))).contains(.l12))
        XCTAssertTrue(limits(RuleBook.check(.drop(session: "no such session"), for: .t1, input: f.input(d(2, 5)))).contains(.l12))
    }

    func testL13NoDoctorTalk() {
        XCTAssertEqual(RuleBook.l13Words(["Stay fit and healthy"])?.limit, .l13)
        XCTAssertEqual(RuleBook.l13Words(["This is safe for your heart"])?.limit, .l13)
        XCTAssertNil(RuleBook.l13Words([RuleBookWords.footer, RuleBookWords.whyPoorMornings, "It fits the week"]))
        let every = [RuleBookWords.whyHardSessions, RuleBookWords.whyStillTired, RuleBookWords.whyTiredOverWeek,
                     RuleBookWords.whyTwoTiredWeeks, RuleBookWords.whyMissedKey, RuleBookWords.whyBackLong,
                     RuleBookWords.whyHurts, RuleBookWords.whyBackToBack, RuleBookWords.stopSignDoctor]
            + [RBLadder.rest, .easyDays, .cold, .week1, .week2, .back, .outLong].map(RuleBookWords.ladderText)
        XCTAssertNil(RuleBook.l13Words(every))
    }

    func testOwnEditsGetOneCalmLineNeverABlock() {
        let f = Fixture.standard()
        var after = f.input(d(2, 0)).sessions
        after[after.firstIndex { $0.id == f.id(2, "Steady easy run") }!].day = d(2, 4)
        XCTAssertEqual(RuleBook.warnings(before: f.input(d(2, 0)).sessions, after: after, input: f.input(d(2, 0))).first,
                       "Friday is your rest day. Move anyway?")
    }
}
