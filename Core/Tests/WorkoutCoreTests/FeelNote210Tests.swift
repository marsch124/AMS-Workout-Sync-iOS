import XCTest
@testable import WorkoutCore

/* 2.10: a few words travel with the morning answer. All figures and texts here are invented. */
final class FeelNote210Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testASetNoteIsKeptTrimmedAndMarked() {
        var doc = DiaryDoc()
        doc.setFeel(4, on: "2026-09-16", now: t0)
        doc.setNote("  sore legs \n", on: "2026-09-16", now: t0)
        XCTAssertEqual(doc.notes["2026-09-16"], "sore legs")
        XCTAssertNotNil(doc.stamps["note:2026-09-16"])
        let back = try! DiaryDoc.decoded(try! doc.encoded())
        XCTAssertEqual(back.notes, doc.notes)
    }

    func testTheNewerNoteWinsWhateverTheOrder() {
        var a = DiaryDoc(), b = DiaryDoc()
        a.setNote("slept badly", on: "2026-09-16", now: t0)
        b.setNote("sore legs", on: "2026-09-16", now: t0.addingTimeInterval(60))
        XCTAssertEqual(DiaryDoc.merged(a, b).notes["2026-09-16"], "sore legs")
        XCTAssertEqual(DiaryDoc.merged(b, a).notes["2026-09-16"], "sore legs")
        // The same mark, two texts: the larger, the same either way round.
        var c = DiaryDoc(), d = DiaryDoc()
        c.stamps["note:x"] = t0; c.notes["x"] = "aaa"
        d.stamps["note:x"] = t0; d.notes["x"] = "bbb"
        XCTAssertEqual(DiaryDoc.merged(c, d).notes["x"], "bbb")
        XCTAssertEqual(DiaryDoc.merged(d, c).notes["x"], "bbb")
    }

    func testADocWithoutTheFieldStillReads() throws {
        let json = #"{"format":1,"feel":{"2026-09-16":4},"answers":{},"stamps":{}}"#
        let doc = try DiaryDoc.decoded(Data(json.utf8))
        XCTAssertEqual(doc.notes, [:])
        XCTAssertEqual(doc.feel["2026-09-16"], 4)
    }
}
