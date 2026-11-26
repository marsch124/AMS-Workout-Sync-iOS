import XCTest
@testable import WorkoutCore

/* The notes between the three apps: invented notes only. */
final class NeighbourNotesTests: XCTestCase {
    private let today = "2026-11-25"

    private func json(_ s: String) -> Data { Data(s.utf8) }

    private let sample = """
    {"format":1,"newTop":{"a":[1,2]},
     "feel":{"day":"2026-11-25","value":4,"at":"2026-11-25T06:41:10Z","from":"morning","mood":"calm"},
     "done":[
      {"id":"S1","day":"2026-11-25","kind":"strength","title":"Strength A","minutes":35,"effort":6,"at":"2026-11-25T07:40:02Z","from":"workouts","tag":"x"},
      {"id":"T1","day":"2026-11-24","kind":"stretch","minutes":12,"from":"morning"},
      {"id":"T1","day":"2026-11-24","kind":"stretch","minutes":12,"from":"morning"},
      {"id":"T2","day":"2026-11-21","kind":"stretch"},
      {"id":"T3","day":"2026-11-02","kind":"stretch"}]}
    """

    func testRoundTripKeepsUnknownFields() throws {
        let notes = try XCTUnwrap(NeighbourNotes.decode(json(sample)))
        let again = try XCTUnwrap(NeighbourNotes.decode(notes.encoded()))
        XCTAssertEqual(notes, again)
        XCTAssertEqual(again.extra["newTop"], .object(["a": .array([.number(1), .number(2)])]))
        XCTAssertEqual(again.feel?.extra["mood"], .string("calm"))
        XCTAssertEqual(again.done.first?.extra["tag"], .string("x"))
        let text = String(decoding: try XCTUnwrap(notes.encoded()), as: UTF8.self)
        XCTAssertTrue(text.contains("newTop") && text.contains("mood") && text.contains("tag"))
    }

    func testTodaysFeelFromAnotherAppIsTakenOnceAndNeverOverwritten() throws {
        let notes = NeighbourNotes.decode(json(sample))
        XCTAssertEqual(NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: nil, today: today), .good)
        // Once the diary holds an answer, nothing more is taken.
        XCTAssertNil(NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: .good, today: today))
        XCTAssertNil(NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: .bad, today: today))
        // Another app's answer of today is not written over.
        XCTAssertNil(NeighbourRules.writingFeel(notes: notes, own: .bad, today: today))
        // Another day's feel is not taken.
        XCTAssertNil(NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: nil, today: "2026-11-26"))
    }

    func testTakenOverAnswerFollowsTheNotesButOwnAnswerNeverChanges() throws {
        // The neighbour changed its answer to "good" after it was taken over as "bad": follow.
        let notes = NeighbourNotes.decode(json(sample))
        XCTAssertEqual(NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: .bad, today: today, ownAnswerWasTakenOver: true), .good)
        // Nothing to do when they already agree.
        XCTAssertNil(NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: .good, today: today, ownAnswerWasTakenOver: true))
        // An answer given in this app is never replaced.
        XCTAssertNil(NeighbourRules.takeOverFeel(notes: notes, ownAnswerToday: .bad, today: today, ownAnswerWasTakenOver: false))
        // Notes that carry this app's own answer are not followed.
        let mine = NeighbourNotes(feel: NeighbourFeel(day: today, value: 2, at: nil, from: "training"))
        XCTAssertNil(NeighbourRules.takeOverFeel(notes: mine, ownAnswerToday: .good, today: today, ownAnswerWasTakenOver: true))
    }

    func testAnOldFeelIsReplacedAndOwnAnswerIsWritten() throws {
        let old = NeighbourNotes(feel: NeighbourFeel(day: "2026-11-24", value: 2, at: nil, from: "morning"))
        let written = try XCTUnwrap(NeighbourRules.writingFeel(notes: old, own: .great, today: today))
        XCTAssertEqual(written.feel?.day, today)
        XCTAssertEqual(written.feel?.value, 5)
        XCTAssertEqual(written.feel?.from, "training")
        // No notes yet: a fresh set. Own earlier answer may change; the same one is not rewritten.
        let fresh = try XCTUnwrap(NeighbourRules.writingFeel(notes: nil, own: .ok, today: today))
        XCTAssertEqual(fresh.format, 1)
        let changed = try XCTUnwrap(NeighbourRules.writingFeel(notes: fresh, own: .good, today: today))
        XCTAssertEqual(changed.feel?.value, 4)
        XCTAssertNil(NeighbourRules.writingFeel(notes: changed, own: .good, today: today))
    }

    func testWritingKeepsUnknownFieldsAndPrunesOldNotes() throws {
        let notes = try XCTUnwrap(NeighbourNotes.decode(json(sample.replacingOccurrences(of: "\"feel\":{", with: "\"feelx\":{"))))
        let written = try XCTUnwrap(NeighbourRules.writingFeel(notes: notes, own: .ok, today: today))
        XCTAssertFalse(written.done.contains { $0.id == "T3" }, "a note older than 14 days is dropped")
        XCTAssertTrue(written.done.contains { $0.id == "S1" })
        XCTAssertNotNil(written.extra["newTop"])
    }

    func testADoneNoteIsNeverCountedTwice() throws {
        let notes = NeighbourNotes.decode(json(sample))
        // T1 twice + T2 = two mornings in the last 7 days (T3 is far back).
        XCTAssertEqual(NeighbourRules.stretchMornings(in: notes, lastDays: 7, today: today), 2)
        XCTAssertNil(NeighbourRules.stretchMornings(in: NeighbourNotes(), today: today), "no stretch note: no line")
        XCTAssertEqual(NeighbourRules.strengthNote(for: today, in: notes)?.id, "S1")
        XCTAssertNil(NeighbourRules.strengthNote(for: today, in: notes, used: ["S1"]), "a logged note is not offered again")
        XCTAssertNil(NeighbourRules.strengthNote(for: "2026-11-24", in: notes))
    }

    func testHigherFormatIsRefused() throws {
        let newer = json(#"{"format":2,"feel":{"day":"2026-11-25","value":4}}"#)
        XCTAssertNil(NeighbourNotes.decode(newer), "nothing read")
        var higher = NeighbourNotes(format: 2)
        XCTAssertNil(NeighbourRules.writingFeel(notes: higher, own: .good, today: today), "nothing written")
        higher.done = [NeighbourDone(id: "x", day: today, kind: "strength")]
        XCTAssertNil(NeighbourRules.strengthNote(for: today, in: higher))
        XCTAssertNil(NeighbourRules.takeOverFeel(notes: NeighbourNotes.decode(newer), ownAnswerToday: nil, today: today))
    }

    func testBrokenJSONIsNoNotes() {
        XCTAssertNil(NeighbourNotes.decode(json("{not json")))
        XCTAssertNil(NeighbourNotes.decode(nil))
        // Missing fields are fine; a list holding a stray string loses only the stray.
        let sparse = NeighbourNotes.decode(json(#"{"done":["oops",{"kind":"stretch","day":"2026-11-25"}]}"#))
        XCTAssertEqual(sparse?.done.count, 1)
    }

    func testDoneLine() {
        let note = NeighbourDone(id: "a", day: today, kind: "strength", minutes: 35, at: "2026-11-25T07:40:02Z")
        XCTAssertEqual(NeighbourRules.doneLine(note, timeZone: TimeZone(identifier: "UTC")!), "Done in Workout Companion at 07:40 · 35 min")
        XCTAssertEqual(NeighbourRules.doneLine(NeighbourDone(id: "b", day: today, kind: "strength")), "Done in Workout Companion")
    }

    /* An answer taken over from the notes keeps the note's own time, never later than now. */
    func testATakenOverAnswerKeepsTheNotesOwnTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let early = NeighbourFeel(day: today, value: 4, at: "2027-01-15T07:00:00Z", from: "morning")
        XCTAssertEqual(NeighbourRules.takenOverMoment(early, now: now), ISO8601DateFormatter().date(from: "2027-01-15T07:00:00Z"))
        let ahead = NeighbourFeel(day: today, value: 4, at: "2030-01-01T07:00:00.250Z", from: "morning")
        XCTAssertEqual(NeighbourRules.takenOverMoment(ahead, now: now), now)
        XCTAssertEqual(NeighbourRules.takenOverMoment(NeighbourFeel(day: today, value: 4, at: nil, from: "morning"), now: now), now)
    }
}
