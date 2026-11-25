import XCTest
@testable import WorkoutCore

/* The Thursday easy rides, on a little invented plan: seconds, no workbook of his. */
final class ThursdayRidesTests: XCTestCase {

    private func weeks() -> [PlanWeek] {
        var out: [PlanWeek] = []
        func add(_ phase: String, _ tags: [String]) {
            for tag in tags {
                let n = out.count + 1
                out.append(PlanWeek(number: n, monday: PlanView.addDays("2030-01-07", 7 * (n - 1)), phase: phase, tag: tag))
            }
        }
        add("Base 2 \u{2014} Aerobic Development", ["", "RECOVERY WEEK"])
        add("Base 3 \u{2014} Aerobic Endurance", ["TEST WEEK", "", "", "", "", ""])
        add("Build 1 \u{2014} Race-Specific Strength", ["RACE SIMULATION 1", ""])
        add("Peak \u{2014} Maximum Specific Load", [""])
        add("Taper \u{2014} Freshen Up", [""])
        add("Taper \u{2014} Freshen Up", ["RACE WEEK \u{2014} THE RACE"])
        add("Recovery & Transition \u{2014} Postseason", ["RECOVERY WEEK"])
        return out
    }

    private func book() throws -> PlanBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
    }

    private func minutes(_ d: [SessionDraft]) -> [Double?] { d.map(\.minutes) }

    func testMinutesFollowTheKindOfWeek() throws {
        let b = try book()
        let d = ThursdayRides.drafts(weeks: weeks(), sessions: b.sessions, from: "2030-01-01")
        // Base 2 ordinary, Base 2 easy, Base 3 test, five ordinary Base 3, Build practice (none), Build, Peak, Taper, race week (none), after (none)
        XCTAssertEqual(minutes(d), [45, 30, 30, 50, 55, 55, 60, 60, 60, 45, 30])
        XCTAssertEqual(d[0].intensity, "Z1\u{2013}Z2")
        XCTAssertEqual(d[1].intensity, "Z1")
        XCTAssertEqual(d[3].intensity, "Z2")
        XCTAssertTrue(d.allSatisfy { $0.sport == "bike" && !$0.isKey && $0.purpose == ThursdayRides.purpose })
    }

    func testEveryRideIsOnAThursday() throws {
        let b = try book()
        for d in ThursdayRides.drafts(weeks: weeks(), sessions: b.sessions, from: "2030-01-01") {
            let monday = PlanView.weekStart(d.dayKey)
            XCTAssertEqual(PlanView.addDays(monday, 3), d.dayKey)
        }
    }

    func testNoRideInRacePracticeOrRaceWeeks() throws {
        let b = try book()
        let w = weeks()
        let none = w.filter { $0.tag.contains("RACE") }.map { PlanView.addDays($0.monday, 3) }
        XCTAssertEqual(none.count, 2)
        let days = Set(ThursdayRides.drafts(weeks: w, sessions: b.sessions, from: "2030-01-01").map(\.dayKey))
        for day in none { XCTAssertFalse(days.contains(day)) }
        XCTAssertFalse(days.contains(PlanView.addDays(w.last!.monday, 3)), "nothing after the race")
    }

    func testOnlyFromTheStartDay() throws {
        let b = try book()
        let w = weeks()
        let all = ThursdayRides.drafts(weeks: w, sessions: b.sessions, from: "2030-01-01")
        let later = ThursdayRides.drafts(weeks: w, sessions: b.sessions, from: all[2].dayKey)
        XCTAssertEqual(later.count, all.count - 2)
        XCTAssertEqual(later.first?.dayKey, all[2].dayKey)
    }

    func testNothingIsAddedTwice() throws {
        var b = try book()
        let w = weeks()
        let first = ThursdayRides.drafts(weeks: w, sessions: b.sessions, from: "2030-01-01")
        XCTAssertFalse(first.isEmpty)
        for d in first { try b.add(d, why: "Thursday easy rides") }
        XCTAssertEqual(ThursdayRides.drafts(weeks: w, sessions: b.sessions, from: "2030-01-01"), [])
    }

    func testWeeksBeforeAndAfter() throws {
        let b = try book()
        let w = weeks()
        let d = ThursdayRides.drafts(weeks: w, sessions: b.sessions, from: "2030-01-01")
        let rows = ThursdayRides.weekMinutes(weeks: w, sessions: b.sessions, mapping: b.mapping, drafts: d)
        XCTAssertEqual(rows.count, d.count)
        XCTAssertEqual(rows.map { $0.after - $0.before }, d.map { $0.minutes ?? 0 })
    }
}
