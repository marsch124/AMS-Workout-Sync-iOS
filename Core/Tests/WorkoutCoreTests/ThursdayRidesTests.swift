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

    /* A ride he moved, renamed or took out still counts for its week: the rule never offers that week again. */
    func testAMovedRenamedOrRemovedRideIsNotOfferedAgain() throws {
        var b = try book()
        let w = weeks()
        let first = ThursdayRides.drafts(weeks: w, sessions: b.sessions, changes: b.changes, from: "2030-01-01")
        XCTAssertEqual(first.count, 11)
        var keys: [String] = []
        for d in first { keys.append(try b.add(d, why: ThursdayRides.why).key) }
        XCTAssertEqual(ThursdayRides.drafts(weeks: w, sessions: b.sessions, changes: b.changes, from: "2030-01-01").count, 0)

        // Moved to the Friday of its week.
        var moved = try XCTUnwrap(b.draft(of: keys[0]))
        moved.dayKey = PlanView.addDays(moved.dayKey, 1)
        _ = try b.change(keys[0], to: moved)
        // Renamed and given another purpose.
        var renamed = try XCTUnwrap(b.draft(of: keys[1]))
        renamed.title = "Coffee ride"
        renamed.purpose = "Sunshine"
        _ = try b.change(keys[1], to: renamed)
        // Taken out of the plan.
        _ = try b.remove(keys[2])
        XCTAssertEqual(ThursdayRides.drafts(weeks: w, sessions: b.sessions, changes: b.changes, from: "2030-01-01").count, 0,
                       "a week that has, or had, its ride is never offered a second one")

        // Only an Undo of the adding itself frees the week again.
        let adding = try XCTUnwrap(b.changes.first { $0.kind == "add" && $0.key == keys[3] })
        try b.undo(adding.id)
        let again = ThursdayRides.drafts(weeks: w, sessions: b.sessions, changes: b.changes, from: "2030-01-01")
        XCTAssertEqual(again.map(\.dayKey), [first[3].dayKey])
    }

    /* A week whose heading does not start on a Monday still gets its ride on the Thursday. */
    func testAWeekHeadingThatIsNotAMondayStillGivesAThursday() throws {
        let b = try book()
        let odd = [PlanWeek(number: 1, monday: "2030-01-06", phase: "Base 2 \u{2014} Aerobic Development", tag: "")]   // a Sunday
        let d = ThursdayRides.drafts(weeks: odd, sessions: b.sessions, from: "2029-12-01")
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(PlanView.addDays(PlanView.weekStart(d[0].dayKey), 3), d[0].dayKey)
    }

    /* "Base 3 · Recovery" is still Base 3: the steps go on after it. */
    func testBaseThreeStepsGoOnAfterItsEasyWeek() throws {
        let b = try book()
        var w: [PlanWeek] = []
        let phases = ["Base 3 \u{2014} Aerobic Endurance", "Base 3 \u{2014} Recovery", "Base 3 \u{2014} Aerobic Endurance"]
        let tags = ["", "RECOVERY WEEK", ""]
        for i in 0..<3 { w.append(PlanWeek(number: i + 1, monday: PlanView.addDays("2030-01-07", 7 * i), phase: phases[i], tag: tags[i])) }
        XCTAssertEqual(minutes(ThursdayRides.drafts(weeks: w, sessions: b.sessions, from: "2030-01-01")), [50, 30, 55])
    }

    /* Two devices add the season's rides before iCloud has carried either set across: one ride per Thursday after the merge. */
    func testTwoDevicesAddingTheRidesMakeOneRidePerThursday() throws {
        let start = try book()
        let w = weeks()
        let drafts = ThursdayRides.drafts(weeks: w, sessions: start.sessions, changes: start.changes, from: "2030-01-01")
        XCTAssertFalse(drafts.isEmpty)
        var phone = start, pad = start
        for d in drafts { try phone.add(d, why: ThursdayRides.why, fixedKey: ThursdayRides.key(for: d)) }
        for d in drafts { try pad.add(d, why: ThursdayRides.why, fixedKey: ThursdayRides.key(for: d)) }
        // Adding again on one device adds nothing.
        let count = phone.sessions.count
        for d in drafts { try phone.add(d, why: ThursdayRides.why, fixedKey: ThursdayRides.key(for: d)) }
        XCTAssertEqual(phone.sessions.count, count)
        let joined = try BookMerge.merged(phone, pad)
        for d in drafts {
            XCTAssertEqual(joined.sessions.filter { $0.dayKey == d.dayKey && ThursdayRides.holdsARide($0) }.count, 1, d.dayKey)
        }
    }
}
