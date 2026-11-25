import XCTest
@testable import WorkoutCore

/*
 * Claude's pick on the card: off or invalid means the rule book's own pick
 * stays, a valid answer swaps in the chosen item of the same menu (found by
 * its moves, with its own sessions and closing day), and an answer for a card
 * that has moved on is dropped. Invented plans only.
 */
final class ClaudeWiringTests: XCTestCase {
    let d = Fixture.day

    /* A real card from the engine with two choices touching different sessions (the T5 big week). */
    private func real() throws -> (entry: SuggestionEntry, input: RuleBookInput) {
        var f = Fixture.standard()
        f.allDone(before: d(10, 0))
        for wd in [1, 3, 5] { f.extras.append(RBExtra(day: d(10, wd), activity: "hike", minutes: 150, countsAsTraining: false)) }
        f.allDone(before: d(11, 0))
        let input = f.input(d(11, 0))
        let s = try XCTUnwrap(RuleBook.suggest(input))
        XCTAssertGreaterThanOrEqual(s.otherChoices.count, 1)
        return (SuggestionEntry(s, input: input), input)
    }

    private func keep(_ e: SuggestionEntry) -> SuggestionKeep {
        var k = SuggestionKeep(); k.entries = [e]; return k
    }

    private let fine = "Why: a lighter day after a big week keeps things calm."

    func testNoAnswerKeepsTheRuleBooksPick() throws {
        let (e, input) = try real()
        var k = keep(e)
        XCTAssertFalse(k.applyClaude(nil, to: e, on: input.today, input: input), "switched off, capped or failed: no answer")
        XCTAssertEqual(k.entries[0], e)
    }

    func testAnInvalidAnswerKeepsTheRuleBooksPick() throws {
        let (e, input) = try real()
        for bad in [ClaudeAnswer(pick: 9, why: fine),
                    ClaudeAnswer(pick: -1, why: fine),
                    ClaudeAnswer(pick: 2, why: "Why: see a doctor."),
                    ClaudeAnswer(pick: 2, why: "Why: rest, see [here](https://example.org)."),
                    ClaudeAnswer(pick: 2, why: "Why: **rest** today."),
                    ClaudeAnswer(pick: 2, why: String(repeating: "x", count: 400)),
                    ClaudeAnswer(pick: 2, why: "  "),
                    ClaudeAnswer(pick: 0, why: "Why: keep it.")] {
            var k = keep(e)
            XCTAssertFalse(k.applyClaude(bad, to: e, on: input.today, input: input), "\(bad)")
            XCTAssertEqual(k.entries[0], e)
        }
    }

    /* The known gap: whatever the card shows first is what "Take it" writes, with that move's sessions and day. */
    func testClaudesPickBringsItsOwnSessionsAndClosingDay() throws {
        let (e, input) = try real()
        var k = keep(e)
        XCTAssertTrue(k.applyClaude(ClaudeAnswer(pick: 2, why: fine), to: e, on: input.today, input: input))
        let c = k.entries[0]
        let other = e.record.choices[1]
        XCTAssertEqual(c.headline, e.otherHeadlines[0])
        XCTAssertEqual(c.why, fine)
        XCTAssertEqual(c.record.choices.first, other)
        XCTAssertEqual(c.before.first, e.before[1])
        XCTAssertEqual(c.record.choices.count, e.record.choices.count, "the same menu, nothing added")
        XCTAssertTrue(c.record.choices.allSatisfy { e.record.choices.contains($0) })
        XCTAssertEqual(c.otherHeadlines.first, e.headline)
        XCTAssertEqual(c.id, e.id)
        XCTAssertTrue(c.claudePicked)
        XCTAssertNil(c.record.answer)

        let changed = RuleBook.changedSessions(other, input: input)
        XCTAssertEqual(c.record.sessions, changed.map(\.id))
        XCTAssertNotEqual(c.record.sessions, e.record.sessions, "the two choices touch different sessions")
        XCTAssertEqual(c.record.closesOn, changed.map(\.day).filter { $0 >= input.today }.min())

        // "Take it" (choice 0) writes exactly the shown move, and only its sessions.
        XCTAssertTrue(SuggestionApply.fits(c, choice: 0, input: input))
        let edits = try SuggestionApply.edits(for: try XCTUnwrap(c.record.choice(0)), input: input)
        XCTAssertEqual(Set(edits.map(\.key)), Set(c.record.sessions))

        // The stale check holds for it: its own session changed under it, so it no longer fits.
        var moved = input
        let i = try XCTUnwrap(moved.sessions.firstIndex { $0.id == c.record.sessions[0] })
        moved.sessions[i].plannedMin += 5
        XCTAssertFalse(SuggestionApply.fits(c, choice: 0, input: moved))
    }

    func testPickOneKeepsTheRuleBooksMoveWithClaudesReason() throws {
        let (e, input) = try real()
        var k = keep(e)
        XCTAssertTrue(k.applyClaude(ClaudeAnswer(pick: 1, why: fine), to: e, on: input.today, input: input))
        XCTAssertEqual(k.entries[0].headline, e.headline)
        XCTAssertEqual(k.entries[0].record.choices, e.record.choices)
        XCTAssertEqual(k.entries[0].record.sessions, e.record.sessions)
        XCTAssertEqual(k.entries[0].record.closesOn, e.record.closesOn)
        XCTAssertTrue(k.entries[0].claudePicked)
    }

    /* Found by its moves, never by its place: a menu in another order, or with a foreign item, cannot mislead. */
    func testThePickIsFoundByItsMovesNotItsPlace() throws {
        let (e, input) = try real()
        let reversed = Array(e.record.choices.reversed())
        let c = try XCTUnwrap(e.applyingClaude(ClaudeAnswer(pick: 1, why: fine), menu: reversed, input: input))
        XCTAssertEqual(c.record.choices.first, reversed[0])
        var foreign = e.record.choices
        foreign[1] = [.drop(session: e.record.sessions[0])]
        XCTAssertFalse(e.record.choices.contains(foreign[1]))
        XCTAssertNil(e.applyingClaude(ClaudeAnswer(pick: 2, why: fine), menu: foreign, input: input), "not in the card's menu")
        XCTAssertNil(e.applyingClaude(ClaudeAnswer(pick: 1, why: fine), menu: [e.record.choices[0]], input: input),
                     "a menu of another size")
    }

    func testAStaleCardDropsTheAnswer() throws {
        let (e, input) = try real()
        let answer = ClaudeAnswer(pick: 2, why: fine)
        var answered = keep(e)
        answered.answer(e.id, .keptPlan, on: input.today)
        XCTAssertFalse(answered.applyClaude(answer, to: e, on: input.today, input: input), "answered meanwhile")
        var remade = keep(e)
        remade.entries[0].record = SuggestionRecord(day: e.record.day, trigger: e.record.trigger, step: e.record.step,
            key: e.record.key, headline: e.headline, why: "Why: changed.", choices: e.record.choices, tried: [],
            sessions: e.record.sessions, closesOn: e.record.closesOn)
        XCTAssertFalse(remade.applyClaude(answer, to: e, on: input.today, input: input), "the card was made again")
        var gone = SuggestionKeep()
        XCTAssertFalse(gone.applyClaude(answer, to: e, on: input.today, input: input), "the card is gone")
        var late = keep(e)
        let tomorrow = PlanView.addDays(input.today, 1)
        var next = input; next.today = tomorrow
        XCTAssertFalse(late.applyClaude(answer, to: e, on: tomorrow, input: next), "the day rolled over")
        var changed = keep(e)
        var moved = input
        for i in moved.sessions.indices where e.record.sessions.contains(moved.sessions[i].id) { moved.sessions[i].plannedMin += 5 }
        XCTAssertFalse(changed.applyClaude(answer, to: e, on: input.today, input: moved), "the plan changed under it")
        XCTAssertEqual(changed.entries[0], e)
        var twice = keep(e)
        XCTAssertTrue(twice.applyClaude(answer, to: e, on: input.today, input: input))
        XCTAssertFalse(twice.applyClaude(ClaudeAnswer(pick: 1, why: fine), to: e, on: input.today, input: input), "a second answer")
    }

    func testAskedOnceAndNeverWhilePausedIllOrForHisOwnTaps() throws {
        let (e, input) = try real()
        var k = keep(e)
        XCTAssertNotNil(k.askable(on: input.today, ladder: .none))
        for step in [RBLadder.paused, .rest, .cold, .easyDays, .week1, .week2, .back, .outLong] {
            XCTAssertNil(k.askable(on: input.today, ladder: step), "\(step)")
        }
        var own = keep(e)
        own.entries[0].record = SuggestionRecord(day: e.record.day, trigger: .section5, step: 0, key: e.record.key,
            headline: e.headline, why: e.why, choices: e.record.choices, tried: [], sessions: e.record.sessions,
            closesOn: e.record.closesOn)
        XCTAssertNil(own.askable(on: input.today, ladder: .none), "stop sign and illness cards are never Claude's")
        k.markAsked(e.id)
        XCTAssertNil(k.askable(on: input.today, ladder: .none), "never asked twice")
        XCTAssertNil(SuggestionKeep().askable(on: input.today, ladder: .none), "no card, no ask")
    }

    func testTheReasonIsPlainText() {
        XCTAssertEqual(ClaudePick.cleanWhy("Why: an easy ride keeps the rhythm."), "Why: an easy ride keeps the rhythm.")
        for bad in ["Why: see www.example.org", "Why: <b>rest</b>", "Why: `rest`", "Why: # rest", "Why: mail me@example.org",
                    "Why: your heart needs it.", "Why: the pain will pass."] {
            XCTAssertNil(ClaudePick.cleanWhy(bad), bad)
        }
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
