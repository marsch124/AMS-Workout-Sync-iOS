import XCTest
@testable import WorkoutCore

/*
 * The twelve worked examples of the rule book's specification, rebuilt on an
 * invented plan of the same shape (same weekday pattern, week kinds and
 * ratios; different dates, titles and minutes). Each must end the same way:
 * silent, or the card with the right move. And the whole stretch together
 * gives three cards — all "easier", none from sleep.
 */
final class RuleBookExampleTests: XCTestCase {

    let d = Fixture.day

    /* Eleven weeks shaped like the real autumn, plus the easy week after. */
    func season() -> Fixture {
        var f = Fixture.standard(longRides: [1: 80, 2: 85, 3: 90, 6: 100, 7: 110, 9: 115, 10: 120, 11: 125, 13: 130],
                                longRuns: [9: 65, 10: 70])
        f.sessions[f.index(f.id(11, "Steady easy run"))].plannedMin = 50
        f.sessions[f.index(f.id(11, "Long run"))].plannedMin = 75
        f.allDone(before: d(12, 3))
        f.done(f.id(8, "Reduced long ride"), 35)
        f.done(f.id(9, "Long ride"), 75)
        f.done(f.id(10, "Long ride"), 85)
        // Week 10: three long hikes from the watch, about twice the plan.
        for wd in [1, 3, 5] { f.extras.append(RBExtra(day: d(10, wd), activity: "hike", minutes: 150, countsAsTraining: false)) }
        // Week 11: the Thursday easy run moved to Monday; the swim moved to Friday and missed;
        // Sunday's ride cut short and hard; the Saturday long run moved into the easy week, not done.
        f.move(f.id(11, "Steady easy run"), to: d(11, 0))
        f.move(f.id(11, "Drill swim"), to: d(11, 4)); f.missed(f.id(11, "Drill swim"))
        f.done(f.id(11, "Long ride"), 95, rpe: 7)
        let longRun = f.id(11, "Long run")
        f.move(longRun, to: d(12, 2))
        f.sessions[f.index(longRun)].status = .open; f.sessions[f.index(longRun)].actualMin = nil
        // Week 12 (easy): the Thursday run ticked a day early, and it felt hard.
        f.done(f.id(12, "Short shakeout run"), 35, rpe: 6)
        for s in f.sessions where s.day >= d(12, 2) && s.id != f.id(12, "Short shakeout run") && !s.isRest {
            f.sessions[f.index(s.id)].status = .open; f.sessions[f.index(s.id)].actualMin = nil
        }
        f.importDay = d(12, 2)
        return f
    }

    func testTheWholeSeasonGivesThreeCards() {
        let cards = season().cards(from: d(1, 2), to: d(12, 3))
        XCTAssertEqual(cards.map(\.trigger), [.t5, .t4, .cameInBreaking])
        XCTAssertEqual(cards.map(\.record.day), [d(11, 0), d(11, 5), d(12, 2)])
        XCTAssertTrue(cards.allSatisfy { $0.footer == RuleBookWords.footer })
    }

    // 1 · three tests on three days running in a test week: nothing (L2 only stops NEW pairs).
    func testExample1TestsInARow() {
        var f = Fixture.standard()
        f.allDone(before: d(6, 0))
        XCTAssertEqual(f.cards(from: d(5, 0), to: d(5, 6)).count, 0)
        // The tests themselves never block easing something else in their week.
        let easier = RuleBook.check(.makeEasier(session: f.id(5, "Recovery jog"), instead: nil), for: .t1, input: Fixture.standard().input(d(5, 0)))
        XCTAssertFalse(limits(easier).contains(.l2))
        XCTAssertFalse(limits(easier).contains(.l6))
    }

    // 2 · an easy run moved onto the Friday rest day by his own hand: no card, one grey line at the move.
    func testExample2HisOwnFridayMove() {
        var f = Fixture.standard()
        let before = f.input(d(5, 3)).sessions
        f.move(f.id(5, "Recovery jog"), to: d(5, 4))
        XCTAssertEqual(RuleBook.warnings(before: before, after: f.input(d(5, 3)).sessions, input: f.input(d(5, 3))),
                       ["Friday is your rest day. Move anyway?"])
        f.allDone(before: d(6, 0))
        XCTAssertEqual(f.cards(from: d(5, 3), to: d(6, 0)).count, 0)
    }

    // 3 · easy week, the reduced long ride done longer than planned: nothing.
    func testExample3MoreThanPlannedInAnEasyWeek() {
        var f = Fixture.standard()
        f.allDone(before: d(5, 2))
        f.done(f.id(4, "Reduced long ride"), 95)
        XCTAssertEqual(f.cards(from: d(4, 6), to: d(5, 1)).count, 0)
    }

    // 4 · the key strength session missed (one day): nothing; the session says "gone".
    func testExample4OneMissedKey() {
        var f = Fixture.standard()
        f.move(f.id(6, "Strength A"), to: d(6, 6))
        f.allDone(before: d(7, 3))
        f.sessions[f.index(f.id(6, "Strength A"))].status = .missed
        XCTAssertEqual(f.cards(from: d(6, 6), to: d(7, 2)).count, 0)
        XCTAssertEqual(RuleBookWords.gone, "Gone — no catching up needed.")
    }

    // 5 · bike, run and strength B all on one Tuesday by his moves: nothing.
    func testExample5ThreeOnOneTuesday() {
        var f = Fixture.standard()
        let before = f.input(d(6, 0)).sessions
        f.move(f.id(6, "Run with short"), to: d(6, 1))
        f.move(f.id(6, "Strength B"), to: d(6, 1))
        XCTAssertEqual(RuleBook.warnings(before: before, after: f.input(d(6, 0)).sessions, input: f.input(d(6, 0))), [])
        f.allDone(before: d(7, 0))
        XCTAssertEqual(f.cards(from: d(6, 0), to: d(6, 6)).count, 0)
    }

    // 6 · easy week, one easy swim felt clearly harder: nothing.
    func testExample6OneHardSwimInAnEasyWeek() {
        var f = Fixture.standard()
        f.allDone(before: d(9, 0))
        f.done(f.id(8, "Relaxed drill swim"), 50, rpe: 7)
        XCTAssertEqual(f.cards(from: d(8, 2), to: d(8, 6)).count, 0)
    }

    // 7 · Sunday's long ride a little longer than the longest in 21 days, within its step: nothing.
    func testExample7LongRideWithinItsStep() {
        var f = Fixture.standard(longRides: [7: 104, 9: 110])
        f.allDone(before: d(9, 5))
        f.done(f.id(6, "Long ride"), 104)
        f.done(f.id(8, "Reduced long ride"), 30)
        XCTAssertNil(f.suggest(d(9, 5)))
        XCTAssertEqual(f.input(d(9, 5)).longReference(sport: .bike, before: d(9, 6)), 104)
    }

    // 8 · Monday after a week of hikes about twice the plan: the first in drop order, the easy run, shorter and easy.
    func testExample8BigWeekWithHikes() {
        let card = season().cards(from: d(11, 0), to: d(11, 0)).first
        XCTAssertEqual(card?.trigger, .t5)
        XCTAssertEqual(card?.headline, "Mon run: 50 → 35 min, easy")
        XCTAssertEqual(card?.why, "Why: last week, with the hikes, you trained about twice your planned time.")
    }

    // 9 · Saturday: Sunday's long ride far beyond the longest of the last three weeks → one step above it.
    func testExample9LongRideTooFar() {
        let card = season().cards(from: d(11, 5), to: d(11, 5)).first
        XCTAssertEqual(card?.trigger, .t4)
        XCTAssertEqual(card?.headline, "Sun bike: 125 → 95 min")
        XCTAssertEqual(card?.why, "Why: your longest ride in the last 3 weeks was 85 min; long rides grow a step at a time.")
    }

    // 10 · Friday swim missed, Saturday key long run not logged: nothing — the week is over, so no slot.
    func testExample10GapAtTheEndOfAWeek() {
        var f = Fixture.standard()
        f.allDone(before: d(11, 4))
        f.move(f.id(11, "Drill swim"), to: d(11, 4)); f.missed(f.id(11, "Drill swim"))
        f.done(f.id(11, "Long ride"))
        XCTAssertNil(f.suggest(d(12, 0)))
        f.missed(f.id(11, "Long run"))
        XCTAssertNil(f.suggest(d(12, 0)))
        f.missed(f.id(11, "Long ride"))           // even a three-day gap with two keys finds no slot
        XCTAssertNil(f.suggest(d(12, 0)))
        XCTAssertNil(f.suggest(d(12, 1)))
    }

    // 11 · last week's long run moved into today in the easy week: one card when the plan comes in.
    func testExample11CameInBreakingALimit() {
        let card = season().cards(from: d(12, 2), to: d(12, 2)).first
        XCTAssertEqual(card?.trigger, .cameInBreaking)
        XCTAssertEqual(card?.headline, "Wed run: 75 min long run → rest")
        XCTAssertEqual(card?.why, "Why: it is last week's run; missed sessions are not made up, and this is your easy week.")
        XCTAssertEqual(card?.otherChoices.count, 0)
    }

    // 12 · the Thursday run ticked a day early and felt hard, Sunday's ride too: nothing, then still nothing.
    func testExample12FutureTicksAndAnEasyWeek() {
        var f = season()
        f.importDay = nil
        XCTAssertEqual(f.cards(from: d(12, 2), to: d(12, 3)).count, 0)
        // On Thursday two sessions in 7 days felt harder — but T1 is off in an easy week; the day still counts.
        XCTAssertTrue(f.input(d(12, 3), .evening).isBadSignalDay(d(12, 3)))
        XCTAssertFalse(f.input(d(12, 2), .evening).isBadSignalDay(d(12, 3)))
    }
}
