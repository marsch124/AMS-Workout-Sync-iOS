import XCTest
@testable import WorkoutCore

/*
 * The writer, on a real workbook, without the web app or a simulator.
 *
 * This is the code that edits his training plan, so what matters is not only
 * that a cell arrives but that everything around it survives: the other
 * sheets, the other rows, and the file's own structure.
 */
final class WritingTests: XCTestCase {

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"),
                                "the test workbook is missing")
        return try Data(contentsOf: url)
    }

    func testACellWrittenComesBackOut() throws {
        let book = try Workbook(data: try fixture())
        let name = try XCTUnwrap(book.sheets.first?.name)
        let before = try book.readSheet(name)
        let row = try XCTUnwrap(before.rows.keys.sorted().first(where: { $0 > 2 }))

        try book.writeCells(name, [CellEdit(ref: "Z\(row)", value: .text("hardening"), field: "test")])
        let after = try Workbook(data: try book.save()).readSheet(name)
        XCTAssertEqual(after.textAt(row, 26), "hardening")
    }

    func testTheRestOfTheWorkbookIsUntouched() throws {
        let original = try Workbook(data: try fixture())
        let names = original.sheets.map(\.name)
        let othersBefore = try names.dropFirst().map { try original.readSheet($0) }

        let book = try Workbook(data: try fixture())
        let first = try XCTUnwrap(names.first)
        let row = try XCTUnwrap(try book.readSheet(first).rows.keys.sorted().first(where: { $0 > 2 }))
        try book.writeCells(first, [CellEdit(ref: "Z\(row)", value: .number(42), field: "test")])
        let saved = try Workbook(data: try book.save())

        XCTAssertEqual(saved.sheets.map(\.name), names, "a sheet was lost or renamed")
        for (i, name) in names.dropFirst().enumerated() {
            // Every cell on both sides, so a cell ADDED to another sheet is
            // caught too — comparing only the cells that existed before let a
            // scribble through when this test was falsified (2026-09-30).
            XCTAssertEqual(Self.everyCell(try saved.readSheet(name)),
                           Self.everyCell(othersBefore[i]),
                           "\(name) was changed by a write to another sheet")
        }
    }

    /* Every cell of a sheet as text, keyed by its place. */
    private static func everyCell(_ sheet: Sheet) -> [String: String] {
        var out: [String: String] = [:]
        for (r, row) in sheet.rows {
            for (c, _) in row {
                let text = sheet.textAt(r, c)
                if !text.isEmpty { out["\(r):\(c)"] = text }
            }
        }
        return out
    }

    func testAnEmptiedCellEmptiesTheCell() throws {
        let book = try Workbook(data: try fixture())
        let name = try XCTUnwrap(book.sheets.first?.name)
        let row = try XCTUnwrap(try book.readSheet(name).rows.keys.sorted().first(where: { $0 > 2 }))

        try book.writeCells(name, [CellEdit(ref: "Y\(row)", value: .text("something"), field: "test")])
        let written = try Workbook(data: try book.save())
        XCTAssertEqual(try written.readSheet(name).textAt(row, 25), "something")

        try written.writeCells(name, [CellEdit(ref: "Y\(row)", value: .text(""), field: "test")])
        let emptied = try Workbook(data: try written.save())
        XCTAssertEqual(try emptied.readSheet(name).textAt(row, 25), "")
    }

    func testAWorkbookSurvivesBeingSavedTwice() throws {
        // The sync saves, uploads, and later starts again from what it saved.
        let book = try Workbook(data: try fixture())
        let once = try book.save()
        let twice = try Workbook(data: once).save()
        let sheetsOnce = try Workbook(data: once).sheets.map(\.name)
        let sheetsTwice = try Workbook(data: twice).sheets.map(\.name)
        XCTAssertEqual(sheetsOnce, sheetsTwice)
        XCTAssertFalse(sheetsTwice.isEmpty)
    }

    func testRubbishIsRefusedRatherThanGuessedAt() {
        XCTAssertThrowsError(try Workbook(data: Data("not a workbook".utf8)))
        XCTAssertThrowsError(try Workbook(data: Data()))
    }
}
