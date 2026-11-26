import XCTest
@testable import WorkoutCore

/* 2.15: a planned mobility session is ticked from a Magic Morning stretch note. Invented notes only. */
final class MobilityTickTests: XCTestCase {
    private let today = "2030-01-09"   // a Wednesday

    private func stretch(_ id: String, _ day: String, _ minutes: Int = 12) -> NeighbourDone {
        NeighbourDone(id: id, day: day, kind: "stretch", title: "Morning stretch", minutes: minutes, from: "morning")
    }

    func testAStretchNoteTicksThatDaysMobilityOnceAndNeverAhead() {
        let notes = NeighbourNotes(feel: nil, done: [
            stretch("s-mon", "2030-01-07", 10),
            stretch("s-wed", today, 14),
            stretch("s-wed", today, 14),                   // the same note twice counts once
            NeighbourDone(id: "r-wed", day: today, kind: "routine", minutes: 30, from: "morning"),
            stretch("s-fri", "2030-01-11"),                // a day ahead: never
            stretch("s-tue", "2030-01-08"),                // a day without mobility: nothing
        ])
        let todo = [(key: "fri", day: "2030-01-11"), (key: "wed-2", day: today), (key: "mon", day: "2030-01-07"),
                    (key: "wed", day: today)]
        let ticks = NeighbourRules.mobilityTicks(todo: todo, notes: notes, today: today)
        XCTAssertEqual(ticks.map(\.key), ["mon", "wed-2"], "Monday's and the first of today's; never Friday")
        XCTAssertEqual(ticks.map { $0.note.minutes }, [10, 14])

        // A note already used ticks nothing again; a routine note is not stretching.
        XCTAssertEqual(NeighbourRules.mobilityTicks(todo: todo, notes: notes, used: ["s-mon", "s-wed"], today: today).count, 0)
        XCTAssertTrue(NeighbourRules.mobilityTicks(todo: todo, notes: nil, today: today).isEmpty)

        // A note from a newer format is left alone.
        var newer = notes
        newer.format = NeighbourNotes.knownFormat + 1
        XCTAssertTrue(NeighbourRules.mobilityTicks(todo: todo, notes: newer, today: today).isEmpty)
    }

    func testTheDoneLineNamesTheAppTheNoteCameFrom() {
        XCTAssertEqual(NeighbourRules.doneLine(stretch("x", today, 12)), "Done in Magic Morning · 12 min")
        XCTAssertEqual(NeighbourRules.doneLine(NeighbourDone(id: "y", day: today, kind: "strength", from: "workouts")), "Done in Workouts")
    }
}
