import XCTest
@testable import WorkoutCore

/*
 * The app's keeper of suggestions, the part without a screen: one card a
 * day, the log read back as it was written, a taken card as undoable changes
 * to the plan, and a dropped session counted as followed. Invented plans only.
 */
final class SuggestionLogTests: XCTestCase {

    private func d(_ week: Int, _ weekday: Int) -> String { Fixture.day(week, weekday) }

    private func tiredCard() throws -> (Fixture, Suggestion) {
        var f = Fixture.standard()
        f.allDone(before: d(2, 2))
        f.feel.set(.tired, on: d(2, 1)); f.feel.set(.bad, on: d(2, 2))
        return (f, try XCTUnwrap(f.suggest(d(2, 2))))
    }

    func testOneCardADay() throws {
        let (_, card) = try tiredCard()
        var keep = SuggestionKeep()
        XCTAssertTrue(keep.add(SuggestionEntry(card), today: d(2, 2)))
        XCTAssertEqual(keep.openEntry(on: d(2, 2))?.headline, card.headline)
        XCTAssertFalse(keep.add(SuggestionEntry(card), today: d(2, 2)), "a second card the same day")
        keep.answer(card.record.id, .keptPlan, on: d(2, 2))
        XCTAssertNil(keep.openEntry(on: d(2, 2)))
        XCTAssertFalse(keep.mayShowNew(on: d(2, 2)), "still one a day after he answered")
        XCTAssertTrue(keep.mayShowNew(on: d(2, 3)))
        XCTAssertEqual(keep.answerWords(keep.entries[0], today: d(2, 3)), "Kept my plan")
    }

    func testAnUnansweredCardClosesQuietlyAfterItsDay() throws {
        let (_, card) = try tiredCard()
        var keep = SuggestionKeep()
        keep.add(SuggestionEntry(card), today: d(2, 2))
        keep.closeStale(today: PlanView.addDays(card.record.closesOn, 1))
        XCTAssertEqual(keep.entries[0].record.answer, .closedUnanswered)
        XCTAssertEqual(keep.answerWords(keep.entries[0], today: d(3, 0)), "No answer")
    }

    func testTheLogReadsBackAsItWasWritten() throws {
        let (_, card) = try tiredCard()
        var keep = SuggestionKeep()
        keep.on = false
        keep.settings.somethingHurtsTap = false
        keep.add(SuggestionEntry(card), today: d(2, 2))
        keep.answer(card.record.id, .took(1), on: d(2, 2), changeIDs: ["a", "b"])
        keep.health.illSince = d(2, 2)
        keep.hurts("calf", session: "w2-3", on: d(2, 2))
        let back = try SuggestionKeep.decoded(try keep.encoded())
        XCTAssertEqual(back, keep)
        XCTAssertEqual(back.answerWords(back.entries[0], today: d(2, 2)), "Other choice: " + card.otherChoices[0].headline)
        XCTAssertThrowsError(try SuggestionKeep.decoded(Data("{\"entries\": 7}".utf8)), "an unreadable log is never guessed at")
    }

    private func book() throws -> PlanBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
    }

    func testATakenMoveIsExactlyOneUndoableChange() throws {
        var book = try book()
        let input = RuleBook.input(book: book, today: "2026-09-16")
        let s = try XCTUnwrap(input.sessions.first { $0.counts && $0.status == .open && $0.plannedMin >= 30 })
        let short = RuleBook.percent(s.plannedMin, 70)
        let ids = try SuggestionApply.take([.shorten(session: s.id, minutes: short)], input: input, to: &book,
                                           why: "Suggestion: shorter")
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(book.changes.last?.why, "Suggestion: shorter")
        XCTAssertTrue(book.canUndo(ids[0]))
        XCTAssertEqual(book.draft(of: s.id)?.minutes, Double(short))
        try SuggestionApply.undo(ids, in: &book)
        XCTAssertEqual(book.draft(of: s.id).map { Int(($0.minutes ?? 0).rounded()) }, s.plannedMin)
    }

    func testADroppedSessionCountsAsFollowedNeverMissed() throws {
        var book = try book()
        let input = RuleBook.input(book: book, today: "2026-09-16")
        let s = try XCTUnwrap(input.sessions.first { $0.counts && $0.status == .open })
        let ids = try SuggestionApply.take([.drop(session: s.id)], input: input, to: &book, why: "Suggestion: rest")
        XCTAssertEqual(ids.count, 1)
        let w = try XCTUnwrap(book.session(s.id))
        XCTAssertEqual(w.discipline.id, "rest")
        XCTAssertEqual(w.title, SuggestionApply.restTitle)
        XCTAssertFalse(w.missed)
        let view = PlanView(plan: book.sessions, mapping: book.mapping)
        XCTAssertFalse(view.outstanding(before: "2099-01-01").contains { $0.key == s.id }, "a dropped session is never behind")
        let record = SuggestionRecord(day: "2026-09-16", trigger: .t1, step: 1, key: "x", headline: "", why: "",
                                      choices: [[.drop(session: s.id)]], tried: [], sessions: [s.id], closesOn: "2026-09-16",
                                      answer: .took(0), answeredOn: "2026-09-16")
        let after = RuleBook.input(book: book, today: "2026-09-17", log: [record])
        let seen = try XCTUnwrap(after.sessions.first { $0.id == s.id })
        XCTAssertNotEqual(seen.status, .missed)
        XCTAssertFalse(seen.counts)
    }

    func testHisOwnEditGetsOneStatementNeverAQuestion() {
        let f = Fixture.standard()
        let input = f.input(d(2, 0))
        let run = f.id(2, "Steady easy run")
        let note = SuggestionApply.note(moving: run, to: d(2, 4), input: input)
        XCTAssertEqual(note, "Friday is your rest day.")
        XCTAssertNil(SuggestionApply.note(moving: run, to: d(2, 3), input: input))
    }
}
