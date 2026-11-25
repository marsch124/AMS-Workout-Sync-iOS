import XCTest
@testable import WorkoutCore

/*
 * Two copies of the plan meeting (2.1, iCloud sharing).
 *
 * Every test builds "devices" from the same invented plan, lets each change
 * it on its own with its own clock, and joins them. The promises: it is the
 * same whichever copy is named first, joining twice is joining once, and
 * nothing he logged is ever lost.
 */
final class BookMergeTests: XCTestCase {

    private let swim9 = "Weekly Schedules!2"
    private let run10 = "Weekly Schedules!4"
    private let bike12 = "Weekly Schedules!6"
    private let run13 = "Weekly Schedules!7"
    private let bike15 = "Weekly Schedules!10"
    private let run16 = "Weekly Schedules!11"
    private let bike19 = "Weekly Schedules!13"
    private let t0 = 1_789_000_000.0
    private func at(_ s: Double) -> Date { Date(timeIntervalSince1970: t0 + s) }

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try Data(contentsOf: url)
    }

    private func base(takenAt: Double = 0) throws -> PlanBook {
        try PlanImport.read(try fixture(), fileName: "plan.xlsx", today: "2026-09-16", now: at(takenAt)).book
    }

    private func log(_ book: inout PlanBook, _ key: String, _ minutes: String, _ s: Double) throws {
        let w = try XCTUnwrap(book.session(key))
        var e = LogEntry(); e.actualDuration = minutes
        try book.apply(QueuedEntry(workout: w, entry: e, now: at(s)), now: at(s))
    }

    private func edit(_ book: inout PlanBook, _ key: String, _ s: Double, _ fill: (inout SessionDraft) -> Void) throws {
        var d = try XCTUnwrap(book.draft(of: key))
        fill(&d)
        try book.change(key, to: d, now: at(s))
    }

    private func extra(_ book: inout PlanBook, _ ref: String, _ day: String, _ s: Double) throws {
        var x = ExtraEntry(date: day, activity: "run", ref: ref)
        x.minutes = 20
        try book.apply(extra: x, now: at(s))
    }

    private func m(_ a: PlanBook, _ b: PlanBook) throws -> PlanBook { try BookMerge.merged(a, b) }
    private func bytes(_ b: PlanBook) throws -> Data { try b.encoded() }

    // MARK: the properties

    func testMergingABookWithItselfChangesNothing() throws {
        var a = try base()
        try log(&a, bike12, "60", 10)
        try edit(&a, run13, 20) { $0.minutes = 33 }
        let once = try m(a, a)
        XCTAssertEqual(try bytes(once), try bytes(try m(once, a)))
        XCTAssertEqual(try bytes(once), try bytes(try m(once, once)))
        XCTAssertEqual(PlanImport.differences(a.sessions, once.sessions), [])
        XCTAssertEqual(once.changes, a.changes)
        XCTAssertEqual(once.stamps, a.stamps)
        XCTAssertEqual(once.removed, a.removed)
        XCTAssertEqual(once.extras, a.extras)
    }

    /* Three devices that each did a bit of everything, apart. */
    private func three() throws -> (PlanBook, PlanBook, PlanBook) {
        let b = try base()
        var x = b, y = b, z = b
        try log(&x, bike12, "60", 10)
        try edit(&x, run13, 20) { $0.minutes = 33 }
        try x.remove(swim9, now: at(30))
        try extra(&x, "x-1", "2026-09-14", 40)
        try edit(&y, run13, 25) { $0.dayKey = "2026-09-14" }
        try log(&y, run10, "30", 26)
        _ = try y.add(SessionDraft(dayKey: "2026-09-17", sport: "bike", title: "Spin", minutes: 40), now: at(27))
        try extra(&y, "y-1", "2026-09-14", 41)
        try log(&z, swim9, "45", 50)
        try log(&z, bike19, "70", 51)
        try z.record(TestResult(name: "Test 2", lthr: 160), now: at(52))
        return (x, y, z)
    }

    func testTheSameWhicheverCopyIsNamedFirst() throws {
        let (x, y, z) = try three()
        for (p, q) in [(x, y), (y, z), (x, z)] {
            XCTAssertEqual(try bytes(try m(p, q)), try bytes(try m(q, p)))
        }
        XCTAssertEqual(try bytes(try BookMerge.merged([x, y, z])), try bytes(try BookMerge.merged([z, x, y])))
    }

    func testJoiningInAnyGroupingIsTheSame() throws {
        let (x, y, z) = try three()
        XCTAssertEqual(try bytes(try m(try m(x, y), z)), try bytes(try m(x, try m(y, z))))
        XCTAssertEqual(try bytes(try m(try m(x, z), y)), try bytes(try m(try m(y, x), z)))
    }

    func testNothingLoggedOnEitherSideIsEverLost() throws {
        let (x, y, z) = try three()
        let all = try BookMerge.merged([x, y, z])
        // Every log the devices made is in the result (the swim was logged on z after x took it out).
        for (book, key) in [(x, bike12), (y, run10), (z, swim9), (z, bike19)] {
            let theirs = try XCTUnwrap(book.session(key)).results
            XCTAssertFalse(theirs.isEmpty)
            XCTAssertEqual(all.session(key)?.results, theirs, key)
        }
        XCTAssertNotNil(all.session(swim9), "logged after it was taken out: it came back")
        XCTAssertNil(all.removed[swim9])
        XCTAssertTrue(all.changes.contains { $0.kind == "back" && $0.key == swim9 })
        // Both devices' own changes and extras are there, rows apart.
        XCTAssertEqual(Set(all.extras.compactMap { $0.ref.isEmpty ? nil : $0.ref }), ["x-1", "xtest001", "y-1"], "the workbook's own extra too")
        XCTAssertEqual(Set(all.extras.map(\.row)).count, all.extras.count)
        XCTAssertEqual(all.sessions.count, try base().sessions.count + 1)
        for c in x.changes + y.changes + z.changes { XCTAssertTrue(all.changes.contains { $0.id == c.id }) }
    }

    func testTheChangeListIsTheUnionInTimeOrderWithoutDoublesAndKeepsUndone() throws {
        let b = try base()
        var x = b, y = b
        try edit(&x, run13, 20) { $0.minutes = 33 }
        let first = try XCTUnwrap(x.changes.first)
        y = try m(y, x)
        try y.undo(first.id, now: at(30))
        try edit(&x, run16, 40) { $0.minutes = 25 }
        let all = try m(x, y)
        XCTAssertEqual(all.changes.map(\.id), all.changes.sorted { $0.at != $1.at ? $0.at < $1.at : $0.id < $1.id }.map(\.id))
        XCTAssertEqual(Set(all.changes.map(\.id)).count, all.changes.count)
        XCTAssertEqual(all.changes.count, 2)
        XCTAssertTrue(all.changes.first { $0.id == first.id }?.undone == true, "taken back on either side is taken back")
    }

    func testTestResultsAreTheUnionAndTheLaterNumbersWin() throws {
        let b = try base()
        var x = b, y = b
        x.record(TestResult(name: "Test 8", lthr: 160), now: at(10))
        y.record(TestResult(name: "Test 9", lthr: 165), now: at(5))
        y.record(TestResult(name: "Test 8", lthr: 140), now: at(6))
        let all = try m(x, y)
        XCTAssertEqual(all.tests.first { $0.name == "Test 8" }?.lthr, 160)
        XCTAssertNotNil(all.tests.first { $0.name == "Test 9" })
        XCTAssertEqual(all.tests.count, Set(all.tests.map(\.name)).count)
        XCTAssertEqual(try bytes(all), try bytes(try m(y, x)))
    }

    // MARK: the rules

    func testASessionTakenOutStaysOutUnlessTheOtherDeviceDidSomethingLater() throws {
        let b = try base()
        var x = b, y = b
        try log(&y, run16, "30", 5)             // logged BEFORE the removal…
        x = try m(x, y)                         // …and the removing device saw that log
        try x.remove(run16, now: at(10))
        let gone = try m(x, y)
        XCTAssertNil(gone.session(run16))
        XCTAssertNotNil(gone.removed[run16])
        XCTAssertTrue(gone.changes.contains { $0.kind == "remove" && $0.key == run16 && $0.undo?.results == y.session(run16)?.results })
        // Merging with a copy that never heard of it also keeps it out.
        XCTAssertNil(try m(gone, b).session(run16))
        // Taken out unlogged on one, never logged on the other: out.
        var p = b
        try p.remove(bike15, now: at(20))
        XCTAssertNil(try m(p, b).session(bike15))
        XCTAssertNil(try m(b, p).session(bike15))
    }

    func testTwoDevicesChangingTheSameSessionTheLaterWholeSideWins() throws {
        let b = try base()
        var x = b, y = b
        try edit(&x, bike12, 10) { $0.minutes = 75; $0.intensity = "Z1" }
        try edit(&y, bike12, 20) { $0.minutes = 50 }
        let all = try m(x, y)
        XCTAssertEqual(all.draft(of: bike12), y.draft(of: bike12))
        XCTAssertEqual(try bytes(all), try bytes(try m(y, x)))
    }

    func testTheSameMarkWithOtherWordsGivesTheSameAnswerEverywhere() throws {
        let b = try base()
        var x = b, y = b
        try edit(&x, bike12, 10) { $0.title = "Short" }
        try edit(&y, bike12, 10) { $0.title = "A much longer title" }
        XCTAssertEqual(try m(x, y).session(bike12)?.title, "A much longer title")
        XCTAssertEqual(try bytes(try m(x, y)), try bytes(try m(y, x)))
    }

    func testMovesTheNewestWins() throws {
        var x = try base(), y = try base()
        x.moves[run10] = MoveRecord(from: "2026-09-10", to: "2026-09-11", disciplineId: "run", at: at(5))
        y.moves[run10] = MoveRecord(from: "2026-09-10", to: "2026-09-12", disciplineId: "run", at: at(9))
        y.moves[bike12] = MoveRecord(from: "2026-09-12", to: "2026-09-13", disciplineId: "bike", at: at(1))
        let all = try m(x, y)
        XCTAssertEqual(all.moves[run10]?.to, "2026-09-12")
        XCTAssertEqual(all.moves.count, 2)
        XCTAssertEqual(try bytes(all), try bytes(try m(y, x)))
    }

    func testExtrasRowsAreRenumberedTheSameEverywhere() throws {
        let b = try base()
        var x = b, y = b
        try extra(&x, "aaa", "2026-09-14", 10)
        try extra(&y, "bbb", "2026-09-14", 11)
        XCTAssertEqual(x.extras.first { $0.ref == "aaa" }?.row, y.extras.first { $0.ref == "bbb" }?.row, "both made the same row offline")
        let all = try m(x, y)
        let rows = all.extras.map(\.row)
        XCTAssertEqual(Set(rows).count, rows.count)
        XCTAssertEqual(all.extras.first { $0.ref == "aaa" }?.row, b.origin.extrasLastRow.map { $0 + 1 })
        XCTAssertEqual(try bytes(all), try bytes(try m(y, x)))
        // …and the spreadsheet copy still reads back.
        let template = try fixture()
        XCTAssertNoThrow(try PlanExport.workbook(all, template: template))
    }

    // MARK: the eight cases

    func testCase1_TheSameSessionChangedOnTwoDevices() throws {
        let b = try base()
        let was = try XCTUnwrap(b.draft(of: bike12))
        var phone = b, mac = b
        try edit(&phone, bike12, 10) { $0.minutes = 75 }
        try edit(&mac, bike12, 20) { $0.dayKey = PlanView.addDays(was.dayKey, 1) }
        let all = try m(phone, mac)
        XCTAssertEqual(all.draft(of: bike12)?.dayKey, PlanView.addDays(was.dayKey, 1))
        XCTAssertEqual(all.draft(of: bike12)?.minutes, was.minutes, "the later plan side, whole")
        XCTAssertEqual(try bytes(all), try bytes(try m(mac, phone)))
        XCTAssertEqual(all.changes.count, 2)

        // 1b: the phone LOGS it, the Mac changes its length later: both survive.
        var phone2 = b, mac2 = b
        try log(&phone2, bike12, "88", 10)
        try edit(&mac2, bike12, 20) { $0.minutes = 80 }
        let both = try m(phone2, mac2)
        XCTAssertEqual(both.session(bike12)?.results, phone2.session(bike12)?.results)
        XCTAssertEqual(both.draft(of: bike12)?.minutes, 80)
        XCTAssertEqual(both.session(bike12)?.loggedInSheet, true)
        // And the other way round: the Mac changes first, the phone logs after — neither undoes the other.
        var phone3 = b, mac3 = b
        try edit(&mac3, bike12, 10) { $0.minutes = 80 }
        try log(&phone3, bike12, "88", 20)
        let again = try m(mac3, phone3)
        XCTAssertEqual(again.draft(of: bike12)?.minutes, 80)
        XCTAssertEqual(again.session(bike12)?.results["actualDuration"]?.text, "88")
    }

    func testCase2_RemovedOnOneLoggedOnTheOther() throws {
        let b = try base()
        var mac = b, phone = b
        try mac.remove(swim9, now: at(10))
        try log(&phone, swim9, "40", 20)
        let all = try m(mac, phone)
        XCTAssertNotNil(all.session(swim9)?.results["actualDuration"])
        XCTAssertNil(all.removed[swim9])
        XCTAssertTrue(all.changes.contains { $0.kind == "back" && $0.key == swim9 && $0.after.hasPrefix("Came back") })
        XCTAssertEqual(try bytes(all), try bytes(try m(phone, mac)))
        // The line "came back" does not stand in the way of undoing an older change.
        XCTAssertEqual(try bytes(try m(all, mac)), try bytes(all))

        // Reversed times: logged on the phone at 10 (and the app closed at once, or offline), taken out on the
        // Mac at 20 — the Mac never saw that log, so taking the session out must not take the log with it.
        var mac2 = b, phone2 = b
        try log(&phone2, swim9, "40", 10)
        try mac2.remove(swim9, now: at(20))
        let kept = try m(mac2, phone2)
        XCTAssertEqual(kept.session(swim9)?.results, phone2.session(swim9)?.results, "the session and its log survive")
        XCTAssertNil(kept.removed[swim9])
        XCTAssertTrue(kept.changes.contains { $0.kind == "back" && $0.key == swim9 && $0.after.hasPrefix("Came back") })
        XCTAssertEqual(try bytes(kept), try bytes(try m(phone2, mac2)), "the same in either order")
        XCTAssertEqual(try bytes(try m(kept, mac2)), try bytes(kept), "and the same when it meets the Mac again")
        let join = BookMerge.join(local: phone2, cloud: [mac2], cloudFileThere: true)
        XCTAssertFalse(join.takenAway.contains(swim9))
        XCTAssertFalse(join.takenAway.contains("log:" + swim9))
    }

    /* Undoing the removal afterwards (on either device) brings the session back WITH its log, not empty. */
    func testCase2b_UndoOfTheRemovalKeepsTheLogTheRemovingDeviceNeverSaw() throws {
        let b = try base()
        var mac = b, phone = b
        try log(&phone, swim9, "40", 10)
        let removal = try mac.remove(swim9, now: at(20))
        for (first, second) in [(mac, phone), (phone, mac)] {
            var joined = try m(first, second)
            XCTAssertTrue(joined.canUndo(removal.id))
            try joined.undo(removal.id, now: at(30))
            XCTAssertEqual(joined.session(swim9)?.results["actualDuration"]?.text, "40")
            XCTAssertEqual(joined.session(swim9)?.loggedInSheet, true)
        }
        // Undone on the Mac BEFORE it met the phone: the phone's log still wins.
        var macUndo = mac
        try macUndo.undo(removal.id, now: at(30))
        XCTAssertEqual(try m(macUndo, phone).session(swim9)?.results["actualDuration"]?.text, "40")
        XCTAssertEqual(try bytes(try m(macUndo, phone)), try bytes(try m(phone, macUndo)))

        // He saw the log and took the session out anyway: then it goes, and the remove line holds the log.
        var mac3 = try m(b, phone)
        try mac3.remove(swim9, now: at(40))
        let gone = try m(mac3, phone)
        XCTAssertNil(gone.session(swim9))
        XCTAssertEqual(gone.changes.last { $0.kind == "remove" && $0.key == swim9 }?.undo?.results["actualDuration"]?.text, "40")
        XCTAssertEqual(try bytes(gone), try bytes(try m(phone, mac3)))
        XCTAssertTrue(BookMerge.join(local: phone, cloud: [mac3], cloudFileThere: true).takenAway.contains(swim9))
    }

    func testCase3_AddedOnBoth() throws {
        let b = try base()
        var pad = b, phone = b
        let p = try pad.add(SessionDraft(dayKey: "2026-09-15", sport: "run", title: "Pad run", minutes: 30), now: at(10))
        let q = try phone.add(SessionDraft(dayKey: "2026-09-15", sport: "run", title: "Phone run", minutes: 30), now: at(11))
        XCTAssertEqual(pad.counter, phone.counter)
        XCTAssertNotEqual(p.key, q.key)
        var padX = pad, phoneX = phone
        try extra(&padX, "pad-extra", "2026-09-15", 12)
        try extra(&phoneX, "phone-extra", "2026-09-15", 13)
        let all = try m(padX, phoneX)
        XCTAssertNotNil(all.session(p.key)); XCTAssertNotNil(all.session(q.key))
        XCTAssertEqual(all.counter, 1)
        let sameDay = all.sessions.filter { $0.dayKey == "2026-09-15" && $0.madeInApp }.map(\.key)
        XCTAssertEqual(sameDay, sameDay.sorted(), "on the day, by key, the same everywhere")
        XCTAssertEqual(Set(all.extras.map(\.row)).count, all.extras.count)
        XCTAssertNoThrow(try PlanExport.workbook(all, template: try fixture()), "the spreadsheet copy reads back")
        XCTAssertEqual(try bytes(all), try bytes(try m(phoneX, padX)))
    }

    func testCase4_ClockSkew() throws {
        let b = try base()
        var mac = b, phone = b
        // Mac's clock is 10 minutes behind: it edits at real 10:15 and its clock says 10:05.
        try edit(&mac, bike12, 5 * 60) { $0.minutes = 11 }        // real 10:15, written 10:05
        try edit(&phone, bike12, 10 * 60) { $0.minutes = 22 }     // real 10:10
        let all = try m(mac, phone)
        XCTAssertEqual(all.draft(of: bike12)?.minutes, 22, "the known limit: the iPhone's mark is later")
        XCTAssertEqual(try bytes(all), try bytes(try m(phone, mac)))

        // A device's own marks never go backwards.
        var one = b
        let s0 = one
        try one.remove(swim9, now: at(1000))                       // ensure unrelated stuff
        var w = try XCTUnwrap(one.session(bike12))
        w.title = "First"
        one.sessions = one.sessions.map { $0.key == bike12 ? w : $0 }
        let first = one.stamped(after: s0, now: at(100))
        let firstStamp = try XCTUnwrap(first.stamps[bike12])
        XCTAssertEqual(firstStamp, at(100))
        var again = first
        w.title = "Second"
        again.sessions = again.sessions.map { $0.key == bike12 ? w : $0 }
        let second = again.stamped(after: first, now: at(50))     // the clock was set back
        XCTAssertEqual(second.stamps[bike12].map(PlanBook.ms), PlanBook.ms(firstStamp) + 1)
    }

    func testCase5_OfflineForWeeks() throws {
        let b = try base()
        var pad = b, phone = b
        try log(&pad, run16, "35", 100)
        try extra(&pad, "pad-1", "2026-09-14", 101)
        // The phone: forty changes and two removals.
        let keys = [bike12, bike15, run13, run10]
        for i in 0..<40 {
            let key = keys[i % keys.count]
            try edit(&phone, key, 200 + Double(i)) { $0.minutes = Double(30 + i) }
        }
        try phone.remove(swim9, now: at(300))
        try phone.remove(bike19, now: at(301))
        try extra(&phone, "phone-1", "2026-09-14", 302)
        let all = try m(pad, phone)
        XCTAssertEqual(all.session(run16)?.results["actualDuration"]?.text, "35", "the iPad's one log survives")
        XCTAssertEqual(all.changes.count, 42)
        for key in keys { XCTAssertEqual(all.draft(of: key), phone.draft(of: key), "nothing of the forty is undone") }
        XCTAssertNil(all.session(swim9)); XCTAssertNil(all.session(bike19))
        XCTAssertNotNil(all.removed[swim9]); XCTAssertNotNil(all.removed[bike19])
        XCTAssertEqual(Set(all.extras.compactMap { $0.ref.isEmpty ? nil : $0.ref }), ["pad-1", "phone-1", "xtest001"])
        XCTAssertEqual(Set(all.extras.map(\.row)).count, all.extras.count)
        XCTAssertEqual(try bytes(all), try bytes(try m(phone, pad)))
    }

    func testCase6_ADeviceThatStillThoughtExcelWasHome() throws {
        // The book in iCloud; B has two entries waiting from before it knew.
        var cloud = try base()
        try edit(&cloud, run13, 10) { $0.minutes = 44 }
        let old = try base()
        let waiting = try [bike12, run10].map { key -> QueuedEntry in
            var e = LogEntry(); e.actualDuration = "50"
            return QueuedEntry(workout: try XCTUnwrap(old.session(key)), entry: e, now: at(20))
        }
        // B adopts the book (never merges its own view into it) and writes its waiting entries in.
        var adopted = cloud
        for q in waiting { XCTAssertEqual(try adopted.apply(q, now: at(21)), .written) }
        XCTAssertEqual(adopted.session(bike12)?.results["actualDuration"]?.text, "50")
        XCTAssertEqual(adopted.draft(of: run13)?.minutes, 44)
        XCTAssertEqual(try bytes(try m(adopted, cloud)).count, try bytes(adopted).count)

        // A B that imported on its own: two plans, nothing merged.
        let own = try base(takenAt: 500)
        XCTAssertThrowsError(try m(cloud, own)) { error in
            guard case BookMerge.Refusal.differentPlan = error else { return XCTFail("wrong refusal \(error)") }
        }
        let join = BookMerge.join(local: own, cloud: [cloud], cloudFileThere: true)
        XCTAssertNotNil(join.refused)
        XCTAssertFalse(join.changesLocal); XCTAssertFalse(join.changesCloud)
        XCTAssertEqual(join.book, own)
        // The refusal reads the same either way round.
        do { _ = try m(own, cloud) } catch let e as BookMerge.Refusal {
            do { _ = try m(cloud, own) } catch let f as BookMerge.Refusal { XCTAssertEqual(e, f) }
        }
    }

    func testCase7_AnOlderAppReadingANewerBook() throws {
        let local = try base()
        var newer = local
        newer.format = 3
        let decoded = try PlanBook.decoded(try newer.encoded())
        XCTAssertEqual(decoded.format, 3, "a newer format stays as it was read")
        XCTAssertTrue(decoded.isFromNewerApp)
        let join = BookMerge.join(local: local, cloud: [decoded], cloudFileThere: true)
        XCTAssertEqual(join.refused, .newerFormat(3))
        XCTAssertFalse(join.changesLocal); XCTAssertFalse(join.changesCloud)
        XCTAssertEqual(join.book, local)
        XCTAssertThrowsError(try m(local, newer)) { XCTAssertEqual($0 as? BookMerge.Refusal, .newerFormat(3)) }
        XCTAssertThrowsError(try BookMerge.merged([local, newer]))
    }

    func testCase8_AConflictVersionFromICloud() throws {
        let b = try base()
        var x = b, y = b, l = b
        try edit(&x, run13, 10) { $0.minutes = 21 }
        try log(&y, bike12, "55", 11)
        try edit(&l, bike15, 12) { $0.minutes = 66 }
        let join = BookMerge.join(local: l, cloud: [x, y], cloudFileThere: true)
        XCTAssertNil(join.refused)
        XCTAssertEqual(join.book.draft(of: run13)?.minutes, 21)
        XCTAssertEqual(join.book.session(bike12)?.results["actualDuration"]?.text, "55")
        XCTAssertEqual(join.book.draft(of: bike15)?.minutes, 66)
        XCTAssertTrue(join.changesLocal)
        XCTAssertTrue(join.changesCloud, "so the file is rewritten and the conflict resolved")
        // The next meeting is quiet: joined == file, no conflicts left.
        let quiet = BookMerge.join(local: join.book, cloud: [join.book], cloudFileThere: true)
        XCTAssertFalse(quiet.changesLocal); XCTAssertFalse(quiet.changesCloud)
    }

    // MARK: the small rules

    func testAMissingICloudFileNeverEmptiesTheDevice() throws {
        var l = try base()
        try log(&l, bike12, "60", 10)
        let join = BookMerge.join(local: l, cloud: [], cloudFileThere: false)
        XCTAssertEqual(join.book.sessions.count, l.sessions.count)
        XCTAssertEqual(join.book.session(bike12)?.results, l.session(bike12)?.results)
        XCTAssertFalse(join.changesLocal)
        XCTAssertTrue(join.changesCloud, "the file is written")
        XCTAssertEqual(join.takenAway, [])
    }

    func testTakenAwayNamesWhatTheMeetingRemovesHere() throws {
        let b = try base()
        var local = b, cloud = b
        try log(&local, swim9, "40", 10)
        cloud = try m(cloud, local)                 // the other device saw the log, then took the session out
        try cloud.remove(swim9, now: at(20))
        try cloud.remove(run16, now: at(21))
        let join = BookMerge.join(local: local, cloud: [cloud], cloudFileThere: true)
        XCTAssertEqual(join.takenAway, [swim9, run16].sorted())
        XCTAssertTrue(join.changesLocal)
    }

    func testAnOldFormatBookOpensUnchangedAndReSavesEqual() throws {
        // A 2.0 document: format 1, no moves, no extras line, one logged session with its one stamp.
        var b = try base()
        try log(&b, bike12, "60", 10)
        try edit(&b, run13, 20) { $0.minutes = 30 }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try b.encoded()) as? [String: Any])
        object["format"] = 1
        object["moves"] = nil
        var origin = try XCTUnwrap(object["origin"] as? [String: Any])
        origin["extrasLastRow"] = nil; origin["originalHash"] = nil
        object["origin"] = origin
        var stamps = try XCTUnwrap(object["stamps"] as? [String: Any])
        for k in stamps.keys where k.hasPrefix("log:") { stamps[k] = nil }
        stamps[bike12] = PlanBook.ms(at(10))            // 2.0 stamped a log on the one mark the session had
        object["stamps"] = stamps
        let old = try JSONSerialization.data(withJSONObject: object)

        let opened = try PlanBook.decoded(old)
        XCTAssertEqual(PlanImport.differences(b.sessions, opened.sessions), [])
        XCTAssertEqual(opened.sessions, b.sessions)
        XCTAssertEqual(opened.extras, b.extras)
        XCTAssertEqual(opened.changes, b.changes)
        XCTAssertEqual(opened.format, 2)
        XCTAssertTrue(opened.moves.isEmpty)
        // The log took the stamp the session had; nothing is stamped "now".
        XCTAssertEqual(opened.stamps["log:" + bike12], at(10))
        XCTAssertNil(opened.stamps["log:" + run13], "never logged: no log stamp")
        XCTAssertEqual(opened.stamps[run13], at(20))
        XCTAssertTrue(opened.stamps.values.allSatisfy { $0 == at(10) || $0 == at(20) })
        XCTAssertNotNil(opened.origin.extrasLastRow)
        // Re-saved and read again: equal.
        let again = try PlanBook.decoded(try opened.encoded())
        XCTAssertEqual(again, opened)
        XCTAssertEqual(try bytes(again), try bytes(opened))
        // And two old-format documents merge.
        let other = try PlanBook.decoded(old)
        XCTAssertEqual(try bytes(try m(opened, other)), try bytes(try m(other, opened)))
        XCTAssertEqual(try m(opened, other).session(bike12)?.results, b.session(bike12)?.results)
    }

    func testAnImportedBookWithNoMarksStillMergesAndABaselineIsNeverNow() throws {
        let b = try base()
        XCTAssertTrue(b.stamps.isEmpty)
        var phone = b.baselined(rank: 3), mac = b.baselined(rank: 1)
        XCTAssertTrue(phone.stamps.values.allSatisfy { $0.timeIntervalSince1970 < 1_000_000_000 }, "a day in 2001, not now")
        try log(&phone, bike12, "10", 5)
        try log(&mac, bike12, "20", 6)
        // Merged: a real mark beats a baseline whichever device it is on.
        XCTAssertEqual(try m(phone, mac).session(bike12)?.results["actualDuration"]?.text, "20")
        // Two baselines that differ: the higher rank (the phone) wins, the same everywhere.
        var x = b, y = b
        x.sessions = x.sessions.map { $0.key == run10 ? $0.titled("Mac title") : $0 }
        y.sessions = y.sessions.map { $0.key == run10 ? $0.titled("Phone title") : $0 }
        let all = try m(x.baselined(rank: 1), y.baselined(rank: 3))
        XCTAssertEqual(all.session(run10)?.title, "Phone title")
        XCTAssertEqual(try bytes(all), try bytes(try m(y.baselined(rank: 3), x.baselined(rank: 1))))
    }

    func testStampedMarksOnlyWhatChangedAndKeepsThePlanAndLogSidesApart() throws {
        let b = try base()
        var c = b
        var w = try XCTUnwrap(c.session(bike12))
        w.results["actualDuration"] = ResultValue(text: "60", number: 60, date: nil)
        w.loggedInSheet = true
        var v = try XCTUnwrap(c.session(run13))
        v.title = "Renamed"
        c.sessions = c.sessions.map { $0.key == bike12 ? w : ($0.key == run13 ? v : $0) }
        let s = c.stamped(after: b, now: at(7))
        XCTAssertEqual(s.stamps["log:" + bike12], at(7))
        XCTAssertNil(s.stamps[bike12], "a log is not a change of plan")
        XCTAssertEqual(s.stamps[run13], at(7))
        XCTAssertNil(s.stamps["log:" + run13])
        XCTAssertEqual(s.stamps.count, 2)
        // A session that vanished gets a removed mark later than anything it had.
        var gone = s
        gone.sessions.removeAll { $0.key == bike12 }
        let r = gone.stamped(after: s, now: at(3))
        XCTAssertEqual(r.removed[bike12].map(PlanBook.ms), PlanBook.ms(at(7)) + 1)
        // An extra edited elsewhere in its row alone is not a change.
        let none = b.stamped(after: b, now: at(9))
        XCTAssertTrue(none.stamps.isEmpty)
    }

    func testAnEntryThatMovesADayMarksThePlanSideAndOneThatLogsMarksTheLogSide() throws {
        var b = try base()
        try log(&b, run10, "30", 10)
        XCTAssertEqual(b.stamps["log:" + run10], at(10))
        XCTAssertNil(b.stamps[run10])
    }
}

private extension Workout {
    func titled(_ t: String) -> Workout { var w = self; w.title = t; return w }
}
