import XCTest
@testable import WorkoutCore

/*
 * The plan living in the app (2.0).
 *
 * Two promises are held here. Taking the workbook in changes nothing: the
 * same sessions, the same minutes. And logging into the book is what logging
 * into Excel was, box for box — the same entries are written both ways and
 * read back.
 */
final class PlanBookTests: XCTestCase {

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"),
                                "the test workbook is missing")
        return try Data(contentsOf: url)
    }

    private func book() throws -> PlanBook {
        try PlanImport.read(try fixture(), fileName: "plan.xlsx", today: "2026-09-16").book
    }

    func testTakingThePlanInChangesNothing() throws {
        let taken = try PlanImport.read(try fixture(), fileName: "plan.xlsx", today: "2026-09-16")
        XCTAssertTrue(taken.proof.matches, taken.proof.differences.joined(separator: "\n"))
        XCTAssertGreaterThan(taken.proof.compared, 0)
        XCTAssertEqual(taken.proof.before.sessions, taken.book.sessions.count)
        XCTAssertNotNil(taken.book.sessions.first?.source, "each session keeps the words of its own row")
    }

    func testLoggingIntoTheBookIsWhatLoggingIntoExcelWas() throws {
        let outcome = try BookOracle.run(try fixture(), today: "2026-09-16")
        XCTAssertGreaterThan(outcome.entries, 4)
        XCTAssertEqual(outcome.differences, [])
    }

    func testASessionCanBeChangedAndTheChangeTakenBack() throws {
        var book = try book()
        let w = try XCTUnwrap(book.sessions.first { $0.discipline.id != "rest" && !$0.loggedInSheet })
        var draft = try XCTUnwrap(book.draft(of: w.key))
        let minutesBefore = draft.minutes
        draft.minutes = 40
        draft.intensity = "Z1"
        draft.dayKey = PlanView.addDays(w.dayKey, 1)

        let change = try XCTUnwrap(try book.change(w.key, to: draft, why: "tired legs"))
        let after = try XCTUnwrap(book.session(w.key))
        XCTAssertEqual(Plan.plannedSeconds(after, book.mapping), 40 * 60)
        XCTAssertEqual(after.planned.intensity, "Z1")
        XCTAssertEqual(after.dayKey, draft.dayKey)
        XCTAssertEqual(after.key, w.key, "a session keeps its name for good")
        XCTAssertTrue(change.after.contains("40 min"))
        XCTAssertNil(try book.change(w.key, to: draft), "saying what the plan already says is no change")

        try book.undo(change.id)
        let back = try XCTUnwrap(book.session(w.key))
        XCTAssertEqual(back.dayKey, w.dayKey)
        XCTAssertEqual(book.draft(of: w.key)?.minutes, minutesBefore)
    }

    /* A drop on the week board: only the day is new. The key stays, the session moves, one change is recorded. */
    func testADropOnTheWeekBoardOnlyMovesTheDay() throws {
        var book = try book()
        let w = try XCTUnwrap(book.sessions.first { $0.discipline.id != "rest" && !$0.loggedInSheet })
        var draft = try XCTUnwrap(book.draft(of: w.key))
        let changesBefore = book.changes.count
        draft.dayKey = PlanView.addDays(w.dayKey, 2)
        let change = try XCTUnwrap(try book.change(w.key, to: draft))
        let moved = try XCTUnwrap(book.session(w.key))
        XCTAssertEqual(moved.dayKey, draft.dayKey)
        XCTAssertEqual(moved.title, w.title)
        XCTAssertEqual(book.changes.count, changesBefore + 1)
        XCTAssertEqual(change.afterDay, draft.dayKey)
    }

    func testASessionCanBeAddedLoggedAndRemoved() throws {
        var book = try book()
        let count = book.sessions.count
        let made = try book.add(SessionDraft(dayKey: "2026-09-17", sport: "bike", title: "Easy spin",
                                             minutes: 45, intensity: "Z2", purpose: "Third ride of the week"))
        XCTAssertEqual(book.sessions.count, count + 1)
        XCTAssertEqual(made.discipline.id, "bike")
        XCTAssertTrue(made.madeInApp)

        var entry = LogEntry(); entry.actualDuration = "45"
        XCTAssertEqual(try book.apply(QueuedEntry(workout: made, entry: entry)), .written)
        XCTAssertEqual(book.session(made.key)?.loggedInSheet, true)

        let reopened = try PlanBook.decoded(try book.encoded())
        XCTAssertEqual(reopened.session(made.key)?.title, "Easy spin")
        XCTAssertEqual(reopened.session(made.key)?.loggedInSheet, true)

        let gone = try book.remove(made.key)
        XCTAssertEqual(book.sessions.count, count)
        XCTAssertNotNil(book.removed[made.key])
        try book.undo(gone.id)
        XCTAssertEqual(book.sessions.count, count + 1)
        XCTAssertNil(book.removed[made.key])
    }

    func testABookFromAnOlderAppStillOpens() throws {
        let book = try book()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try book.encoded()) as? [String: Any])
        for key in ["changes", "stamps", "removed", "counter", "weeks", "origin", "format"] { object[key] = nil }
        object["somethingNewer"] = ["a": 1]
        let reopened = try PlanBook.decoded(try JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(reopened.sessions.count, book.sessions.count)
        XCTAssertEqual(PlanImport.differences(book.sessions, reopened.sessions), [])
    }

    func testATestEnteredInTheAppChangesTheZonesAndNothingElseDoes() throws {
        var book = try book()
        let zones = try XCTUnwrap(book.zones, "the test plan has a zones sheet")
        XCTAssertFalse(book.tests.isEmpty, "the test rows come in with the plan")
        // Worked out in the app from the same numbers, the tables say what Excel said.
        XCTAssertEqual(zones.recalculated(from: book.tests).tables, zones.tables)

        let before = try XCTUnwrap(zones.lthr)
        let next = try XCTUnwrap(book.tests.first { !$0.hasNumbers } ?? book.tests.last)
        book.record(TestResult(name: next.name, week: next.week, dates: next.dates, lthr: before + 10))
        XCTAssertEqual(book.zones?.lthr, before + 10)
        XCTAssertNotEqual(book.zones?.tables.first { $0.kind == .heart }, zones.tables.first { $0.kind == .heart })
        // A number the new test does not carry stays the last one known.
        XCTAssertEqual(book.zones?.tables.first { $0.kind == .swim }, zones.tables.first { $0.kind == .swim })
        XCTAssertEqual(try PlanBook.decoded(try book.encoded()).tests, book.tests)
    }

    func testAWeekHeadingGivesItsMonday() {
        XCTAssertEqual(PlanImport.monday(of: "07 Sep – 13 Sep 2026"), "2026-09-07")
        XCTAssertEqual(PlanImport.monday(of: "28 Dec – 03 Jan 2027"), "2026-12-28")
        XCTAssertNil(PlanImport.monday(of: "2026-09-10"))
    }

    /* An entry from the Excel days names a row as it was then: if that row is now another session, it is not written there. */
    func testAnEntryFromTheExcelDaysIsNotWrittenIntoAnotherSession() throws {
        var book = try book()
        let w = try XCTUnwrap(book.sessions.first { $0.discipline.id == "run" && $0.results.isEmpty })
        var entry = LogEntry(); entry.actualDuration = "41"
        // Made the day before the plan moved in, for a swim far away that the row no longer holds.
        let old = QueuedEntry(workoutKey: w.key, sheet: w.sheet, row: w.row, dayKey: "2001-01-01", disciplineId: "swim",
                              title: "Invented swim", entry: entry, now: book.origin.takenAt.addingTimeInterval(-86400))
        XCTAssertThrowsError(try book.apply(old))
        XCTAssertTrue(try XCTUnwrap(book.session(w.key)).results.isEmpty, "the run was left alone")
        // The same entry made after the move-in names the session for good, as before.
        let fresh = QueuedEntry(workoutKey: w.key, sheet: w.sheet, row: w.row, dayKey: "2001-01-01", disciplineId: "swim",
                                title: "Invented swim", entry: entry, now: book.origin.takenAt.addingTimeInterval(60))
        XCTAssertEqual(try book.apply(fresh), .written)
    }
}
