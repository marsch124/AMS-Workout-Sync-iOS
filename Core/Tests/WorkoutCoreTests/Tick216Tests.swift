import XCTest
@testable import WorkoutCore

/*
 * 2.16: strength ticked from Workout Companion, where a tick came from travelling with the log
 * (never into Excel), and the Mobility count on Progress. Invented notes and the test workbook only.
 */
final class Tick216Tests: XCTestCase {
    private let today = "2030-01-10"   // a Thursday

    private func strength(_ id: String, _ day: String, _ minutes: Int? = 35, effort: Int? = 6) -> NeighbourDone {
        NeighbourDone(id: id, day: day, kind: "strength", title: "Strength A", minutes: minutes, effort: effort, from: "workouts")
    }

    func testAFinishedWorkoutCompanionWorkoutTicksThatDaysStrengthOnce() {
        let notes = NeighbourNotes(feel: nil, done: [
            strength("w-tue", "2030-01-08", 30),
            strength("w-thu", today, 40),
            strength("w-sat", "2030-01-12"),                                   // a day ahead: never
            NeighbourDone(id: "s-thu", day: today, kind: "stretch", minutes: 12, from: "morning"),   // stretching is not strength
        ])
        let todo = [(key: "thu", day: today), (key: "tue", day: "2030-01-08"), (key: "sat", day: "2030-01-12")]
        let ticks = NeighbourRules.strengthTicks(todo: todo, notes: notes, today: today)
        XCTAssertEqual(ticks.map(\.key), ["tue", "thu"])
        XCTAssertEqual(ticks.map { $0.note.minutes }, [30, 40])
        XCTAssertEqual(ticks.first.map { NeighbourRules.tickSource($0.note) }, "workouts")
        XCTAssertTrue(NeighbourRules.strengthTicks(todo: todo, notes: notes, used: ["w-tue", "w-thu"], today: today).isEmpty,
                      "each note ticks once")
        XCTAssertEqual(NeighbourRules.tickedLine(from: "workouts"), "Ticked from Workout Companion")
        XCTAssertEqual(NeighbourRules.tickedLine(from: "morning"), "Ticked from Magic Morning")
        XCTAssertNil(NeighbourRules.tickedLine(from: nil))
    }

    private func book() throws -> (PlanBook, Data) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        let data = try Data(contentsOf: url)
        return (try PlanImport.read(data, fileName: "plan.xlsx", today: "2026-09-16").book, data)
    }

    func testTheTickTravelsWithTheLogStaysOutOfExcelAndIsCountedOnProgress() throws {
        var (book, template) = try book()
        let open = book.sessions.filter { $0.discipline.id != "rest" && !$0.loggedInSheet }
        XCTAssertGreaterThanOrEqual(open.count, 3)
        let keys = Array(open.prefix(3).map(\.key))
        // Three mobility sessions for the count: one ticked, one by hand, one ticked and then missed.
        let mobility = try XCTUnwrap(Disciplines.five.first { $0.id == "mobility" })
        for k in keys { if let i = book.sessions.firstIndex(where: { $0.key == k }) { book.sessions[i].discipline = mobility } }
        func log(_ key: String, _ build: (inout LogEntry) -> Void) throws {
            let w = try XCTUnwrap(book.session(key))
            var e = LogEntry()
            build(&e)
            _ = try book.apply(QueuedEntry(workout: w, entry: e))
        }
        try log(keys[0]) { $0.actualDuration = "12"; $0.tickedFrom = "morning" }
        try log(keys[0]) { $0.rpe = "4" }                                   // How hard was it? keeps the mark
        XCTAssertEqual(book.session(keys[0])?.results[PlanBook.tickedFromField]?.text, "morning")
        try log(keys[1]) { $0.actualDuration = "30" }
        try log(keys[2]) { $0.actualDuration = "10"; $0.tickedFrom = "morning" }
        try log(keys[2]) { $0.missed = true }
        XCTAssertNil(book.session(keys[2])?.results[PlanBook.tickedFromField], "a missed session loses the mark")

        let n = NeighbourRules.mobilitySources(book.sessions)
        XCTAssertEqual(n.fromMorning, 1)
        XCTAssertEqual(n.byHand, 1, "the missed one is not counted")

        // The mark goes to iCloud with the plan and back, and the Excel copy still matches (no column for it).
        let again = try JSONDecoder().decode(PlanBook.self, from: try JSONEncoder().encode(book))
        XCTAssertEqual(again.session(keys[0])?.results[PlanBook.tickedFromField]?.text, "morning")
        XCTAssertNoThrow(try PlanExport.workbook(book, template: template))
    }
}
