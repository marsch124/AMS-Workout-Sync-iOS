import XCTest
@testable import WorkoutCore

/*
 * What travels through iCloud besides the merge itself (2.1): the diary, the
 * Health numbers the iPhone shares, and two devices meeting through a plain
 * folder exactly the way the app meets the iCloud folder (CloudFiles +
 * PlanMeeting). An invented plan only.
 */
final class CloudMeetingTests: XCTestCase {
    private let bike12 = "Weekly Schedules!6"
    private let run13 = "Weekly Schedules!7"
    private let t0 = 1_789_000_000.0
    private func at(_ s: Double) -> Date { Date(timeIntervalSince1970: t0 + s) }

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try Data(contentsOf: url)
    }

    private func base() throws -> PlanBook {
        try PlanImport.read(try fixture(), fileName: "plan.xlsx", today: "2026-09-16", now: at(0)).book
    }

    // MARK: the diary

    func testDiaryTheNewestAnswerPerDayWinsWhicheverDeviceIsNamedFirst() {
        var phone = DiaryDoc(), pad = DiaryDoc()
        phone.setFeel(3, on: "2026-11-24", now: at(10))
        pad.setFeel(5, on: "2026-11-24", now: at(20))       // later: wins
        phone.setFeel(2, on: "2026-11-25", now: at(30))     // only on the phone: kept
        pad.setAnswer(7, for: "H1", now: at(5))
        phone.setAnswer(4, for: "H1", now: at(40))          // later: wins
        let one = DiaryDoc.merged(phone, pad), two = DiaryDoc.merged(pad, phone)
        XCTAssertEqual(one, two)
        XCTAssertEqual(one.feel, ["2026-11-24": 5, "2026-11-25": 2])
        XCTAssertEqual(one.answers, ["H1": 4])
        XCTAssertEqual(DiaryDoc.merged(one, one), one, "joining twice is joining once")
    }

    func testDiaryAnAnswerWithoutAMarkLosesToOneWithAndTheSameMarkPicksTheSameEverywhere() {
        let old = DiaryDoc(feel: ["2026-11-20": 1])          // from before 2.1: no marks
        var new = DiaryDoc(); new.setFeel(4, on: "2026-11-20", now: at(1))
        XCTAssertEqual(DiaryDoc.merged(old, new).feel["2026-11-20"], 4)
        let x = DiaryDoc(feel: ["d": 2], stamps: ["feel:d": at(1)]), y = DiaryDoc(feel: ["d": 3], stamps: ["feel:d": at(1)])
        XCTAssertEqual(DiaryDoc.merged(x, y), DiaryDoc.merged(y, x))
    }

    func testDiaryAMissingICloudFileKeepsEverythingAndANewerOneIsRefused() throws {
        var mine = DiaryDoc(); mine.setFeel(3, on: "2026-11-25", now: at(1))
        let join = DiaryDoc.join(local: mine, cloud: [], cloudFileThere: false)
        XCTAssertEqual(join.doc.feel, mine.feel)
        XCTAssertFalse(join.changesLocal)
        XCTAssertTrue(join.changesCloud)
        var newer = DiaryDoc(); newer.format = 9
        let refused = DiaryDoc.join(local: mine, cloud: [newer], cloudFileThere: true)
        XCTAssertTrue(refused.newerApp)
        XCTAssertFalse(refused.changesLocal || refused.changesCloud)
        // A mark never goes backwards, even with the clock set back.
        var d = DiaryDoc(); d.setFeel(3, on: "x", now: at(100)); d.setFeel(4, on: "x", now: at(50))
        XCTAssertGreaterThan(try XCTUnwrap(d.stamps["feel:x"]), at(100))
        XCTAssertEqual(try DiaryDoc.decoded(try d.encoded()), d)
    }

    // MARK: Health from the iPhone

    func testHealthShareOlderThan18HoursReadsYesterday() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let written = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 7, minute: 12))!
        let share = HealthShare(writtenAt: written)
        let soon = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 9, minute: 0))!
        XCTAssertEqual(share.asOfWords(now: soon, calendar: cal), "from iPhone, as of 07:12")
        XCTAssertFalse(share.isStale(now: soon))
        let nextMorning = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9, minute: 0))!
        XCTAssertTrue(share.isStale(now: nextMorning))
        XCTAssertEqual(share.asOfWords(now: nextMorning, calendar: cal), "from iPhone, yesterday 07:12")
        let later = cal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 9, minute: 0))!
        XCTAssertEqual(share.asOfWords(now: later, calendar: cal), "from iPhone, 24 Nov 07:12")
    }

    func testHealthShareReadsAFileWithUnknownFieldsAndLosesOnlyABadWorkout() throws {
        let json = """
        {"format":2,"writtenAt":1789000000000,"somethingNew":{"a":1},
         "mornings":{"2026-11-25":{"readAt":1789000000000,"restingHR":48,"hrv":61,"restingDays":13,"hrvDays":13,"extra":true}},
         "workouts":[{"id":"A","dayKey":"2026-11-25","sport":"run","typeName":"Run","start":1789000000000,"seconds":1800,"source":"Watch","cadence":80},
                     {"broken":true}],
         "found":[{"id":"F","dayKey":"2026-11-24","sport":"walk","name":"Hike","minutes":90}]}
        """
        let share = try HealthShare.decoded(Data(json.utf8))
        XCTAssertEqual(share.mornings["2026-11-25"]?.restingHR, 48)
        XCTAssertEqual(share.mornings["2026-11-25"]?.sleepHours, nil)
        XCTAssertEqual(share.workouts.map(\.id), ["A"])
        XCTAssertEqual(share.found.map(\.id), ["F"])
        XCTAssertEqual(share.morning(onOrBefore: "2026-11-26")?.day, "2026-11-25")
        let older = HealthShare(writtenAt: at(0)), newer = HealthShare(writtenAt: at(60))
        XCTAssertEqual(HealthShare.newest([newer, older]), newer)
    }

    // MARK: two devices through one folder

    private struct Device {
        let rank: Int
        var book: PlanBook?
        var copiesBeforeReplacing = 0

        /* The Store's save: marks by difference. */
        mutating func change(_ now: Date, _ body: (inout PlanBook) throws -> Void) rethrows {
            guard let old = book else { return }
            var b = old
            try body(&b)
            book = b.stamped(after: old, now: now)
        }

        /* One meeting, the way PlanCloud does it. */
        mutating func meet(_ file: URL) {
            let read = CloudFiles.read(file)
            guard let local = book else {
                if case .success(let adopted)? = PlanMeeting.adoptable(read) { book = adopted }
                return
            }
            let outcome = PlanMeeting.meet(local: local, rank: rank, read: read)
            guard let join = outcome.join, join.refused == nil else { return }
            if join.changesLocal { copiesBeforeReplacing += 1; book = join.book }
            if join.changesCloud { CloudFiles.write(try! join.book.encoded(), to: file, resolving: outcome.mergedConflicts) }
        }
    }

    func testTwoDevicesMeetThroughAFolderAndNothingLoggedIsLost() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amsws-meet-\(UUID().uuidString)/Sync")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let file = folder.appendingPathComponent("plan.json")
        XCTAssertEqual(CloudFiles.read(file), .absent, "a missing file is absent, not empty")

        var phone = Device(rank: 3, book: try base())
        var mac = Device(rank: 1, book: nil)
        mac.meet(file)
        XCTAssertNil(mac.book, "nothing in iCloud yet: the Mac waits")

        phone.meet(file)                                       // the phone puts the plan up
        mac.meet(file)                                         // the Mac, with no plan of its own, takes it
        XCTAssertEqual(mac.book?.sessions.count, phone.book?.sessions.count)

        // Each changes something while apart.
        try phone.change(at(100)) { b in
            let w = try XCTUnwrap(b.session(bike12))
            var e = LogEntry(); e.actualDuration = "61"
            try b.apply(QueuedEntry(workout: w, entry: e, now: at(100)), now: at(100))
        }
        try mac.change(at(200)) { b in
            var d = try XCTUnwrap(b.draft(of: run13)); d.minutes = 33
            try b.change(run13, to: d, now: at(200))
        }
        mac.meet(file); phone.meet(file); mac.meet(file)

        let p = try XCTUnwrap(phone.book), m = try XCTUnwrap(mac.book)
        XCTAssertEqual(try p.encoded(), try m.encoded(), "both devices hold the same plan")
        XCTAssertEqual(p.session(bike12)?.results["actualDuration"]?.text, "61", "the phone's log survived")
        XCTAssertEqual(p.draft(of: run13)?.minutes, 33, "the Mac's change survived")
        XCTAssertEqual(try PlanBook.decoded(try Data(contentsOf: file)).encoded(), try p.encoded(), "iCloud holds it too")

        // Meeting again changes nothing anywhere.
        let before = try Data(contentsOf: file)
        phone.meet(file); mac.meet(file)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testAnUnreadableOrNewerICloudFileIsNeverTakenForEmpty() throws {
        let local = try base()
        let damaged = PlanMeeting.meet(local: local, rank: 3, read: .found(Data("{not json".utf8), conflicts: [], modified: at(0)))
        XCTAssertEqual(damaged.unreadable, Data("{not json".utf8), "kept before anything is written over it")
        XCTAssertEqual(damaged.join?.book.sessions.count, local.sessions.count)
        XCTAssertEqual(damaged.join?.changesLocal, false)

        let newer = PlanMeeting.meet(local: local, rank: 3, read: .found(Data(#"{"format":3}"#.utf8), conflicts: [], modified: at(0)))
        XCTAssertEqual(newer.join?.refused, .newerFormat(3))
        XCTAssertEqual(newer.join?.changesCloud, false)

        XCTAssertNil(PlanMeeting.meet(local: local, rank: 3, read: .waiting).join, "still downloading: nothing is done")
        XCTAssertNil(PlanMeeting.adoptable(.absent))
        if case .failure(let r)? = PlanMeeting.adoptable(.found(Data(#"{"format":3}"#.utf8), conflicts: [], modified: at(0))) {
            XCTAssertEqual(r, .newerFormat(3))
        } else { XCTFail("a newer book is not adopted") }
    }
}
