import XCTest
@testable import WorkoutCore

/*
 * What an extra becomes on the sheet. These decide which cells are written,
 * and a fault here writes into the wrong row of his own workbook — the one
 * class of mistake the app must never make.
 */
final class ExtrasWritingTests: XCTestCase {

    private func fixture() throws -> Workbook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try Workbook(data: try Data(contentsOf: url))
    }

    func testAnExtraIsAppendedToTheFirstFreeRow() throws {
        let book = try fixture()
        let name = try Extras.ensureSheet(book)
        let before = try book.readSheet(name)
        let used = before.rows.keys.filter { r in
            (before.rows[r] ?? [:]).keys.contains { !before.textAt(r, $0).isEmpty }
        }
        let firstFree = (used.max() ?? 1) + 1

        var entry = ExtraEntry(date: "2026-10-01", activity: "rowing", ref: "xrow0001")
        entry.minutes = 20
        entry.isTraining = true
        let built = Extras.buildEdits(before, entry, weekdayNames: [:])
        XCTAssertEqual(built.row, firstFree, "an extra must land on the first empty row, never over one in use")
        XCTAssertFalse(built.edits.isEmpty)
        // Every edit it makes belongs to that row and no other.
        for edit in built.edits {
            XCTAssertTrue(edit.ref.hasSuffix(String(built.row)), "an edit strayed off its row: \(edit.ref)")
        }
    }

    func testTheWrittenExtraReadsBackAsItself() throws {
        let book = try fixture()
        let name = try Extras.ensureSheet(book)
        var entry = ExtraEntry(date: "2026-10-01", activity: "rowing", ref: "xrow0002")
        entry.minutes = 20
        entry.what = "Rodd chill"
        entry.isTraining = true
        let built = Extras.buildEdits(try book.readSheet(name), entry, weekdayNames: [:])
        try book.writeCells(name, built.edits)

        let saved = try Workbook(data: try book.save())
        let mine = Extras.read(saved).first { $0.ref == "xrow0002" }
        let row = try XCTUnwrap(mine, "the extra just written cannot be read back")
        XCTAssertEqual(row.date, "2026-10-01")
        XCTAssertEqual(row.minutes, 20)
        XCTAssertEqual(row.what, "Rodd chill")
        XCTAssertTrue(row.isTraining)
        XCTAssertEqual(row.label, "Rowing")
    }

    func testWritingTheSameExtraTwiceDoesNotDoubleIt() throws {
        let book = try fixture()
        let name = try Extras.ensureSheet(book)
        var entry = ExtraEntry(date: "2026-10-02", activity: "walk", ref: "xrow0003")
        entry.minutes = 30

        let first = Extras.buildEdits(try book.readSheet(name), entry, weekdayNames: [:])
        try book.writeCells(name, first.edits)
        let once = try Workbook(data: try book.save())

        // The replay guard is what stops a resend appending it again.
        XCTAssertTrue(Extras.alreadyRecorded(try once.readSheet(name), entry))
        XCTAssertEqual(Extras.read(once).filter { $0.ref == "xrow0003" }.count, 1)
    }

    func testACorrectionWritesOnlyTheBoxesNamed() throws {
        let book = try fixture()
        let name = try Extras.ensureSheet(book)
        var entry = ExtraEntry(date: "2026-10-03", activity: "walk", ref: "xrow0004")
        entry.minutes = 30
        entry.what = "Dog walk"
        let built = Extras.buildEdits(try book.readSheet(name), entry, weekdayNames: [:])
        try book.writeCells(name, built.edits)
        let saved = try Workbook(data: try book.save())

        var corrected = entry
        corrected.minutes = 65
        corrected.editing = ExtraTarget(id: "x", ref: "xrow0004", date: "2026-10-03",
                                        label: "Walk", minutes: 30, fields: [ExtraField.duration])
        let sheet = try saved.readSheet(name)
        let row = try XCTUnwrap(Extras.findRow(sheet, try XCTUnwrap(corrected.editing)))
        let edits = Extras.buildEdits(sheet, corrected, row: row, weekdayNames: [:])
        XCTAssertEqual(edits.count, 1, "only the duration was named, so only one cell may be written")
        try saved.writeCells(name, edits)

        let after = try Workbook(data: try saved.save())
        let mine = try XCTUnwrap(Extras.read(after).first { $0.ref == "xrow0004" })
        XCTAssertEqual(mine.minutes, 65, "the corrected length")
        XCTAssertEqual(mine.what, "Dog walk", "everything not named must be exactly as it was")
    }
}
