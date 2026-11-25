import XCTest
@testable import WorkoutCore

/*
 * Claude's pick on the card: off or invalid means the rule book's own pick
 * stays, a valid answer swaps in the chosen item of the same menu, and an
 * answer for a card that has moved on is dropped. Invented plans only.
 */
final class ClaudeWiringTests: XCTestCase {
    private let day = "2027-03-02"

    private func card() -> SuggestionEntry {
        let r = SuggestionRecord(day: day, trigger: .section5, step: 0, key: "k", headline: "Shorten the ride", why: "Why: a tired week.",
                                 choices: [[.shorten(session: "a", minutes: 40)], [.drop(session: "a")], [.makeEasier(session: "a", instead: nil)]],
                                 tried: [], sessions: ["a"], closesOn: day)
        return SuggestionEntry(record: r, otherHeadlines: ["Rest instead", "Ride it easy"])
    }

    private func keep(_ e: SuggestionEntry) -> SuggestionKeep {
        var k = SuggestionKeep(); k.entries = [e]; return k
    }

    func testNoAnswerKeepsTheRuleBooksPick() {
        let e = card()
        var k = keep(e)
        XCTAssertFalse(k.applyClaude(nil, to: e, on: day), "switched off, capped or failed: no answer")
        XCTAssertEqual(k.entries[0], e)
    }

    func testAnInvalidAnswerKeepsTheRuleBooksPick() {
        let e = card()
        for bad in [ClaudeAnswer(pick: 4, why: "Why: fine."),
                    ClaudeAnswer(pick: -1, why: "Why: fine."),
                    ClaudeAnswer(pick: 2, why: "Why: see a doctor."),
                    ClaudeAnswer(pick: 2, why: String(repeating: "x", count: 400)),
                    ClaudeAnswer(pick: 2, why: "  "),
                    ClaudeAnswer(pick: 0, why: "Why: keep it.")] {
            var k = keep(e)
            XCTAssertFalse(k.applyClaude(bad, to: e, on: day), "\(bad)")
            XCTAssertEqual(k.entries[0], e)
        }
    }

    func testAValidAnswerTakesTheChosenItemOfTheSameMenu() throws {
        let e = card()
        var k = keep(e)
        XCTAssertTrue(k.applyClaude(ClaudeAnswer(pick: 3, why: "Why: an easy ride keeps the rhythm."), to: e, on: day))
        let c = k.entries[0]
        XCTAssertEqual(c.headline, "Ride it easy")
        XCTAssertEqual(c.why, "Why: an easy ride keeps the rhythm.")
        XCTAssertEqual(c.record.choices.first, [.makeEasier(session: "a", instead: nil)])
        XCTAssertEqual(c.otherHeadlines, ["Shorten the ride", "Rest instead"])
        XCTAssertEqual(c.record.choices.count, 3, "the menu is the same size")
        XCTAssertEqual(c.id, e.id)
        XCTAssertTrue(c.claudePicked)
        XCTAssertNil(c.record.answer)
        // Pick 1 is the rule book's own: only the reason is Claude's.
        var j = keep(e)
        XCTAssertTrue(j.applyClaude(ClaudeAnswer(pick: 1, why: "Why: a shorter ride suits a tired week."), to: e, on: day))
        XCTAssertEqual(j.entries[0].headline, "Shorten the ride")
        XCTAssertEqual(j.entries[0].record.choices, e.record.choices)
    }

    func testAStaleCardDropsTheAnswer() {
        let e = card()
        let answer = ClaudeAnswer(pick: 2, why: "Why: rest helps.")
        var answered = keep(e)
        answered.answer(e.id, .keptPlan, on: day)
        XCTAssertFalse(answered.applyClaude(answer, to: e, on: day), "answered meanwhile")
        var other = keep(e)
        other.entries[0] = SuggestionEntry(record: SuggestionRecord(day: day, trigger: .section5, step: 0, key: "k", headline: "Shorten the ride",
            why: "Why: changed.", choices: e.record.choices, tried: [], sessions: ["a"], closesOn: day), otherHeadlines: e.otherHeadlines)
        XCTAssertFalse(other.applyClaude(answer, to: e, on: day), "the card was made again")
        var gone = SuggestionKeep()
        XCTAssertFalse(gone.applyClaude(answer, to: e, on: day), "the card is gone")
        var late = keep(e)
        XCTAssertFalse(late.applyClaude(answer, to: e, on: "2027-03-03"), "its day is over")
    }

    func testAskedOnceAndNeverForAReview() {
        var k = keep(card())
        XCTAssertNotNil(k.askable(on: day))
        k.markAsked(card().id)
        XCTAssertNil(k.askable(on: day), "never asked twice")
        XCTAssertNil(SuggestionKeep().askable(on: day), "no card, no ask")
    }

    func testTheContextIsBuiltFromThePlanAlone() {
        var f = Fixture.standard()
        f.allDone(before: Fixture.day(2, 2))
        let input = f.input(Fixture.day(2, 2))
        let c = ClaudeContext.make(from: input)
        XCTAssertEqual(c.today, Fixture.day(2, 2))
        XCTAssertEqual(c.ahead.count, 7)
        XCTAssertLessThanOrEqual(c.past.count, 14)
        XCTAssertFalse(c.past.isEmpty)
    }
}
