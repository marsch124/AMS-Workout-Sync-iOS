import XCTest
@testable import WorkoutCore

final class PlanOverviewCountTests: XCTestCase {
    /* 2.4.1: the season bars mark an easy week with E and a test week with T; pale is left to "still to do". */
    func testTheLetterAboveAWeeksBarAndTheLineUnderTheBars() {
        XCTAssertEqual(PlanOverview.weekLetter(isEasy: true, isTest: false), "E")
        XCTAssertEqual(PlanOverview.weekLetter(isEasy: false, isTest: true), "T")
        XCTAssertEqual(PlanOverview.weekLetter(isEasy: true, isTest: true), "T")
        XCTAssertNil(PlanOverview.weekLetter(isEasy: false, isTest: false))
        XCTAssertEqual(PlanOverview.seasonKey(hasEasy: true, hasTest: true, lettersShown: true),
                       "E = easy week \u{00B7} T = test week \u{00B7} Tap a bar to see its week")
        XCTAssertEqual(PlanOverview.seasonKey(hasEasy: true, hasTest: false, lettersShown: true),
                       "E = easy week \u{00B7} Tap a bar to see its week")
        // Wide bars carry the whole words, so the line explains no letters.
        XCTAssertEqual(PlanOverview.seasonKey(hasEasy: true, hasTest: true, lettersShown: false), "Tap a bar to see its week")
        XCTAssertFalse(PlanOverview.seasonKey(hasEasy: true, hasTest: true, lettersShown: true).lowercased().contains("pale"))
    }

    func testAllCountLeavesRestDaysOut() {
        XCTAssertEqual(PlanOverview.countedInAll(disciplineIds: ["run", "rest", "swim", "rest"], extras: 2), 4)
    }

    func testTrainingCountLeavesRestDaysOut() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        var book = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        let rest = try XCTUnwrap(book.sessions.first { $0.discipline.id == "rest" })
        let run = try XCTUnwrap(book.sessions.first { $0.discipline.id != "rest" })
        book.sessions = [run, rest, run, rest, rest]
        XCTAssertEqual(book.trainingCount, 2)
    }
}
