import XCTest
@testable import WorkoutCore

/*
 * The data-safety review of the iCloud sharing (25 Nov 2026): a device that
 * writes before it knows, a safety copy put back on a shared plan, the list of
 * entries already written, conflict copies, two different plans — and a soak
 * of two devices doing everything at random. An invented plan only.
 */
final class CloudSafetyTests: XCTestCase {
    private let swim9 = "Weekly Schedules!2"
    private let run10 = "Weekly Schedules!4"
    private let bike12 = "Weekly Schedules!6"
    private let run13 = "Weekly Schedules!7"
    private let bike15 = "Weekly Schedules!10"
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

    /* The Store's save: the change, then marks by difference. */
    private func saved(_ book: PlanBook, _ s: Double, _ body: (inout PlanBook) throws -> Void) rethrows -> PlanBook {
        var b = book
        try body(&b)
        return b.stamped(after: book, now: at(s))
    }

    // MARK: S3 — writing up only when it is safe

    func testADeviceWithAPlanWritesItUpOnlyWhenNoOtherDeviceHoldsThePlan() {
        XCTAssertTrue(PlanMeeting.shouldWriteUp(localHasPlan: true, cloudFileThere: true, otherDevices: ["app"]), "the file is there: joined, then written")
        XCTAssertTrue(PlanMeeting.shouldWriteUp(localHasPlan: true, cloudFileThere: false, otherDevices: []), "the first device puts it up")
        XCTAssertTrue(PlanMeeting.shouldWriteUp(localHasPlan: true, cloudFileThere: false, otherDevices: ["excel", "none"]))
        XCTAssertFalse(PlanMeeting.shouldWriteUp(localHasPlan: true, cloudFileThere: false, otherDevices: ["none", "app"]),
                       "another device's plan lives in the app: the file is on its way, wait")
        XCTAssertFalse(PlanMeeting.shouldWriteUp(localHasPlan: false, cloudFileThere: true, otherDevices: []))
    }

    // MARK: S5 — a safety copy put back on a shared plan

    func testASafetyCopyPutBackOnASharedPlanTakesThePlanBackAndKeepsWhatWasLoggedSince() throws {
        var now = try base()
        now = try saved(now, 10) { try log(&$0, bike12, "50", 10) }
        let copy = now                                                    // the copy of that morning
        let wasRun13 = try XCTUnwrap(copy.draft(of: run13))
        now = try saved(now, 20) { b in var d = try XCTUnwrap(b.draft(of: run13)); d.minutes = 99; try b.change(run13, to: d, now: at(20)) }
        now = try saved(now, 21) { try $0.remove(bike15, now: at(21)) }
        now = try saved(now, 22) { try log(&$0, run10, "31", 22) }
        var logged = ""
        now = try saved(now, 23) { b in
            logged = try b.add(SessionDraft(dayKey: "2026-09-17", sport: "run", title: "Added and logged", minutes: 20), now: at(23)).key
        }
        now = try saved(now, 24) { try log(&$0, logged, "20", 24) }
        var unlogged = ""
        now = try saved(now, 25) { b in
            unlogged = try b.add(SessionDraft(dayKey: "2026-09-18", sport: "bike", title: "Added only", minutes: 30), now: at(25)).key
        }
        now = try saved(now, 26) { try log(&$0, bike12, "77", 26) }
        let other = now                                                   // the Mac, which has all of it

        let back = try XCTUnwrap(PlanBook.putBack(copy, over: now, now: at(100)))
        XCTAssertEqual(back.draft(of: run13), wasRun13, "the plan side goes back")
        XCTAssertNotNil(back.session(bike15), "a session taken out since comes back")
        XCTAssertNil(back.session(unlogged), "added since and never logged: goes")
        XCTAssertEqual(back.session(run10)?.results["actualDuration"]?.text, "31", "logged since: stays")
        XCTAssertEqual(back.session(logged)?.results["actualDuration"]?.text, "20", "added and logged since: stays")
        XCTAssertEqual(back.session(bike12)?.results["actualDuration"]?.text, "77", "the newer log, not the copy's")

        // The other device takes it the same way: the plan side is the newest change, the logs are kept.
        for all in [try BookMerge.merged(back, other), try BookMerge.merged(other, back)] {
            XCTAssertEqual(all.draft(of: run13), wasRun13)
            XCTAssertNotNil(all.session(bike15))
            XCTAssertNil(all.session(unlogged))
            XCTAssertEqual(all.session(run10)?.results["actualDuration"]?.text, "31")
            XCTAssertEqual(all.session(logged)?.results["actualDuration"]?.text, "20")
            XCTAssertEqual(all.session(bike12)?.results["actualDuration"]?.text, "77")
        }
        XCTAssertEqual(try BookMerge.merged(back, other).encoded(), try BookMerge.merged(other, back).encoded())

        // A copy of another plan (a second move into the app) is not mixed in.
        XCTAssertNil(PlanBook.putBack(try base(takenAt: 500), over: now, now: at(100)))
    }

    func testAnUndoneRemovalBringsTheOldLogBackWithItsOwnMarkNotNow() throws {
        var mac = try base()
        mac = try saved(mac, 10) { try log(&$0, swim9, "40", 10) }
        var phone = mac
        var removal: PlanChange?
        mac = try saved(mac, 20) { removal = try $0.remove(swim9, now: at(20)) }
        phone = try saved(phone, 30) { try log(&$0, swim9, "45", 30) }       // a newer log the Mac never saw
        let removalID = try XCTUnwrap(removal?.id)
        mac = try saved(mac, 40) { try $0.undo(removalID, now: at(40)) }
        XCTAssertEqual(mac.stamps["log:" + swim9], at(10), "the log that came back keeps its own mark")
        let all = try BookMerge.merged(mac, phone)
        XCTAssertEqual(all.session(swim9)?.results["actualDuration"]?.text, "45", "the newer log wins, not the undone one")
        XCTAssertEqual(try all.encoded(), try BookMerge.merged(phone, mac).encoded())
    }

    // MARK: M2 — entries already written, trimmed by age

    func testTheListOfEntriesAlreadyWrittenKeepsTheNewestAfterAMerge() throws {
        var a = try base()
        let b = a
        // "id000" is the newest, "id299" the oldest: A–Z is the wrong way round on purpose.
        a.applied = (0..<300).map { String(format: "id%03d", $0) }.reversed()
        for (i, id) in a.applied.enumerated() { a.appliedAt[id] = at(Double(i)) }
        var joined = try BookMerge.merged(a, b)
        XCTAssertEqual(joined.applied.first, "id299", "oldest first")
        XCTAssertEqual(joined.applied, try BookMerge.merged(b, a).applied)
        var x = ExtraEntry(date: "2026-09-14", activity: "run", ref: "new-1"); x.minutes = 10
        XCTAssertEqual(try joined.apply(QueuedEntry(extra: x), now: at(1000)), .written)
        XCTAssertEqual(joined.applied.count, 300)
        XCTAssertTrue(joined.applied.contains("id000"), "the newest stays")
        XCTAssertFalse(joined.applied.contains("id299"), "the oldest goes")
        XCTAssertNil(joined.appliedAt["id299"])
        // A merge never trims.
        var big = a
        big.applied += ["more-1", "more-2"]
        XCTAssertEqual(try BookMerge.merged(big, b).applied.count, 302)
    }

    // MARK: M5 — a conflict copy that brought nothing new

    func testAConflictCopyThatBroughtNothingNewIsClearedWithoutAWrite() throws {
        var file = try base()
        file = try saved(file, 10) { try log(&$0, bike12, "50", 10) }
        let quiet = BookMerge.join(local: file, cloud: [file, file], cloudFileThere: true)
        XCTAssertFalse(quiet.changesCloud, "nothing new: the file is not written again")
        XCTAssertTrue(quiet.clearConflicts, "the copy is only cleared")
        var copy = file
        copy = try saved(copy, 20) { try log(&$0, run13, "30", 20) }
        let news = BookMerge.join(local: file, cloud: [file, copy], cloudFileThere: true)
        XCTAssertTrue(news.changesCloud)
        XCTAssertTrue(news.clearConflicts)
        XCTAssertFalse(BookMerge.join(local: file, cloud: [file], cloudFileThere: true).clearConflicts)
    }

    // MARK: S2 — the plan that really differs

    func testTwoDifferentPlansNameTheBookThatReallyDiffers() throws {
        var mine = try base()
        mine = try saved(mine, 10) { try log(&$0, bike12, "50", 10) }
        let other = try base(takenAt: 500)
        let otherBytes = try other.encoded()
        // The file is this device's plan, a conflict copy beside it is the other one.
        let a = PlanMeeting.meet(local: mine, rank: 3, read: .found(try mine.encoded(), conflicts: [otherBytes], modified: at(0)))
        if case .differentPlan? = a.join?.refused {} else { XCTFail("refused as two plans") }
        XCTAssertEqual(a.otherPlan, other)
        XCTAssertTrue(a.otherPlanIsConflict)
        XCTAssertEqual(a.otherPlanBytes, otherBytes)
        XCTAssertEqual(a.join?.changesCloud, false)
        // The file itself is the other plan.
        let b = PlanMeeting.meet(local: mine, rank: 3, read: .found(otherBytes, conflicts: [], modified: at(0)))
        XCTAssertEqual(b.otherPlan, other)
        XCTAssertFalse(b.otherPlanIsConflict)
        XCTAssertEqual(b.join?.changesLocal, false)
    }

    // MARK: the soak

    /* A fixed-seed random stream: the same rounds on every run. */
    private struct Dice {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
    }

    private func randomStep(_ book: PlanBook, _ dice: inout Dice, _ s: Double, _ tag: String) -> PlanBook {
        var b = book
        let keys = b.sessions.map(\.key)
        let key = keys.isEmpty ? "" : keys[dice.int(keys.count)]
        do {
            switch dice.int(6) {
            case 0, 1:
                if let w = b.session(key) {
                    var e = LogEntry(); e.actualDuration = String(10 + dice.int(80))
                    try b.apply(QueuedEntry(workout: w, entry: e, now: at(s)), now: at(s))
                }
            case 2:
                if var d = b.draft(of: key) { d.minutes = Double(15 + dice.int(90)); try b.change(key, to: d, now: at(s)) }
            case 3:
                if keys.count > 6 { try b.remove(key, now: at(s)) }
            case 4:
                if dice.int(2) == 0 {
                    _ = try b.add(SessionDraft(dayKey: "2026-09-1\(dice.int(9))", sport: "run", title: "Soak \(tag)", minutes: 30), now: at(s))
                } else {
                    var x = ExtraEntry(date: "2026-09-1\(dice.int(9))", activity: "walk", ref: "soak-\(tag)"); x.minutes = 20
                    try b.apply(extra: x, now: at(s))
                }
            default:
                // The newest change still standing per session: the ones canUndo allows (worked out in one pass).
                var seen = Set<String>(), open: [PlanChange] = []
                for c in b.changes.reversed() where !c.undone {
                    if seen.insert(c.key).inserted { open.append(c) }
                }
                if !open.isEmpty { try b.undo(open[dice.int(open.count)].id, now: at(s)) }
            }
        } catch {
            return book
        }
        return b.stamped(after: book, now: at(s))
    }

    /* Every session logged on a device before a meeting is, after it, in the plan with a log — or was taken out by a device that saw that log (or a newer one). */
    private func nothingLost(_ device: PlanBook, in all: PlanBook, round: Int) {
        for w in device.sessions where !w.results.isEmpty {
            if let there = all.session(w.key), !there.results.isEmpty { continue }
            let mark = device.stamps["log:" + w.key] ?? .distantPast
            let seen = all.changes.contains { c in
                c.kind == "remove" && c.key == w.key && !c.undone && !(c.undo?.results.isEmpty ?? true)
                    && (c.undo?.results == w.results || (c.logAt ?? .distantPast) >= mark)
            }
            XCTAssertTrue(seen, "round \(round): the log on \(w.key) was lost")
        }
    }

    func testSoakTwoDevicesFiveHundredRoundsTheSameEitherWayAndNoLogLost() throws {
        let start = try base()
        var phone = start.baselined(rank: 3), mac = start.baselined(rank: 1)
        var dice = Dice(state: 20261125)
        var clock = 0.0
        for round in 0..<500 {
            for _ in 0..<(1 + dice.int(3)) { clock += 1; phone = randomStep(phone, &dice, clock, "p\(round)") }
            for _ in 0..<(1 + dice.int(3)) { clock += 1; mac = randomStep(mac, &dice, clock - 2, "m\(round)") }    // the Mac's clock is 2 s behind
            let one = try BookMerge.merged(phone, mac), two = try BookMerge.merged(mac, phone)
            // Equal books encode to equal bytes (sorted keys, ms dates); the bytes themselves are compared every 25th round, to keep it quick.
            XCTAssertEqual(one, two, "round \(round): the same in either order")
            if round % 25 == 0 {
                let bytes = try one.encoded()
                XCTAssertEqual(bytes, try two.encoded(), "round \(round): the same bytes in either order")
                XCTAssertEqual(try BookMerge.merged(one, one).encoded(), bytes, "joining twice is joining once")
            }
            nothingLost(phone, in: one, round: round)
            nothingLost(mac, in: one, round: round)
            // The phone always meets; the Mac is sometimes away for a while.
            phone = one
            if dice.int(10) < 6 { mac = one }
        }
    }

    /* 2.4.1: an iPad or Mac that only shows the old workbook takes iCloud's plan; the iPhone on Excel is asked instead. */
    func testAnIPadOrMacShowingTheOldWorkbookTakesTheCloudPlan() {
        XCTAssertTrue(PlanMeeting.takesCloudPlanOverWorkbook(isPhone: false, cloudHasPlan: true))
        XCTAssertFalse(PlanMeeting.takesCloudPlanOverWorkbook(isPhone: false, cloudHasPlan: false), "nothing in iCloud: the workbook stays on screen")
        XCTAssertFalse(PlanMeeting.takesCloudPlanOverWorkbook(isPhone: true, cloudHasPlan: true), "the iPhone decides on its move-in page")
    }
}
