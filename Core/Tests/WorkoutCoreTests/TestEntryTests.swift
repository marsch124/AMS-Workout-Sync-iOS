import XCTest
@testable import WorkoutCore

final class TestEntryTests: XCTestCase {
    private func fields(lthr: String = "160", ftp: String = "200", swim: String = "1:50", weight: String = "70") -> TestEntryFields {
        TestEntryFields(lthr: lthr, ftp: ftp, swim: swim, weight: weight, notes: " felt fine ",
                        firstDay: "2026-11-02", lastDay: "2026-11-04")
    }

    func testSwimPaceIsMinutesAndSeconds() {
        XCTAssertEqual(TestEntry.parseSwim("1:50"), 110)
        XCTAssertEqual(TestEntry.parseSwim(" 2:05 "), 125)
        XCTAssertNil(TestEntry.parseSwim("1:75"))
        XCTAssertNil(TestEntry.parseSwim("110"))
        XCTAssertNil(TestEntry.parseSwim("a:b"))
        XCTAssertEqual(TestEntry.swimText(125), "2:05")
    }

    func testAGoodEntryBecomesATestAndLimitsAreRefused() throws {
        let t = try TestEntry.make(fields(), existing: []).get()
        XCTAssertEqual([t.name, t.dates, t.notes], ["Test 1", "02 Nov–04 Nov 2026", "felt fine"])
        XCTAssertEqual([t.lthr, t.ftp, t.css, t.weight].compactMap { $0 }, [160, 200, 110, 70])
        for bad in [fields(lthr: "79"), fields(lthr: "221"), fields(ftp: "49"), fields(ftp: "501"), fields(swim: "0:59"),
                    fields(swim: "4:01"), fields(weight: "34"), fields(weight: "151"), fields(lthr: "nan"), fields(ftp: "inf"),
                    fields(lthr: "", ftp: "", swim: "", weight: "")] {
            XCTAssertNil(try? TestEntry.make(bad, existing: []).get())
        }
        var late = fields(); late.lastDay = "2026-11-01"
        XCTAssertNil(try? TestEntry.make(late, existing: []).get())
    }

    func testAWaitingBlockIsFilledAndTheLastTestFillsTheBoxes() throws {
        let existing = [TestResult(name: "Test 1", lthr: 150, ftp: 190, css: 115, weight: 71),
                        TestResult(name: "Test 2", week: "W9", dates: "plan")]
        let t = try TestEntry.make(fields(), existing: existing).get()
        XCTAssertEqual([t.name, t.week], ["Test 2", "W9"])
        let same = TestEntry.sameAs(try XCTUnwrap(TestEntry.last(of: existing)))
        XCTAssertEqual([same.lthr, same.ftp, same.swim, same.weight], ["150", "190", "1:55", "71"])
    }
}
