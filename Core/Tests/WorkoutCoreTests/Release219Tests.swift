import XCTest
@testable import WorkoutCore

/*
 * 2.19: a Workout Companion session on a day without planned strength becomes an Extra workout,
 * and his own sleep need replaces Garmin's estimate. Invented notes and nights only.
 */
final class Release219Tests: XCTestCase {
    private let today = "2030-01-11"   // a Friday

    private func strength(_ id: String, _ day: String, _ minutes: Int? = 65, effort: Int? = 6) -> NeighbourDone {
        NeighbourDone(id: id, day: day, kind: "strength", title: "Sets & reps", minutes: minutes, effort: effort, from: "workouts")
    }

    func testAGymSessionOnADayWithoutPlannedStrengthBecomesOneExtra() {
        let notes = NeighbourNotes(feel: nil, done: [
            strength("w-fri", today),                       // rest day: becomes an extra
            strength("w-fri-2", today, 20),                 // a second one the same day: not twice
            strength("w-thu", "2030-01-10"),                // Thursday has planned strength: left to the tick
            strength("w-wed", "2030-01-09"),                // Wednesday already has a Strength extra
            strength("w-sat", "2030-01-12"),                // ahead: never
            strength("w-old", "2029-12-20"),                // older than 14 days: never
            NeighbourDone(id: "s-fri", day: today, kind: "stretch", minutes: 12, from: "morning"),
        ])
        let found = NeighbourRules.companionExtras(notes: notes, plannedStrengthDays: ["2030-01-10"],
                                                   strengthExtraDays: ["2030-01-09"], used: [], today: today)
        XCTAssertEqual(found.map(\.id), ["w-fri"])
        let extra = NeighbourRules.companionExtra(found[0])
        XCTAssertEqual(extra.date, today)
        XCTAssertEqual(extra.activity, "strength")
        XCTAssertEqual(extra.minutes, 65)
        XCTAssertEqual(extra.effort, 6)
        XCTAssertTrue(extra.isTraining)
        XCTAssertEqual(extra.notes, "From Workout Companion")
        XCTAssertTrue(NeighbourRules.companionExtras(notes: notes, plannedStrengthDays: ["2030-01-10"], strengthExtraDays: ["2030-01-09"],
                                                     used: ["w-fri", "w-fri-2"], today: today).isEmpty, "each session once, also after a delete")
    }

    func testHisOwnSleepNeedReplacesGarminsEstimate() {
        let nights = [BodyHealth.Night(day: "2030-01-10", sleptMinutes: 400, needMinutes: 480),
                      BodyHealth.Night(day: "2030-01-11", sleptMinutes: 340, needMinutes: 465)]
        XCTAssertEqual(BodyHealth.balance(nights), -205)
        let own = BodyHealth.withNeed(nights, minutes: 360)
        XCTAssertEqual(own.map(\.needMinutes), [360, 360])
        XCTAssertEqual(BodyHealth.balance(own), 20)
        XCTAssertEqual(BodyHealth.sleepLine(own, ownNeed: 360), "Need 6h a night (your setting)")
        XCTAssertEqual(BodyHealth.withNeed(nights, minutes: nil), nights, "nil = Garmin's estimate")
        XCTAssertEqual(BodyHealth.withNeed(nights, minutes: 0), nights, "0 = Garmin's estimate")
        XCTAssertEqual(BodyHealth.needText(390), "6h\u{00A0}30m")
    }
}
