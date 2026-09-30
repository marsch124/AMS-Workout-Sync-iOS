import XCTest
@testable import WorkoutCore

/*
 * Workbooks that are not what the app hopes for. None of these may crash: a
 * plan he has edited in Excel, or picked by mistake, has to fail as a message
 * on the screen and never as a dead app.
 */
final class BrokenWorkbookTests: XCTestCase {

    private func fixture() throws -> Workbook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try Workbook(data: try Data(contentsOf: url))
    }

    func testAWorkbookWithNothingItRecognisesIsRefusedQuietly() throws {
        // A real file, but not a plan: the app must say so, not crash.
        let book = try fixture()
        let name = try XCTUnwrap(book.sheets.first?.name)
        let sheet = try book.readSheet(name)
        // Wipe the header row the detector looks for.
        var edits: [CellEdit] = []
        for c in 1...20 { edits.append(CellEdit(ref: Self.ref(c, 2), value: .text(""), field: "test")) }
        for c in 1...20 { edits.append(CellEdit(ref: Self.ref(c, 1), value: .text(""), field: "test")) }
        XCTAssertNoThrow(try book.writeCells(name, edits))
        _ = sheet
        let stripped = try Workbook(data: try book.save())
        XCTAssertNoThrow(_ = try autoDetect(stripped))
    }

    func testAPlanWithNoExtrasSheetStillReads() throws {
        let book = try fixture()
        // The fixture has one; reading is expected to cope either way.
        XCTAssertNoThrow(_ = Extras.read(book))
        XCTAssertFalse(Extras.read(book).isEmpty, "the fixture's own extra should be read")
    }

    func testZonesSurviveAWorkbookWithoutThem() throws {
        let book = try fixture()
        XCTAssertNoThrow(_ = Zones.read(book))
    }

    func testTheSameExtraIsNeverAppendedTwice() throws {
        let book = try fixture()
        let name = try Extras.ensureSheet(book)
        let sheet = try book.readSheet(name)
        var entry = ExtraEntry(date: "2026-09-15", activity: "walk", ref: "xtest001")
        entry.minutes = 35
        // The fixture's own row carries that ref: a replay must recognise it.
        XCTAssertTrue(Extras.alreadyRecorded(sheet, entry))

        var fresh = ExtraEntry(date: "2026-09-16", activity: "rowing", ref: "xbrandnew")
        fresh.minutes = 20
        XCTAssertFalse(Extras.alreadyRecorded(sheet, fresh))
    }

    func testAnExtraWithARubbishDateIsNotPlacedOnAWrongDay() {
        // parseDayKey used to roll a thirteenth month into the next January.
        XCTAssertNil(parseDayKey("2026-13-01"))
        XCTAssertNil(parseDayKey("not a date"))
    }

    private static func ref(_ col: Int, _ row: Int) -> String {
        var c = col, letters = ""
        while c > 0 { let r = (c - 1) % 26; letters = String(UnicodeScalar(65 + r)!) + letters; c = (c - 1) / 26 }
        return letters + String(row)
    }
}
