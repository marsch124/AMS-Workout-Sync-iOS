import XCTest
@testable import WorkoutCore

/* A tap on a workout on the Body Battery curve: what it opens and where it can be tapped. Invented data only. */
final class BodyTapTests: XCTestCase {
    private let day = "2026-09-16"
    private func at(_ h: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + h * 3600) }

    private func session(_ key: String, _ sport: String, on d: String? = nil) -> Workout {
        Workout(key: key, sheet: "Weekly Schedules", row: 1, rows: [1],
                date: parseDayKey(d ?? day)!, dayKey: d ?? day, disciplineRaw: sport,
                discipline: Discipline(id: sport, label: sport.capitalized, synonyms: []),
                title: "A session", phase: "", sections: [],
                planned: Planned(durationRaw: 60, distanceRaw: nil, intensity: "", description: ""),
                results: [:], loggedInSheet: false, missed: false, logged: false)
    }

    private func extra(_ id: String, _ activity: String, on d: String? = nil) -> ExtraSummary {
        ExtraSummary(id: id, dayKey: d ?? day, activity: activity, label: activity.capitalized, what: "",
                     minutes: 30, isTraining: false, pending: false)
    }

    private func watch(_ id: String, _ type: String, _ hour: Double, name: String = "", drain: Double? = 9) -> BodyDay.Workout {
        BodyDay.Workout(id: id, name: name, type: type, start: at(hour), end: at(hour + 1), drain: drain)
    }

    func testTheOrderASessionThenAnExtraThenTheLooserMatchThenTheFacts() {
        let plan = [session("run-1", "run"), session("swim-1", "swim"), session("rest", "rest"),
                    session("bike-tomorrow", "bike", on: "2026-09-17")]
        let extras = [extra("walk-1", "walk"), extra("yoga-1", "yoga")]
        let w = [watch("a", "trail_running", 7), watch("b", "walking", 12), watch("c", "yoga", 18),
                 watch("d", "cycling", 19), watch("e", "padel", 20)]
        let t = BodyTap.targets(for: w, day: day, sessions: plan, extras: extras)
        XCTAssertEqual(t[0], .session("run-1"))        // a session of that sport on that day
        XCTAssertEqual(t[1], .extra("walk-1"))         // the walk is the extra, not the run
        XCTAssertEqual(t[2], .extra("yoga-1"))
        XCTAssertEqual(t[3], .facts)                   // tomorrow's ride is not today's
        XCTAssertEqual(t[4], .facts)                   // a sport the app does not know
        // Without the walk extra, the walk may be that day's run; a rest day never matches.
        XCTAssertEqual(BodyTap.targets(for: [w[1]], day: day, sessions: plan, extras: []), [.session("run-1")])
        XCTAssertEqual(BodyTap.targets(for: [w[4]], day: day, sessions: [session("rest", "rest")], extras: []), [.facts])
    }

    func testTwoWorkoutsOfOneSportTakeTheSessionsInTurnAndABrickTakesItsParts() {
        let two = [session("run-am", "run"), session("run-pm", "run")]
        // Given late one first: the order of the answers follows the order given, the turn follows the clock.
        let t = BodyTap.targets(for: [watch("late", "running", 17), watch("early", "running", 7)], day: day, sessions: two, extras: [])
        XCTAssertEqual(t, [.session("run-pm"), .session("run-am")])
        let brick = [session("brick-1", "brick")]
        let parts = BodyTap.targets(for: [watch("a", "road_biking", 9), watch("b", "running", 11), watch("c", "multi_sport", 9),
                                          watch("d", "strength_training", 15)], day: day, sessions: brick, extras: [])
        XCTAssertEqual(parts, [.session("brick-1"), .session("brick-1"), .session("brick-1"), .facts])
    }

    func testEveryWorkoutCanBeTappedAndNeighboursShareTheRoom() {
        // Alone: a short bar still gets a finger's width, pushed inside the card at the edge.
        let alone = BodyTap.spans(bars: [(lo: 2, hi: 8)], from: 0, to: 340)
        XCTAssertEqual(alone[0].lo, 0)
        XCTAssertEqual(alone[0].hi, 44)
        // A long workout is as wide as its bar and a little more.
        let long = BodyTap.spans(bars: [(lo: 100, hi: 200)], from: 0, to: 340)
        XCTAssertEqual(long[0].lo, 96)
        XCTAssertEqual(long[0].hi, 204)
        // Two close together: no overlap, the cut is halfway between the two bars, each keeps its own bar's middle.
        let close = BodyTap.spans(bars: [(lo: 100, hi: 114), (lo: 120, hi: 130)], from: 0, to: 340)
        XCTAssertEqual(close[0].hi, close[1].lo)
        XCTAssertEqual(close[0].hi, 116)
        XCTAssertLessThan(close[0].lo, 107)
        XCTAssertGreaterThan(close[1].hi, 125)
        // Far apart: both keep the full width.
        let apart = BodyTap.spans(bars: [(lo: 50, hi: 60), (lo: 200, hi: 210)], from: 0, to: 340)
        XCTAssertEqual(apart[0].hi - apart[0].lo, 44)
        XCTAssertEqual(apart[1].hi - apart[1].lo, 44)
    }

    func testThePlateSaysTheWorkoutsOwnFacts() {
        let w = BodyDay.Workout(id: "1", name: " Evening padel ", type: "padel", start: at(18), end: at(19.25), drain: 6.4)
        let rows = BodyTap.facts(w) { _ in "18:00" }
        XCTAssertEqual(rows.map(\.name), ["Started", "Lasted", "Body Battery"])
        XCTAssertEqual(rows.map(\.value), ["18:00", "1h\u{00A0}15m", "−6"])
        XCTAssertEqual(BodyTap.title(w), "Evening padel")
        let bare = BodyDay.Workout(id: "2", name: "", type: "running", start: at(7), end: at(7), drain: nil)
        XCTAssertEqual(BodyTap.facts(bare) { _ in "07:00" }.map(\.value), ["07:00", "no cost from Garmin"])
        XCTAssertEqual(BodyTap.title(bare), "Run")
    }
}
