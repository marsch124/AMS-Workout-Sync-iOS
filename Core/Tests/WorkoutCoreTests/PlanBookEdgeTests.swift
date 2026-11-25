import XCTest
@testable import WorkoutCore

/*
 * Trying to break the book.
 *
 * PlanBookTests holds the promises; this file pushes on the edges of them:
 * logging and changing the same session in every order, taking changes back
 * in the wrong order, entries for sessions that are gone, awkward numbers and
 * words, a broken session in the file, and the spreadsheet copy after a mix
 * of all of it. Invented data only.
 *
 * A test that fails here because the CODE is wrong is kept failing, with a
 * note saying what is wrong — the fix is decided elsewhere.
 */
final class PlanBookEdgeTests: XCTestCase {

    // The fixture: one sheet "Weekly Schedules", minutes, 13 sessions 9–20 Sep 2026, one extra.
    private let swim9 = "Weekly Schedules!2"
    private let run10 = "Weekly Schedules!4"
    private let rest11 = "Weekly Schedules!5"
    private let bike12 = "Weekly Schedules!6"      // "Steady aerobic ride, flat to rolling"
    private let run13 = "Weekly Schedules!7"
    private let strength13 = "Weekly Schedules!8"
    private let bike15 = "Weekly Schedules!10"
    private let run16 = "Weekly Schedules!11"
    private let bike19 = "Weekly Schedules!13"     // "Steady aerobic ride"
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try Data(contentsOf: url)
    }

    private func book(_ data: Data? = nil) throws -> PlanBook {
        try PlanImport.read(try data ?? fixture(), fileName: "plan.xlsx", today: "2026-09-16", now: now).book
    }

    private func entry(_ fill: (inout LogEntry) -> Void) -> LogEntry { var e = LogEntry(); fill(&e); return e }

    @discardableResult
    private func log(_ book: inout PlanBook, _ key: String, _ fill: (inout LogEntry) -> Void) throws -> Applied {
        let w = try XCTUnwrap(book.session(key))
        return try book.apply(QueuedEntry(workout: w, entry: entry(fill), now: now), now: now)
    }

    private func text(_ book: PlanBook, _ key: String, _ field: String) -> String? {
        book.session(key)?.results[field]?.text
    }

    // MARK: logging and changing the same session

    func testLogChangeLogAgainKeepsResultsDoneStateAndKey() throws {
        var book = try book()
        try log(&book, bike12) { $0.actualDuration = "55"; $0.avgHr = "140" }
        var d = try XCTUnwrap(book.draft(of: bike12))
        d.minutes = 70; d.sport = "run"; d.dayKey = "2026-09-14"
        try book.change(bike12, to: d, now: now)
        try log(&book, bike12) { $0.rpe = "6" }

        let w = try XCTUnwrap(book.session(bike12), "the key never changes")
        XCTAssertEqual(w.discipline.id, "run")
        XCTAssertEqual(w.dayKey, "2026-09-14")
        XCTAssertEqual(text(book, bike12, "actualDuration"), "55")
        XCTAssertEqual(text(book, bike12, "avgHr"), "140")
        XCTAssertEqual(text(book, bike12, "rpe"), "6")
        XCTAssertTrue(w.loggedInSheet)
        XCTAssertFalse(w.missed)
    }

    func testUndoOfAnEditAfterLoggingKeepsTheLog() throws {
        var book = try book()
        var d = try XCTUnwrap(book.draft(of: run10))
        d.minutes = 50
        let change = try XCTUnwrap(try book.change(run10, to: d, now: now))
        try log(&book, run10) { $0.actualDuration = "48"; $0.avgHr = "150" }
        try book.undo(change.id, now: now)

        XCTAssertEqual(book.draft(of: run10)?.minutes, 30, "the plan's side goes back")
        XCTAssertEqual(text(book, run10, "actualDuration"), "48", "what was logged stays")
        XCTAssertEqual(book.session(run10)?.loggedInSheet, true)
    }

    func testUndoOfARemovalBringsBackALoggedSessionWithItsResults() throws {
        var book = try book()
        try log(&book, swim9) { $0.actualDuration = "32"; $0.actualDistance = "1200" }
        let gone = try book.remove(swim9, now: now)
        XCTAssertNil(book.session(swim9))
        try book.undo(gone.id, now: now)
        XCTAssertEqual(text(book, swim9, "actualDuration"), "32")
        XCTAssertEqual(book.session(swim9)?.loggedInSheet, true)
        XCTAssertEqual(book.sessions.first?.key, swim9, "back in its own place, first in the plan")
    }

    func testUndoTwiceIsRefusedAndChangesNothing() throws {
        var book = try book()
        var d = try XCTUnwrap(book.draft(of: run10)); d.intensity = "Z3"
        let change = try XCTUnwrap(try book.change(run10, to: d, now: now))
        try book.undo(change.id, now: now)
        let after = book
        XCTAssertThrowsError(try book.undo(change.id, now: now)) { XCTAssertEqual($0 as? BookError, .nothingToUndo) }
        XCTAssertEqual(book, after)
    }

    /*
     * Undoing an "add" after the added session was logged must not lose the
     * log: the session is taken out the way any session is, so it stays in
     * the list of changes with what was logged, and can come back.
     */
    func testUndoOfAnAddAfterItWasLoggedDoesNotSilentlyLoseTheLog() throws {
        var book = try book()
        let made = try book.add(SessionDraft(dayKey: "2026-09-17", sport: "swim", title: "Open water try", minutes: 40), now: now)
        try log(&book, made.key) { $0.actualDuration = "42"; $0.avgHr = "128" }
        let addChange = try XCTUnwrap(book.changes.last { $0.kind == "add" })
        try book.undo(addChange.id, now: now)
        XCTAssertNil(book.session(made.key))
        let taken = try XCTUnwrap(book.changes.last { $0.kind == "remove" && $0.key == made.key })
        XCTAssertEqual(taken.undo?.results["actualDuration"]?.text, "42", "what he logged is kept with the removal")
        try book.undo(taken.id, now: now)
        XCTAssertEqual(book.session(made.key)?.results["actualDuration"]?.text, "42")
    }

    /*
     * FAULT: taking back an OLDER change restores the whole session as it was
     * before it, wiping a newer change that is still listed as in force.
     * PlanBook.undo puts back `change.undo` (the full old Workout).
     */
    func testUndoingAnOlderChangeDoesNotWipeANewerOne() throws {
        var book = try book()
        var d = try XCTUnwrap(book.draft(of: run10)); d.minutes = 40
        let first = try XCTUnwrap(try book.change(run10, to: d, now: now))
        d.intensity = "Z1"
        let second = try XCTUnwrap(try book.change(run10, to: d, now: now))
        let refused = (try? book.undo(first.id, now: now)) == nil
        let stillListed = book.changes.first { $0.id == second.id }?.undone == false
        XCTAssertTrue(refused || !stillListed || book.session(run10)?.planned.intensity == "Z1",
                      "the newer change (Z1) is gone but still listed as in force")
    }

    // MARK: moving

    func testMovingByLogAndByChangeEndTheSame() throws {
        var a = try book(), b = try book()
        try log(&a, bike12) { $0.moveTo = "2026-09-11" }
        var d = try XCTUnwrap(b.draft(of: bike12)); d.dayKey = "2026-09-11"
        try b.change(bike12, to: d, now: now)
        XCTAssertEqual(a.sessions, b.sessions)
    }

    func testMovingAwayAndBackKeepsPlanOrderWithinTheDay() throws {
        var book = try book()
        try log(&book, run13) { $0.moveTo = "2026-09-12" }
        try log(&book, run13) { $0.moveTo = "2026-09-13" }
        let day = book.sessions.filter { $0.dayKey == "2026-09-13" }.map(\.key)
        XCTAssertEqual(day, [run13, strength13])
    }

    func testASessionMovedOntoARestDayKeepsBoth() throws {
        var book = try book()
        try log(&book, run10) { $0.moveTo = "2026-09-11" }
        let day = book.sessions.filter { $0.dayKey == "2026-09-11" }.map(\.key)
        XCTAssertEqual(Set(day), [run10, rest11])
        XCTAssertEqual(book.sessions.count, 13)
    }

    // MARK: entries whose session changed or went

    /*
     * FAULT: an entry for a session that was removed is written into ANOTHER
     * session — "Steady aerobic ride, flat to rolling" (12 Sep, removed) lands
     * on "Steady aerobic ride" (19 Sep) because the words agree and it is
     * within a week. PlanBook.apply line `Sync.findWorkout(...) ?? session(...)`:
     * the book's keys are stable for good, so it should go by key first and
     * refuse a key it has in `removed`.
     */
    func testAnEntryForARemovedSessionIsRefusedAndWritesNowhere() throws {
        var book = try book()
        let old = try XCTUnwrap(book.session(bike12))
        try book.remove(bike12, now: now)
        let q = QueuedEntry(workout: old, entry: entry { $0.actualDuration = "60" }, now: now)
        XCTAssertThrowsError(try book.apply(q, now: now))
        XCTAssertEqual(book.session(bike19)?.loggedInSheet, false, "the log landed on the 19 Sep ride")
    }

    func testAnEntryFindsItsSessionAfterSportDayAndWordsAllChanged() throws {
        var book = try book()
        let old = try XCTUnwrap(book.session(bike15))
        var d = try XCTUnwrap(book.draft(of: bike15))
        d.sport = "run"; d.dayKey = "2026-09-17"; d.title = "Tempo intervals"
        try book.change(bike15, to: d, now: now)
        let q = QueuedEntry(workout: old, entry: entry { $0.actualDuration = "45" }, now: now)
        XCTAssertEqual(try book.apply(q, now: now), .written)
        XCTAssertEqual(text(book, bike15, "actualDuration"), "45")
    }

    /*
     * A run changed into a ride, with a new run added that day: the entry
     * queued for the old run must still go to its own session. (Holds today
     * only because an added session lives on the "App" sheet and findWorkout
     * looks within the entry's sheet; a second run on the same plan sheet
     * would take the log — see the removed-session test for the same cause.)
     */
    func testAnEntryGoesToItsOwnSessionEvenIfAnotherOfTheOldSportSharesTheDay() throws {
        var book = try book()
        let old = try XCTUnwrap(book.session(run13))
        var d = try XCTUnwrap(book.draft(of: run13)); d.sport = "bike"
        try book.change(run13, to: d, now: now)
        let added = try book.add(SessionDraft(dayKey: "2026-09-13", sport: "run", title: "Shakeout jog", minutes: 20), now: now)
        let q = QueuedEntry(workout: old, entry: entry { $0.actualDuration = "36" }, now: now)
        try book.apply(q, now: now)
        XCTAssertEqual(text(book, run13, "actualDuration"), "36")
        XCTAssertNil(text(book, added.key, "actualDuration"), "the log went into the added run")
    }

    // MARK: extras

    func testAnExtraWithoutARefAddedTwiceIsKeptOnce() throws {
        var book = try book()
        var x = ExtraEntry(date: "2026-09-14", activity: "yoga", ref: ""); x.minutes = 20
        try book.apply(extra: x, now: now)
        try book.apply(extra: x, now: now)
        XCTAssertEqual(book.extras.filter { $0.activity == "yoga" }.count, 1)
    }

    func testCorrectingOneFieldOfAnExtraChangesOnlyThatField() throws {
        let original = try XCTUnwrap(try book().extras.first)
        var x = ExtraEntry(date: "2026-09-13", activity: "hike", ref: original.ref)
        x.what = "Ridge trail"; x.minutes = 95; x.distance = 7.5; x.avgHr = 101; x.effort = 5
        x.isTraining = true; x.notes = "Windy."
        let fields = [ExtraField.date, ExtraField.activity, ExtraField.what, ExtraField.duration, ExtraField.distance,
                      ExtraField.avgHr, ExtraField.effort, ExtraField.isTraining, ExtraField.notes]
        for field in fields {
            var book = try book()
            x.editing = ExtraTarget(id: original.id, ref: original.ref, date: original.date, label: original.label,
                                    minutes: original.minutes, fields: [field])
            XCTAssertEqual(try book.apply(extra: x, now: now), .written)
            let r = try XCTUnwrap(book.extras.first)
            var differs: [String] = []
            if r.date != original.date { differs.append(ExtraField.date) }
            if r.label != original.label || r.activity != original.activity { differs.append(ExtraField.activity) }
            if r.what != original.what { differs.append(ExtraField.what) }
            if r.minutes != original.minutes { differs.append(ExtraField.duration) }
            if r.distance != original.distance { differs.append(ExtraField.distance) }
            if r.avgHr != original.avgHr { differs.append(ExtraField.avgHr) }
            if r.effort != original.effort { differs.append(ExtraField.effort) }
            if r.isTraining != original.isTraining { differs.append(ExtraField.isTraining) }
            if r.notes != original.notes { differs.append(ExtraField.notes) }
            XCTAssertEqual(differs, [field])
            XCTAssertEqual(r.ref, original.ref)
        }
    }

    func testCorrectingAnExtraWithNoRefFindsItAndGivesItOne() throws {
        var book = try book()
        var x = ExtraEntry(date: "2026-09-12", activity: "walk", ref: ""); x.minutes = 30
        try book.apply(extra: x, now: now)
        var fix = ExtraEntry(date: "2026-09-12", activity: "walk", ref: "xedgefix1"); fix.minutes = 45
        fix.editing = ExtraTarget(id: "row-3", ref: "", date: "2026-09-12", label: "Walk", minutes: 30,
                                  fields: [ExtraField.duration])
        XCTAssertEqual(try book.apply(extra: fix, now: now), .written)
        let r = try XCTUnwrap(book.extras.first { $0.date == "2026-09-12" })
        XCTAssertEqual(r.minutes, 45)
        XCTAssertEqual(r.ref, "xedgefix1")
        XCTAssertEqual(book.extras.count, 2)
    }

    func testEmptyingAnExtraFieldEmptiesIt() throws {
        var book = try book()
        let original = try XCTUnwrap(book.extras.first)
        var x = ExtraEntry(date: original.date, activity: original.activity, ref: original.ref)
        x.editing = ExtraTarget(id: original.id, ref: original.ref, date: original.date, label: original.label,
                                minutes: original.minutes, fields: [ExtraField.distance, ExtraField.what, ExtraField.duration])
        try book.apply(extra: x, now: now)
        let r = try XCTUnwrap(book.extras.first)
        XCTAssertEqual([r.distance, r.what], ["", ""])
        XCTAssertNil(r.minutes)
    }

    /*
     * FAULT: a corrected "What it was" is stored with its spaces (" Ridge
     * walk "), while a new extra's words are trimmed and the sheet reads them
     * trimmed — so the book and the spreadsheet copy disagree and export
     * refuses to save. PlanBook.apply(extra:), `pick(ExtraField.what, x.what, r.what)`:
     * trim x.what as the add path does.
     */
    func testCorrectedWordsOfAnExtraAreTrimmedLikeNewOnes() throws {
        var book = try book()
        let original = try XCTUnwrap(book.extras.first)
        var x = ExtraEntry(date: original.date, activity: original.activity, ref: original.ref)
        x.what = "  Ridge walk "
        x.editing = ExtraTarget(id: original.id, ref: original.ref, date: original.date, label: original.label,
                                minutes: original.minutes, fields: [ExtraField.what])
        try book.apply(extra: x, now: now)
        XCTAssertEqual(book.extras.first?.what, "Ridge walk")
    }

    // MARK: the spreadsheet copy

    func testExportingAnUnchangedBookHandsBackTheTemplate() throws {
        let template = try fixture()
        XCTAssertEqual(try PlanExport.workbook(try book(template), template: template), template)
    }

    func testExportAfterAMixOfEverythingReadsBackTheSame() throws {
        let template = try fixture()
        var book = try book(template)
        try log(&book, swim9) { $0.actualDuration = "1:05"; $0.actualDistance = "1,8"; $0.distanceUnit = "km" }
        try log(&book, run10) { $0.actualDuration = "31"; $0.avgHr = "131"; $0.rpe = "6"; $0.avgPace = "5:36" }
        try log(&book, bike12) { $0.missed = true }
        var d = try XCTUnwrap(book.draft(of: bike15))
        d.minutes = 47.5; d.intensity = "Z2 <&> \"steady\" 'ish'"; d.dayKey = "2026-09-17"
        d.title = "Lugn tur på ön — åäö ÅÄÖ"
        d.purpose = Array(repeating: "Keep the cadence high & the effort low < threshold.", count: 40).joined(separator: " ")
        try book.change(bike15, to: d, now: now)
        try book.add(SessionDraft(dayKey: "2026-09-21", sport: "brick", title: "Brick: ride then run",
                                  minutes: 75, intensity: "Z2", purpose: "Legs off the bike"), now: now)
        try book.remove(strength13, now: now)
        var x = ExtraEntry(date: "2026-09-16", activity: "yoga", ref: "xedge0001")
        x.minutes = 25; x.effort = 2; x.notes = "Ö-övningar"
        try book.apply(extra: x, now: now)

        let bytes = try PlanExport.workbook(book, template: template)
        let again = try PlanImport.read(bytes, fileName: "copy.xlsx", today: "2026-09-16", now: now).book
        XCTAssertEqual(again.sessions.count, book.sessions.count)
        XCTAssertEqual(again.extras, book.extras)
        XCTAssertEqual(again.session(bike15)?.title, "Lugn tur på ön — åäö ÅÄÖ")
        XCTAssertEqual(again.session(bike12)?.missed, true)
    }

    func testExportOfASessionMovedTwiceAndOneRemovedThenRestored() throws {
        let template = try fixture()
        var book = try book(template)
        var d = try XCTUnwrap(book.draft(of: run10)); d.dayKey = "2026-12-31"
        try book.change(run10, to: d, now: now)
        try log(&book, run10) { $0.moveTo = "2027-01-01" }
        let gone = try book.remove(swim9, now: now)
        try book.undo(gone.id, now: now)

        let bytes = try PlanExport.workbook(book, template: template)
        let again = try PlanImport.read(bytes, fileName: "copy.xlsx", today: "2026-09-16", now: now).book
        XCTAssertEqual(again.session(run10)?.dayKey, "2027-01-01")
        XCTAssertNotNil(again.session(swim9))
        XCTAssertEqual(again.sessions.count, 13)
    }

    func testExportAfterAResultWasEmptied() throws {
        // A workbook that already holds a logged session, as his did.
        let fixture = try fixture()
        let w = try XCTUnwrap(try book(fixture).session(run10))
        let (logged, _) = try Sync.apply([QueuedEntry(workout: w, entry: entry { $0.actualDuration = "30"; $0.avgHr = "140" }, now: now)],
                                         to: fixture, now: now)
        let template = try XCTUnwrap(logged)
        var book = try book(template)
        let i = try XCTUnwrap(book.sessions.firstIndex { $0.key == run10 })
        book.sessions[i].results["avgHr"] = nil

        let bytes = try PlanExport.workbook(book, template: template)
        let again = try PlanImport.read(bytes, fileName: "copy.xlsx", today: "2026-09-16", now: now).book
        XCTAssertNil(again.session(run10)?.results["avgHr"])
        XCTAssertEqual(again.session(run10)?.results["actualDuration"]?.text, "30")
    }

    func testAnExtraWithAGarbledDateSurvivesTheCopy() throws {
        let template = try fixture()
        var book = try book(template)
        var x = ExtraEntry(date: "2026-02-30", activity: "walk", ref: "xedge0002"); x.minutes = 15
        try book.apply(extra: x, now: now)
        let bytes = try PlanExport.workbook(book, template: template)
        let again = try PlanImport.read(bytes, fileName: "copy.xlsx", today: "2026-09-16", now: now).book
        XCTAssertEqual(again.extras.first { $0.ref == "xedge0002" }?.date, "2026-02-30")
    }

    func testAwkwardNumbersSurviveTheBookAndTheCopy() throws {
        let template = try fixture()
        var book = try book(template)
        try log(&book, run10) { $0.avgHr = "0.30000000000000004"; $0.rpe = "1.0249999999999999"; $0.actualDuration = "99999999" }
        let reopened = try PlanBook.decoded(try book.encoded())
        XCTAssertEqual(reopened.session(run10)?.results.mapValues(\.text), book.session(run10)?.results.mapValues(\.text))
        XCTAssertNoThrow(try PlanExport.workbook(book, template: template))
    }

    // MARK: on disk

    /*
     * Saving twice in a row must give the same bytes; otherwise every open
     * and save looks like a change (and "newest change wins" goes by stamps).
     */
    func testABookIsByteForByteStableThroughTheDisk() throws {
        var book = try book()
        for (i, t) in [1_789_000_000.1234567, 1_789_123_456.789012, 1_790_000_000.000999].enumerated() {
            let when = Date(timeIntervalSince1970: t)
            let w = try XCTUnwrap(book.session([run10, bike12, swim9][i]))
            try book.apply(QueuedEntry(workout: w, entry: entry { $0.actualDuration = "30" }, now: when), now: when)
        }
        let once = try book.encoded()
        let twice = try PlanBook.decoded(once).encoded()
        XCTAssertEqual(once, twice)
    }

    /*
     * FAULT: typing "Infinity" (or "1e999") as a heart rate or distance puts
     * an infinite number into the book, and from then on the book cannot be
     * saved at all — JSONEncoder throws on it. jsParseFloat accepts
     * "Infinity", Plan.buildEdits keeps it, and PlanBook.readBack only drops
     * NaN. Fix: readBack (and buildEdits) should drop non-finite numbers.
     */
    func testATypedInfinityDoesNotMakeTheBookUnsaveable() throws {
        var book = try book()
        try log(&book, run10) { $0.avgHr = "Infinity"; $0.actualDistance = "1e999" }
        XCTAssertNoThrow(try book.encoded())
    }

    /*
     * FAULT: a draft length of infinity or NaN is taken into the plan and the
     * book can no longer be saved. PlanBook.change / shaped: refuse a length
     * that is not finite.
     */
    func testANonFiniteLengthInADraftCannotBreakTheBook() throws {
        for bad in [Double.infinity, .nan] {
            var book = try book()
            var d = try XCTUnwrap(book.draft(of: run10)); d.minutes = bad
            _ = try? book.change(run10, to: d, now: now)
            XCTAssertNoThrow(try book.encoded(), "length \(bad)")
        }
    }

    /*
     * A session that is there but cannot be read is damage, and the book says
     * so by not opening: the app then puts back its newest safety copy rather
     * than open a plan with a session missing and save that over the rest.
     * A field from a newer app is not damage and is simply passed over.
     */
    func testADamagedSessionStopsTheBookOpeningAndANewerFieldDoesNot() throws {
        let book = try book()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try book.encoded()) as? [String: Any])
        var sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        sessions[6]["somethingNewer"] = true
        object["sessions"] = sessions
        XCTAssertEqual(try PlanBook.decoded(try JSONSerialization.data(withJSONObject: object)).sessions.count, book.sessions.count)

        sessions[5]["dayKey"] = "2026-13-45"
        object["sessions"] = sessions
        XCTAssertThrowsError(try PlanBook.decoded(try JSONSerialization.data(withJSONObject: object)))
    }

    // MARK: counting

    func testTallyCountsMissedRestAndMonthBoundaries() throws {
        var book = try book()
        try log(&book, swim9) { $0.actualDuration = "30" }
        try log(&book, bike12) { $0.missed = true }
        try log(&book, rest11) { $0.actualDuration = "10" }
        var d = try XCTUnwrap(book.draft(of: run10)); d.dayKey = "2026-08-31"
        try book.change(run10, to: d, now: now)
        let t = PlanImport.tally(book.sessions, extras: book.extras, mapping: book.mapping, today: "2026-09-16")
        XCTAssertEqual(t.rest, 2)
        XCTAssertEqual(t.missed, 1)
        XCTAssertEqual(t.done, 1, "a logged rest day is not a done session")
        XCTAssertEqual(t.months.map(\.month), ["2026-08", "2026-09"])
        XCTAssertEqual(t.months.first?.sessions, 1)
    }

    /* A session done today counts in its month, so the months add up to the total. */
    func testMonthsAddUpToTheTotalDone() throws {
        var book = try book()
        try log(&book, swim9) { $0.actualDuration = "30" }
        try log(&book, run16) { $0.actualDuration = "35" }  // today
        let t = PlanImport.tally(book.sessions, extras: book.extras, mapping: book.mapping, today: "2026-09-16")
        XCTAssertEqual(t.months.reduce(0) { $0 + $1.done }, t.done)
    }

    func testAPlanWithNothingBeforeTodayCountsNoMonths() throws {
        let book = try book()
        let t = PlanImport.tally(book.sessions, extras: book.extras, mapping: book.mapping, today: "2026-01-01")
        XCTAssertEqual(t.months, [])
        XCTAssertEqual(t.plannedMinutes, 0)
        XCTAssertEqual(t.toCome, t.training)
    }

    // MARK: weeks

    func testWeekHeadingsAcrossTheYearAndWithoutATag() throws {
        let wb = try Workbook(data: try fixture())
        let mapping = try XCTUnwrap(try Plan.mapping(for: wb))
        let col = try XCTUnwrap(mapping.columns["date"])
        try wb.writeCells(mapping.sheets[0], [
            CellEdit(ref: makeRef(col, 30), value: .text("21 Sep – 27 Sep 2026"), field: "date"),
            CellEdit(ref: makeRef(col, 31), value: .text("28 Dec – 03 Jan 2027"), field: "date")
        ])
        let book = try book(try wb.save())
        XCTAssertEqual(book.sessions.count, 13, "a heading is not a session")
        XCTAssertEqual(book.weeks.map(\.monday), ["2026-09-21", "2026-12-28"])
        XCTAssertEqual(book.week(on: "2027-01-02")?.monday, "2026-12-28")
        XCTAssertEqual(book.weeks.map(\.tag), ["", ""])
        XCTAssertFalse(book.weeks.contains { $0.isEasy || $0.isTest })
    }

    func testAPlanWithoutHeadingsHasNoWeeksAndStillHasPhases() throws {
        let book = try book()
        XCTAssertEqual(book.weeks, [])
        XCTAssertNil(book.week(on: "2026-09-16"))
        XCTAssertEqual(book.phase(on: "2026-09-16"), "")
    }

    /* FAULT (small): a heading with an impossible date gives a Monday that is no day. PlanImport.monday(of:) never checks it. */
    func testAHeadingWithAnImpossibleDateGivesNoMonday() {
        XCTAssertNil(PlanImport.monday(of: "31 Feb – 06 Mar 2026"))
    }

    // MARK: days

    func testLeapDayIsADayAndTwentyNinthFebruaryOfAnOrdinaryYearIsRefused() throws {
        var book = try book()
        var d = try XCTUnwrap(book.draft(of: run10)); d.dayKey = "2028-02-29"
        try book.change(run10, to: d, now: now)
        XCTAssertEqual(book.session(run10)?.dayKey, "2028-02-29")

        let before = book
        d.dayKey = "2026-02-29"
        XCTAssertThrowsError(try book.change(run10, to: d, now: now)) { XCTAssertEqual($0 as? BookError, .badDay("2026-02-29")) }
        XCTAssertThrowsError(try book.add(SessionDraft(dayKey: "2026-02-29", sport: "run"), now: now))
        XCTAssertEqual(book, before, "a refused day changes nothing")
    }

    /*
     * FAULT: a day typed with a space (" 2026-09-20") is accepted — parseDayKey
     * trims — but stored as typed, so the session's day key no longer compares
     * with any other ("today", the week, the months). PlanBook.change
     * (`w.on(date, d.dayKey)`) and PlanBook.add (`dayKey: draft.dayKey`):
     * store dayKey(date) instead of the text.
     */
    func testADayTypedWithASpaceIsStoredAsTheDay() throws {
        var book = try book()
        var d = try XCTUnwrap(book.draft(of: run10)); d.dayKey = " 2026-09-20"
        _ = try? book.change(run10, to: d, now: now)
        XCTAssertTrue(["2026-09-10", "2026-09-20"].contains(book.session(run10)?.dayKey ?? "?"),
                      "stored as \"\(book.session(run10)?.dayKey ?? "")\"")
        if let made = try? book.add(SessionDraft(dayKey: "2026-09-22 ", sport: "run", title: "Easy"), now: now) {
            XCTAssertEqual(book.session(made.key)?.dayKey, "2026-09-22")
        }
    }
}
