import XCTest
@testable import WorkoutCore

/* 2.3: Stop sign and "I'm ill" shared between devices, and Claude's late or off-word answers. Invented days only. */
final class PauseShareTests: XCTestCase {

    private func t(_ s: Double) -> Date { Date(timeIntervalSince1970: s) }

    private func stopped(_ day: String, at: Double) -> PauseShare {
        PauseShare(health: RBHealthTaps(stopSignSince: day), stop: PauseStamp(at: t(at)))
    }

    // MARK: A — newest wins

    func testNewestWinsBetweenTwoPauses() {
        let a = stopped("2030-01-05", at: 100), b = stopped("2030-01-07", at: 200)
        XCTAssertEqual(PauseShare.join(a, b).health.stopSignSince, "2030-01-07")
        XCTAssertEqual(PauseShare.join(b, a).health.stopSignSince, "2030-01-07")
    }

    func testANewerPauseBeatsAnOlderAllClear() {
        let clear = PauseShare(stop: PauseStamp(at: t(50), lifts: t(10)))
        let pause = stopped("2030-01-05", at: 100)
        XCTAssertEqual(PauseShare.join(clear, pause).health.stopSignSince, "2030-01-05")
        XCTAssertEqual(PauseShare.join(pause, clear).health.stopSignSince, "2030-01-05")
    }

    // MARK: A — an older or unaware all clear never lifts a pause

    func testAnOlderAllClearNeverLiftsAPause() {
        let pause = stopped("2030-01-05", at: 100)
        let older = PauseShare(stop: PauseStamp(at: t(90), lifts: t(100)))
        XCTAssertTrue(PauseShare.stopOn(PauseShare.join(older, pause).health))
        XCTAssertTrue(PauseShare.stopOn(PauseShare.join(pause, older).health))
    }

    func testANewerAllClearThatNeverSawThePauseDoesNotLiftIt() {
        // The iPad paused at 100; the iPhone, not knowing, took back its own older pause (from 10) at 150.
        let pause = stopped("2030-01-05", at: 100)
        let unaware = PauseShare(stop: PauseStamp(at: t(150), lifts: t(10)))
        XCTAssertTrue(PauseShare.stopOn(PauseShare.join(unaware, pause).health))
        // A device from before sharing (no stamps) never lifts anything either.
        XCTAssertTrue(PauseShare.stopOn(PauseShare.join(PauseShare(), pause).health))
    }

    func testTheAllClearForThisVeryPauseLiftsIt() {
        let pause = stopped("2030-01-05", at: 100)
        var seen = RBHealthTaps(stopSignSince: "2030-01-05")
        seen.doctorSeenOn = "2030-01-06"
        let lifted = PauseShare.stamped(pause, to: seen, now: t(160))
        XCTAssertEqual(lifted.stop.lifts, t(100))
        XCTAssertFalse(PauseShare.stopOn(PauseShare.join(pause, lifted).health))
        XCTAssertFalse(PauseShare.stopOn(PauseShare.join(lifted, pause).health))
    }

    func testIllnessIsJoinedTheSameWayAndKeepsStillNotRight() {
        let ill = PauseShare(health: RBHealthTaps(illSince: "2030-01-03", illness: .belowNeck, stillNotRight: ["2030-01-10"]),
                             ill: PauseStamp(at: t(100)))
        var free = ill.health
        free.symptomFreeSince = "2030-01-06"
        free.stillNotRight = []
        let newer = PauseShare(health: free, ill: PauseStamp(at: t(120)))
        let joined = PauseShare.join(ill, newer)
        XCTAssertEqual(joined.health.symptomFreeSince, "2030-01-06")
        XCTAssertEqual(joined.health.stillNotRight, ["2030-01-10"])
        // Taken back on a device that never saw this illness: it stays.
        let unaware = PauseShare(ill: PauseStamp(at: t(200), lifts: t(50)))
        XCTAssertEqual(PauseShare.join(unaware, ill).health.illSince, "2030-01-03")
    }

    func testTheFileReadsBackAndAnUnreadableOneIsNeverAllClear() throws {
        let p = stopped("2030-01-05", at: 100)
        XCTAssertEqual(try PauseShare.decoded(p.encoded()), p)
        XCTAssertThrowsError(try PauseShare.decoded(Data(#"{"format":1,"health":{"stopSignSince":5}}"#.utf8)))
    }

    func testTheKeeperStampsATapAndTakesAJoin() {
        var keep = SuggestionKeep()
        let was = keep.pause
        keep.health.stopSignSince = "2030-01-05"
        keep.stampPause(from: was, now: t(300))
        XCTAssertEqual(keep.stopStamp.at, t(300))
        XCTAssertNil(keep.stopStamp.lifts)
        keep.takePause(PauseShare())
        XCTAssertNil(keep.health.stopSignSince)
    }

    // MARK: B — Claude's reason passes the rule book's own word check

    func testClaudesReasonMustPassTheRuleBooksWords() {
        XCTAssertNil(ClaudePick.cleanWhy("Why: an easy ride keeps you healthy."))
        XCTAssertNil(ClaudePick.cleanWhy("Why: it is safe to keep it short."))
        XCTAssertNil(ClaudePick.cleanWhy("Why: you stay fit with less."))
        XCTAssertEqual(ClaudePick.cleanWhy("Why: a shorter ride fits this week."), "Why: a shorter ride fits this week.")
        XCTAssertFalse(ClaudePick.accepts(ClaudeAnswer(pick: 1, why: "Why: it keeps you healthy."), menuCount: 2))
    }

    // MARK: C — one short ask; late or touched answers are dropped

    func testOneShortAskAndLateOrTouchedAnswersAreDropped() {
        XCTAssertEqual(ClaudePick.requestTimeout, 20)
        XCTAssertEqual(ClaudePick.attempts, 1)
        let asked = t(1000)
        XCTAssertTrue(ClaudePick.mayUse(askedAt: asked, now: t(1015), touched: false))
        XCTAssertFalse(ClaudePick.mayUse(askedAt: asked, now: t(1015), touched: true))
        XCTAssertFalse(ClaudePick.mayUse(askedAt: asked, now: t(1030), touched: false))
        XCTAssertFalse(ClaudePick.mayUse(askedAt: asked, now: t(990), touched: false))
    }
}
