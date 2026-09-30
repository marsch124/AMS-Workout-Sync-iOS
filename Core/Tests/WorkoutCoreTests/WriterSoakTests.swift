import XCTest
@testable import WorkoutCore

/*
 * A batch of awkward values written into one workbook, then read back — the
 * shapes a training plan actually collects: Swedish letters, a long note, a
 * decimal, a zero, a cell emptied, a cell written twice.
 *
 * The parity harness proves the writer agrees with the web app, but it needs
 * the web app served. This needs nothing, so it can run on every push.
 */
final class WriterSoakTests: XCTestCase {

    private func fixture() throws -> Workbook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try Workbook(data: try Data(contentsOf: url))
    }

    func testAwkwardValuesSurviveTheRoundTrip() throws {
        let book = try fixture()
        let name = try XCTUnwrap(book.sheets.first?.name)
        let start = 60   // well past the plan's own rows

        let cases: [(row: Int, value: EditValue, expected: String)] = [
            (start, .text("Rodd chill – lite åksjuk (hungrig?)"), "Rodd chill – lite åksjuk (hungrig?)"),
            (start + 1, .text("Löpband hotell · Norrköping"), "Löpband hotell · Norrköping"),
            (start + 2, .number(45.5), "45.5"),
            (start + 3, .number(0), "0"),
            (start + 4, .number(1.025), "1.025"),
            (start + 5, .text(String(repeating: "a very long note. ", count: 40)),
                        String(repeating: "a very long note. ", count: 40)
                            .trimmingCharacters(in: .whitespaces)),
            (start + 6, .text("<&>\"'"), "<&>\"'"),
            // The cell keeps its spaces — the writer emits xml:space="preserve"
            // — but reading trims the ends, as the web app's reader does. The
            // spacing INSIDE the words is what has to survive.
            (start + 7, .text("  keeps  its  spacing  "), "keeps  its  spacing")
        ]

        try book.writeCells(name, cases.map { CellEdit(ref: "AA\($0.row)", value: $0.value, field: "test") })
        let back = try Workbook(data: try book.save()).readSheet(name)
        for c in cases {
            XCTAssertEqual(back.textAt(c.row, 27), c.expected, "row \(c.row) did not come back as it went in")
        }
    }

    func testACellWrittenTwiceKeepsTheSecondValue() throws {
        let book = try fixture()
        let name = try XCTUnwrap(book.sheets.first?.name)
        try book.writeCells(name, [CellEdit(ref: "AB70", value: .text("first"), field: "test")])
        try book.writeCells(name, [CellEdit(ref: "AB70", value: .text("second"), field: "test")])
        let back = try Workbook(data: try book.save()).readSheet(name)
        XCTAssertEqual(back.textAt(70, 28), "second")
    }

    func testManyWritesInOneGoAllArrive() throws {
        let book = try fixture()
        let name = try XCTUnwrap(book.sheets.first?.name)
        let edits = (80..<140).map { CellEdit(ref: "AC\($0)", value: .number(Double($0)), field: "test") }
        try book.writeCells(name, edits)
        let back = try Workbook(data: try book.save()).readSheet(name)
        for r in 80..<140 {
            XCTAssertEqual(back.textAt(r, 29), String(r), "row \(r) of sixty went missing")
        }
    }

    func testWritingThenEmptyingLeavesNothingBehind() throws {
        let book = try fixture()
        let name = try XCTUnwrap(book.sheets.first?.name)
        try book.writeCells(name, [CellEdit(ref: "AD90", value: .text("temporary"), field: "test")])
        let written = try Workbook(data: try book.save())
        try written.writeCells(name, [CellEdit(ref: "AD90", value: .blank, field: "test")])
        let back = try Workbook(data: try written.save()).readSheet(name)
        XCTAssertEqual(back.textAt(90, 30), "")
    }

    func testTheFileIsStillAWorkbookAfterASeriesOfWrites() throws {
        var data = try XCTUnwrap(try? Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))))
        for round in 1...5 {
            let book = try Workbook(data: data)
            let name = try XCTUnwrap(book.sheets.first?.name)
            try book.writeCells(name, [CellEdit(ref: "AE\(100 + round)", value: .number(Double(round)), field: "test")])
            data = try book.save()
        }
        let final = try Workbook(data: data)
        XCTAssertFalse(final.sheets.isEmpty, "five rounds of writing left something that is not a workbook")
        let sheet = try final.readSheet(try XCTUnwrap(final.sheets.first?.name))
        for round in 1...5 { XCTAssertEqual(sheet.textAt(100 + round, 31), String(round)) }
    }
}
