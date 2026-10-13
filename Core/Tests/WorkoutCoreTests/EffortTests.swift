import XCTest
@testable import WorkoutCore

/*
 * The cost of a session and the curves built from it. Nobody can check these
 * by eye — a wrong number here looks exactly like a right one — so they are
 * pinned to arithmetic that can be worked out by hand.
 */
final class EffortTests: XCTestCase {

    func testAnHourAtThresholdIsAHundred() {
        let c = Effort.cost(minutes: 60, avgHR: 150, rpe: 0, lthr: 150, plannedZone: "")
        XCTAssertEqual(c.score, 100, accuracy: 0.01)
        XCTAssertEqual(c.source, .heartRate)
    }

    /* The squaring is the whole point: an easy hour is worth far less than a
       hard one, which hours alone cannot say. */
    func testAnEasyHourCostsFarLessThanAHardOne() {
        let easy = Effort.cost(minutes: 60, avgHR: 105, rpe: 0, lthr: 150, plannedZone: "").score
        let hard = Effort.cost(minutes: 60, avgHR: 150, rpe: 0, lthr: 150, plannedZone: "").score
        XCTAssertEqual(easy, 49, accuracy: 0.5, "0.7 of threshold, squared, is about half")
        XCTAssertLessThan(easy, hard / 1.9)
    }

    func testTwiceTheTimeAtOneIntensityIsTwiceTheCost() {
        let one = Effort.cost(minutes: 60, avgHR: 120, rpe: 0, lthr: 150, plannedZone: "").score
        let two = Effort.cost(minutes: 120, avgHR: 120, rpe: 0, lthr: 150, plannedZone: "").score
        XCTAssertEqual(two, one * 2, accuracy: 0.01)
    }

    /* Heart rate first, then the effort he typed, then the zone the plan asked
       for — and it always says which, because an estimate must own up. */
    func testItFallsBackInOrderAndSaysWhichItUsed() {
        XCTAssertEqual(Effort.cost(minutes: 60, avgHR: 140, rpe: 7, lthr: 150, plannedZone: "Z2").source, .heartRate)
        XCTAssertEqual(Effort.cost(minutes: 60, avgHR: 0, rpe: 7, lthr: 150, plannedZone: "Z2").source, .effort)
        XCTAssertEqual(Effort.cost(minutes: 60, avgHR: 0, rpe: 0, lthr: 150, plannedZone: "Z2").source, .planned)
        XCTAssertEqual(Effort.cost(minutes: 60, avgHR: 0, rpe: 0, lthr: 0, plannedZone: "").source, .none)
    }

    func testNoTimeIsNoCost() {
        XCTAssertEqual(Effort.cost(minutes: 0, avgHR: 150, rpe: 9, lthr: 150, plannedZone: "Z4").score, 0)
    }

    /* A zone range is taken at its middle, so Z1-Z2 sits between the two. */
    func testAZoneRangeIsTakenAtItsMiddle() {
        let one = Effort.cost(minutes: 60, avgHR: 0, rpe: 0, lthr: 0, plannedZone: "Z1").score
        let two = Effort.cost(minutes: 60, avgHR: 0, rpe: 0, lthr: 0, plannedZone: "Z2").score
        let both = Effort.cost(minutes: 60, avgHR: 0, rpe: 0, lthr: 0, plannedZone: "Z1-Z2").score
        XCTAssertGreaterThan(both, one)
        XCTAssertLessThan(both, two)
    }

    /* A heart rate the body does not produce must not be believed. */
    func testAnAbsurdHeartRateIsHeldInside() {
        let silly = Effort.cost(minutes: 60, avgHR: 400, rpe: 0, lthr: 150, plannedZone: "").score
        XCTAssertEqual(silly, 1.15 * 1.15 * 100, accuracy: 0.01, "held at the top of what a human does")
    }

    // MARK: the curves

    func testRestingLowersFatigueFasterThanFitness() {
        var days: [String: Double] = [:]
        for d in 1...28 { days[String(format: "2026-01-%02d", d)] = 100 }   // four weeks of work
        let worked = Effort.form(dailyCost: days, from: "2026-01-01", to: "2026-01-28").last!
        let rested = Effort.form(dailyCost: days, from: "2026-01-01", to: "2026-02-04").last!   // then a week off
        XCTAssertLessThan(rested.fatigue, worked.fatigue / 2, "a week off sheds most of the fatigue")
        XCTAssertGreaterThan(rested.fitness, worked.fitness * 0.8, "and little of the fitness")
        XCTAssertGreaterThan(rested.freshness, worked.freshness)
    }

    func testTheCurvesCoverEveryDayBetweenTheTwoDates() {
        let form = Effort.form(dailyCost: ["2026-01-01": 100], from: "2026-01-01", to: "2026-01-10")
        XCTAssertEqual(form.count, 10, "rest days count: they are where fatigue falls")
        XCTAssertEqual(form.first?.day, "2026-01-01")
        XCTAssertEqual(form.last?.day, "2026-01-10")
        XCTAssertLessThan(form.last!.fatigue, form.first!.fatigue, "nine days of nothing lowers it")
    }

    func testABackwardsRangeIsRefusedRatherThanGuessed() {
        XCTAssertTrue(Effort.form(dailyCost: [:], from: "2026-02-01", to: "2026-01-01").isEmpty)
    }

    func testTheWordForWhereHeStands() {
        XCTAssertEqual(Effort.standing(freshness: -40), "Deep in it")
        XCTAssertEqual(Effort.standing(freshness: -15), "Building")
        XCTAssertEqual(Effort.standing(freshness: 0), "Holding")
        XCTAssertEqual(Effort.standing(freshness: 10), "Fresh")
        XCTAssertEqual(Effort.standing(freshness: 40), "Very fresh")
    }

    // MARK: reading it off a plan

    private func aMapping() throws -> Mapping {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try XCTUnwrap(try Plan.mapping(for: Workbook(data: try Data(contentsOf: url))))
    }

    private func session(_ day: String, sport: String = "run", logged: Bool = true, missed: Bool = false,
                         zone: String = "Z2") -> Workout {
        Workout(key: day + sport, sheet: "Weekly Schedules", row: 1, rows: [1],
                date: parseDayKey(day)!, dayKey: day, disciplineRaw: sport,
                discipline: Discipline(id: sport, label: sport.capitalized, synonyms: []),
                title: "A session", phase: "Base", sections: [],
                planned: Planned(durationRaw: 60, distanceRaw: nil, intensity: zone, description: ""),
                results: [:], loggedInSheet: logged, missed: missed, logged: logged)
    }

    /* Nothing that was not done counts: a session still to do, and a missed
       one, both cost nothing. */
    func testOnlyWhatWasActuallyDoneCosts() throws {
        let plan = [session("2026-01-05"),
                    session("2026-01-06", logged: false),
                    session("2026-01-07", missed: true),
                    session("2026-01-08", sport: "rest")]
        let costs = Effort.dailyCost(plan, extras: [], mapping: try aMapping(), lthr: 150)
        XCTAssertNotNil(costs["2026-01-05"])
        XCTAssertNil(costs["2026-01-06"], "a session still to do has cost nothing yet")
        XCTAssertNil(costs["2026-01-07"], "a missed session cost nothing")
        XCTAssertNil(costs["2026-01-08"], "a rest day is not a session")
    }

    /* Two sessions on one day add up, as a day's work does. */
    func testADayHoldsEverythingDoneOnIt() throws {
        let plan = [session("2026-01-05", sport: "swim"), session("2026-01-05", sport: "run")]
        let costs = Effort.dailyCost(plan, extras: [], mapping: try aMapping(), lthr: 150)
        let one = Effort.dailyCost([plan[0]], extras: [], mapping: try aMapping(), lthr: 150)["2026-01-05"]!
        XCTAssertEqual(costs["2026-01-05"]!, one * 2, accuracy: 0.01)
    }

    /* An extra that counts as training is training; one that does not is not. */
    func testOnlyTheExtrasThatCountAreCounted() throws {
        func extra(_ day: String, training: Bool) -> ExtraSummary {
            ExtraSummary(id: day + String(training), dayKey: day, activity: "walk", label: "Walk", what: "",
                         minutes: 60, isTraining: training, pending: false,
                         distance: "", avgHr: "120", effort: "", notes: "", ref: "")
        }
        let counted = Effort.dailyCost([], extras: [extra("2026-01-05", training: true)],
                                       mapping: try aMapping(), lthr: 150)
        let not = Effort.dailyCost([], extras: [extra("2026-01-06", training: false)],
                                   mapping: try aMapping(), lthr: 150)
        XCTAssertGreaterThan(counted["2026-01-05"] ?? 0, 0)
        XCTAssertTrue(not.isEmpty, "a walk he did not call training is not training")
    }
}
