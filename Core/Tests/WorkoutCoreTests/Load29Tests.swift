import XCTest
@testable import WorkoutCore

final class Load29Tests: XCTestCase {
    func testRatioWordAndScale() {
        let w = [LoadWorkout(day: "2026-09-16", load: 100), LoadWorkout(day: "2026-09-10", load: 100),
                 LoadWorkout(day: "2026-08-25", load: 100), LoadWorkout(day: "2026-08-20", load: 100)]
        let s = BodyLoad.summary(w, today: "2026-09-16")
        XCTAssertEqual(s.acute, 200)
        XCTAssertEqual(s.chronic, 100)
        XCTAssertEqual(s.ratio, 2.0)
        XCTAssertEqual(s.word, "Overreaching")
        XCTAssertEqual(s.weeks.count, 12)
        XCTAssertEqual(s.weeks.last, 200)
        XCTAssertEqual(BodyLoad.word(0.79), "Recovery")
        XCTAssertEqual(BodyLoad.word(1.0), "Maintaining")
        XCTAssertEqual(BodyLoad.word(1.13), "Productive")
        XCTAssertTrue(BodyLoad.isDanger(1.31)); XCTAssertFalse(BodyLoad.isDanger(1.3))
        XCTAssertEqual(BodyLoad.scalePosition(3), 1)
        XCTAssertNil(BodyLoad.summary([], today: "2026-09-16").ratio)
    }

    func testAgeLine() {
        XCTAssertEqual(BodyLoad.ageLine(.init(fitnessAge: 52.2, realAge: 58)), "Real age 58 · 6 years younger")
        XCTAssertEqual(BodyLoad.ageLine(.init(fitnessAge: 59, realAge: 58)), "Real age 58 · 1 year older")
        XCTAssertEqual(BodyLoad.ageLine(.init(fitnessAge: 58.2, realAge: 58)), "Real age 58 · the same")
        XCTAssertNil(BodyLoad.ageLine(.init(fitnessAge: 50, realAge: nil)))
    }

    func testGarminShapes() {
        let acts: [[String: Any]] = [["startTimeLocal": "2026-09-15 07:00:00", "activityTrainingLoad": 40.5, "vO2MaxValue": 52.0],
                                     ["startTimeLocal": "2026-09-14 07:00:00"]]
        let w = BodyLoad.workouts(acts)
        XCTAssertEqual(w.count, 2)
        XCTAssertEqual(BodyLoad.latestVo2(w), 52)
        XCTAssertEqual(BodyLoad.fitnessAge(["fitnessAge": 50.8, "chronologicalAge": 60])?.realAge, 60)
        XCTAssertNil(BodyLoad.fitnessAge(["chronologicalAge": 60]))
    }
}
