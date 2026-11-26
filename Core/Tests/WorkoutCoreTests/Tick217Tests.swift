import XCTest
@testable import WorkoutCore

/* 2.17: strength ticked from a Garmin strength activity, and the month's strength count. Invented data only. */
final class Tick217Tests: XCTestCase {
    private let today = "2030-01-10"   // a Thursday

    private func activity(_ id: Int, _ day: String, minutes: Double, type: String = "strength_training", hour: Int = 7) -> GarminActivitySummary {
        let start = ISO8601DateFormatter().date(from: "\(day)T\(String(format: "%02d", hour)):00:00Z")
        return GarminActivitySummary(id: id, name: "Strength", typeKey: type, day: day, startGMT: start, seconds: minutes * 60)
    }

    func testAGarminStrengthActivityTicksThatDaysStrengthOnce() {
        let list = [
            activity(1, "2030-01-08", minutes: 8),                      // too short: never
            activity(2, "2030-01-08", minutes: 42, hour: 18),
            activity(3, today, minutes: 35, type: "running"),           // not strength
            activity(4, today, minutes: 30),
            activity(5, "2030-01-12", minutes: 45),                     // a day ahead: never
        ]
        let todo = [(key: "thu", day: today), (key: "tue", day: "2030-01-08"), (key: "thu-2", day: today), (key: "sat", day: "2030-01-12")]
        let ticks = NeighbourRules.garminStrengthTicks(todo: todo, activities: list, today: today)
        XCTAssertEqual(ticks.map(\.key), ["tue", "thu"], "one per day, never ahead")
        XCTAssertEqual(ticks.map(\.activity.id), [2, 4])
        XCTAssertTrue(NeighbourRules.garminStrengthTicks(todo: todo, activities: list, used: [2, 4], today: today).isEmpty,
                      "an activity already in a log ticks nothing again")
        XCTAssertEqual(NeighbourRules.garminSource(list[3]), "garmin:4")
        XCTAssertEqual(NeighbourRules.tickedLine(from: "garmin:4"), "Ticked from Garmin")
    }

    func testTheUsedActivityTravelsWithTheLogAndTheMonthIsCounted() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        var book = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        let strength = try XCTUnwrap(Disciplines.five.first { $0.id == "strength" })
        let open = book.sessions.filter { $0.discipline.id != "rest" && !$0.loggedInSheet && $0.dayKey.hasPrefix("2026-09") }
        XCTAssertGreaterThanOrEqual(open.count, 2)
        let keys = open.prefix(2).map(\.key)
        for k in keys { if let i = book.sessions.firstIndex(where: { $0.key == k }) { book.sessions[i].discipline = strength } }
        let day = try XCTUnwrap(keys.compactMap { book.session($0)?.dayKey }.max())
        let before = NeighbourRules.strengthMonth(book.sessions, today: day)

        var e = LogEntry()
        e.actualDuration = "40"
        e.tickedFrom = "garmin:917001"
        _ = try book.apply(QueuedEntry(workout: try XCTUnwrap(book.session(keys[0])), entry: e))
        XCTAssertEqual(NeighbourRules.garminIdsUsed(book.sessions), [917_001])
        let again = try JSONDecoder().decode(PlanBook.self, from: try JSONEncoder().encode(book))
        XCTAssertEqual(NeighbourRules.garminIdsUsed(again.sessions), [917_001], "the used activity goes to iCloud with the log")
        XCTAssertNotNil(book.stamps["log:" + keys[0]], "a logged session carries a log mark, so Garmin never ticks it again")

        let after = NeighbourRules.strengthMonth(book.sessions, today: day)
        XCTAssertEqual(after.planned, before.planned)
        XCTAssertEqual(after.done, before.done + 1)
        XCTAssertEqual(NeighbourRules.strengthMonth(book.sessions, today: "2026-08-31").planned,
                       book.sessions.filter { $0.discipline.id == "strength" && $0.dayKey.hasPrefix("2026-08") }.count,
                       "another month counts only its own days")
    }
}
