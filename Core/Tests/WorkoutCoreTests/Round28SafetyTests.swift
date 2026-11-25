import XCTest
@testable import WorkoutCore

/*
 * Round 28, data safety: what this round writes must stay readable by the
 * builds already on his other devices, Save must never log twice, a repeat's
 * Undo never takes a logged session, and odd answers from outside never crash.
 * Every figure here is invented.
 */
final class Round28SafetyTests: XCTestCase {

    // MARK: the suggestion notes, read by a build from before round 28

    /* The trigger list as builds up to 2.7 (branch main) know it: no "AW". */
    private enum OldTrigger: String, Decodable { case section5 = "S5", cameInBreaking = "IN", t1 = "T1", t2 = "T2", t3 = "T3", t4 = "T4", t5 = "T5", t6 = "T6", hurts = "Q2", backToBack = "Q1" }
    private struct OldRecord: Decodable { let day: String; let trigger: OldTrigger; let key: String; let answer: RBAnswer? }
    private struct OldEntry: Decodable { let record: OldRecord }
    /* The old file's parts that must read; an unknown trigger anywhere in `entries` made the whole file unreadable. */
    private struct OldKeep: Decodable {
        let format: Int?
        let entries: [OldEntry]?
        let health: RBHealthTaps?
        let stopStamp: PauseStamp?
        let illStamp: PauseStamp?
    }

    private func record(_ trigger: RBTrigger, _ day: String, _ key: String) -> SuggestionRecord {
        SuggestionRecord(day: day, trigger: trigger, step: 1, key: key, headline: "Invented \(key)", why: "Why: invented.",
                         choices: [[]], tried: [], sessions: [key], closesOn: day)
    }

    func testAnAwayCardNeverMakesTheNotesUnreadableForAnOlderBuild() throws {
        XCTAssertEqual(Set(RBTrigger.allCases).subtracting(SuggestionKeep.triggersOlderBuildsKnow), [.away],
                       "a new trigger must be added to the older-builds list only once every device knows it")
        var keep = SuggestionKeep()
        keep.on = true
        keep.entries = [SuggestionEntry(record: record(.t1, "2030-01-07", "a")),
                        SuggestionEntry(record: record(.away, "2030-01-08", "b")),
                        SuggestionEntry(record: record(.t4, "2030-01-09", "c"))]
        keep.entries[1].record.answer = .keptPlan
        let data = try keep.encoded()
        // The old rules read it: the cards they know, nothing unreadable.
        let old = try JSONDecoder().decode(OldKeep.self, from: data)
        XCTAssertEqual(old.entries?.map(\.record.key), ["a", "c"])
        XCTAssertLessThanOrEqual(old.format ?? 1, 1)
        // This build reads every card back in its place.
        let back = try SuggestionKeep.decoded(data)
        XCTAssertEqual(back, keep)
        XCTAssertEqual(back.entries.map(\.record.key), ["a", "b", "c"])
        // A file an older build wrote since (without "later") still reads here.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["later"] = nil
        let olderWrote = try SuggestionKeep.decoded(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(olderWrote.entries.map(\.record.key), ["a", "c"])
    }

    // MARK: the log form

    func testNotesAloneNeverQueueALog() {
        XCTAssertEqual(LogSave.step(logChanges: false, notesDiffer: true, photoAdded: false), .notesOnly)
        XCTAssertEqual(LogSave.step(logChanges: false, notesDiffer: true, photoAdded: true), .notesOnly)
        XCTAssertFalse(LogSave.queuesLog(.notesOnly))
        XCTAssertEqual(LogSave.step(logChanges: false, notesDiffer: false, photoAdded: true), .closeOnly)
        XCTAssertEqual(LogSave.step(logChanges: false, notesDiffer: false, photoAdded: false), .nothingChanged)
        XCTAssertEqual(LogSave.step(logChanges: true, notesDiffer: true, photoAdded: false), .logAndNotes)
        XCTAssertEqual([LogSave.Step.logAndNotes, .notesOnly, .closeOnly, .nothingChanged].filter(LogSave.queuesLog), [.logAndNotes])
    }

    // MARK: a repeat's Undo

    func testRepeatUndoLeavesASessionLoggedSince() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        var book = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        let why = RepeatRule.why(title: "Invented easy run", count: 3, batch: "feed1234")
        var keys: [String] = []
        for day in ["2026-09-17", "2026-09-24", "2026-10-01"] {
            keys.append(try book.add(SessionDraft(dayKey: day, sport: "run", title: "Invented easy run", minutes: 40), why: why).key)
        }
        // He logs the second one.
        let logged = try XCTUnwrap(book.sessions.first { $0.key == keys[1] })
        var entry = LogEntry(); entry.actualDuration = "41"
        _ = try book.apply(QueuedEntry(workout: logged, entry: entry))
        XCTAssertTrue(try XCTUnwrap(book.sessions.first { $0.key == keys[1] }).logged)

        let group = book.changes.filter { RepeatRule.batch(of: $0.why) == "feed1234" }
        XCTAssertEqual(group.count, 3)
        let undo = RepeatRule.undoable(group, canUndo: { book.canUndo($0) },
                                       loggedSince: { k in book.sessions.first { $0.key == k }.map { $0.logged || $0.missed } ?? false })
        XCTAssertEqual(Set(undo.map(\.key)), [keys[0], keys[2]])
        for c in undo { try book.undo(c.id) }
        XCTAssertFalse(book.sessions.contains { $0.key == keys[0] || $0.key == keys[2] })
        XCTAssertTrue(book.sessions.contains { $0.key == keys[1] && $0.logged }, "the logged one stays in the plan")
        // A second Undo finds nothing more to take.
        let again = RepeatRule.undoable(book.changes.filter { RepeatRule.batch(of: $0.why) == "feed1234" }, canUndo: { book.canUndo($0) },
                                        loggedSince: { k in book.sessions.first { $0.key == k }?.logged ?? false })
        XCTAssertTrue(again.isEmpty)
    }

    // MARK: odd answers from outside

    func testAHostileRecordingNeverCrashes() {
        // A FIT file whose lap message carries an 8-byte pulse field of all but ones (once a crash).
        var b: [UInt8] = [14, 0x10, 0, 0, 0, 0, 0, 0, 0x2E, 0x46, 0x49, 0x54, 0, 0]
        let def: [UInt8] = [0x40, 0, 0, 19, 0, 1, 15, 8, 0]
        let msg: [UInt8] = [0x00, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        let size = def.count + msg.count
        b[4] = UInt8(size & 0xFF)
        b += def + msg
        let r = GarminFit.parse(Data(b))
        XCTAssertNil(r.laps.first?.avgHr)
        // Truncated and random bytes: an empty recording, no crash, no hang.
        XCTAssertTrue(GarminFit.parse(Data(b.prefix(17))).laps.isEmpty)
        var seed: UInt64 = 42
        for _ in 0..<200 {
            var junk: [UInt8] = [14, 0x10, 0, 0, 0xFF, 0xFF, 0, 0, 0x2E, 0x46, 0x49, 0x54, 0, 0]
            for _ in 0..<300 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; junk.append(UInt8(truncatingIfNeeded: seed >> 33)) }
            _ = GarminFit.parse(Data(junk))
        }
        // A "zip" too big to read is not read at all.
        XCTAssertTrue(GarminFit.recording(fromDownload: Data(count: GarminFit.maxBytes + 1)).laps.isEmpty)
        // Numbers from the service: not-a-number and absurd figures are no number.
        XCTAssertNil(GarminMorning.number("NaN"))
        XCTAssertNil(GarminMorning.number("inf"))
        XCTAssertNil(GarminMorning.number(NSNumber(value: 1e300)))
        XCTAssertEqual(GarminMorning.number("42.5"), 42.5)
    }

    // MARK: the shelf's single keys stay far below their limit

    func testFullFavouritesAndABigChecklistStaySmall() throws {
        let long = String(repeating: "Invented words ", count: 40)
        let full = (0..<Favourites.limit).map { i in
            Favourites.template(from: SessionDraft(dayKey: "2030-01-07", sport: "run", title: long + "\(i)", minutes: 60,
                                                   intensity: long, purpose: long + long))
        }
        let favBytes = try JSONEncoder().encode(full).count
        XCTAssertLessThan(favBytes, ShelfDoc.maxValueBytes / 2, "40 favourites at their longest: \(favBytes) bytes")
        var list = RaceChecklist.starting
        for i in 0..<120 { list.items.append(RaceKitItem(group: .bike, name: "Invented kit item number \(i) with a longer name")) }
        let listBytes = try JSONEncoder().encode(list).count
        XCTAssertLessThan(listBytes, ShelfDoc.maxValueBytes / 2, "a checklist of 141 items: \(listBytes) bytes")
        // Over the limit the shelf refuses (the app then tells him); nothing is half-written.
        var doc = ShelfDoc()
        XCTAssertThrowsError(try doc.set(String(repeating: "x", count: ShelfDoc.maxValueBytes + 1), for: "favourites", device: "invented"))
        XCTAssertFalse(doc.has("favourites"))
    }
}
