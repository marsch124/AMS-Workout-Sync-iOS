import XCTest
@testable import WorkoutCore

/*
 * Round 30, data-safety review: one test per rule the review added. Every
 * number, name and day here is invented.
 */
final class Safety30Tests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    private func fixture() throws -> PlanBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        var b = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        b.changes = []
        return b
    }

    /* An invented season: weeks from Mon 7 Jan 2030, a bike test on 3 Feb, the race on Sun 10 Feb, two sessions after it. */
    private func switchBook() throws -> PlanBook {
        var b = try fixture()
        b.weeks = (0..<7).map { i in
            PlanWeek(number: i + 1, monday: PlanView.addDays("2030-01-07", 7 * i), phase: i < 5 ? "Build" : "Post-season", tag: i == 5 ? "RACE WEEK" : "")
        }
        func add(_ day: String, _ sport: String, _ title: String, _ m: Double, _ zone: String = "Z2") throws {
            try b.add(SessionDraft(dayKey: day, sport: sport, title: title, minutes: m, intensity: zone))
        }
        try add("2030-02-03", "bike", "Test \u{2014} bike: 20 min", 60, "Test")
        try add("2030-02-10", "race", "Race \u{2014} invented", 330, "Race day")
        try add("2030-02-12", "run", "Easy run, no watch", 30)
        try add("2030-02-20", "swim", "Easy swim", 30)
        b.changes = []
        return b
    }

    private var draft: [MadeWeek] {
        PlanMaker.make(PlanMakerSettings(raceName: "Invented Half", raceDay: "2030-07-28", distance: .half, start: "2030-02-04"), shape: .standard)
    }

    private func days(_ b: PlanBook, from: String) -> [String] { b.sessions.filter { $0.dayKey >= from }.map(\.dayKey).sorted() }

    // MARK: switching to a draft

    func testASwitchMadeOnTwoDevicesBeforeTheyMeetIsOneNewPlanAndOneUndoTakesItBack() throws {
        let base = try switchBook(), draft = draft, from = "2030-02-11"
        var a = base, b = base
        _ = try DraftSwitch.apply(draft: draft, from: from, raceName: "Invented Half", to: &a, today: "2030-01-01", now: t0)
        a = a.stamped(after: base, now: t0)
        _ = try DraftSwitch.apply(draft: draft, from: from, raceName: "Invented Half", to: &b, today: "2030-01-01", now: t0.addingTimeInterval(90))
        b = b.stamped(after: base, now: t0.addingTimeInterval(90))

        let batch = DraftSwitch.batch(for: draft, from: from)
        XCTAssertEqual(DraftSwitch.batch(of: try XCTUnwrap(DraftSwitch.latest(in: a)).why), batch, "the same mark on both devices")
        var met = try BookMerge.merged(a, b)
        let adding = draft.flatMap(\.sessions).filter { $0.day >= from }.count
        XCTAssertEqual(met.sessions.filter { $0.key.hasPrefix(DraftSwitch.keyPrefix(batch)) }.count, adding, "one new plan, not two")
        XCTAssertFalse(met.sessions.contains { $0.dayKey >= from && !$0.key.hasPrefix(DraftSwitch.keyPrefix(batch)) })

        // Tapped again where it already stands: refused, nothing changes.
        var again = met
        XCTAssertThrowsError(try DraftSwitch.apply(draft: draft, from: from, raceName: "Invented Half", to: &again, today: "2030-01-01"))
        XCTAssertEqual(again, met)
        // Even where the new plan's own tests would not hold the day back, the same switch is never written twice.
        var bare = met
        bare.sessions.removeAll { $0.key.hasPrefix(DraftSwitch.keyPrefix(batch)) && LayOut.isProtected($0) }
        XCTAssertThrowsError(try DraftSwitch.apply(draft: draft, from: from, raceName: "Invented Half", to: &bare, today: "2030-01-01")) {
            XCTAssertEqual($0 as? DraftSwitchError, .alreadyIn)
        }

        // One Undo on the joined plan: his own sessions back, the new ones gone, both devices' lines read "undone".
        try DraftSwitch.undo(batch: batch, record: nil, in: &met)
        XCTAssertNil(DraftSwitch.latest(in: met))
        XCTAssertTrue(met.changes.filter { $0.kind == DraftSwitch.summaryKind }.allSatisfy(\.undone))
        XCTAssertFalse(met.sessions.contains { $0.key.hasPrefix("App!np") })
        XCTAssertEqual(days(met, from: from), days(base, from: from))
    }

    func testOnlyTheNewestSwitchStillStandingCanBeUndone() throws {
        let base = try switchBook(), draft = draft
        var b = base
        let x = DraftSwitch.batch(for: draft, from: "2030-02-11")
        XCTAssertNotEqual(x, DraftSwitch.batch(for: draft, from: "2030-02-18"), "another Monday, another switch")
        _ = try DraftSwitch.apply(draft: draft, from: "2030-02-11", raceName: "Invented Half", to: &b, today: "2030-01-01", now: t0)
        // A second draft for a later race, switched over the first one's weeks after its race.
        let next = PlanMaker.make(PlanMakerSettings(raceName: "Invented Olympic", raceDay: "2031-03-30", distance: .olympic, start: "2030-08-05"),
                                  shape: .standard)
        let from = try XCTUnwrap(DraftSwitch.days(draft: next, sessions: b.sessions, today: "2030-01-01").first)
        XCTAssertTrue(b.sessions.contains { $0.key.hasPrefix(DraftSwitch.keyPrefix(x)) && $0.dayKey >= from }, "the first plan's weeks after its race")
        let y = DraftSwitch.batch(for: next, from: from)
        _ = try DraftSwitch.apply(draft: next, from: from, raceName: "Invented Olympic", to: &b, today: "2030-01-01", now: t0.addingTimeInterval(60))

        // The older switch first would bring his old sessions back under the newer plan: refused, nothing changes.
        var tried = b
        XCTAssertThrowsError(try DraftSwitch.undo(batch: x, record: nil, in: &tried)) {
            XCTAssertEqual($0 as? DraftSwitchError, .newerSwitch)
        }
        XCTAssertEqual(tried, b)

        try DraftSwitch.undo(batch: y, record: nil, in: &b)
        XCTAssertEqual(DraftSwitch.batch(of: try XCTUnwrap(DraftSwitch.latest(in: b)).why), x)
        try DraftSwitch.undo(batch: x, record: nil, in: &b)
        XCTAssertFalse(b.sessions.contains { $0.key.hasPrefix("App!np") })
        XCTAssertEqual(days(b, from: "2030-02-11"), days(base, from: "2030-02-11"), "no session twice")
    }

    // MARK: next week, tuned

    func testATunedWeekAlreadyInThePlanIsNeverOfferedAgain() {
        func line(_ why: String, day: String, undone: Bool = false) -> PlanChange {
            var c = PlanChange(at: t0, kind: "edit", key: "App!1abc", title: "Steady run", before: "60 min", after: "50 min",
                               why: why, undo: nil, afterDay: day)
            c.undone = undone
            return c
        }
        let why = NextWeekTune.whyPrefixForPlan + "Tue run: 60 \u{2192} 50 min"
        XCTAssertTrue(NextWeekTune.takenInPlan([line(why, day: "2030-01-15")], monday: "2030-01-14"))
        XCTAssertFalse(NextWeekTune.takenInPlan([line(why, day: "2030-01-15", undone: true)], monday: "2030-01-14"), "undone: offered again")
        XCTAssertFalse(NextWeekTune.takenInPlan([line(why, day: "2030-01-22")], monday: "2030-01-14"), "another week")
        XCTAssertFalse(NextWeekTune.takenInPlan([line("Suggestion: an easier day", day: "2030-01-15")], monday: "2030-01-14"), "another card")
    }

    // MARK: room for a tune-up

    func testRoomForATuneUpIsMadeOnceAndNeverOnASessionLoggedSince() throws {
        var b = try fixture()
        b.weeks = (1...3).map { n in PlanWeek(number: n, monday: PlanView.addDays("2030-01-07", 7 * (n - 1)), phase: "Build", tag: "") }
        for (day, sport, title, m) in [("2030-01-10", "run", "Tempo run", 60.0), ("2030-01-11", "bike", "Long ride", 90),
                                       ("2030-01-12", "swim", "Swim set", 45), ("2030-01-14", "run", "Hill run", 60)] {
            try b.add(SessionDraft(dayKey: day, sport: sport, title: title, minutes: m, intensity: "Hard"))
        }
        b.changes = []
        let tuneUp = TuneUp(id: "t", day: "2030-01-13")
        let c = TuneUpRoom.plan(tuneUp, sessions: b.sessions, weeks: b.weeks, mainRaceDay: "2030-07-14", mapping: b.mapping, today: "2030-01-01")
        XCTAssertFalse(TuneUpRoom.takenInPlan(b.changes, tuneUp: tuneUp))

        // Thursday's run is logged after the card was worked out: Take it leaves it as it is.
        let thu = try XCTUnwrap(c.edits.first { $0.day == "2030-01-10" })
        let i = try XCTUnwrap(b.sessions.firstIndex { $0.key == thu.key })
        b.sessions[i].results["done"] = ResultValue(text: "\u{2713}", number: nil, date: nil)
        let logged = b.sessions[i]
        let ids = try TuneUpRoom.apply(c, to: &b, why: TuneUpRoom.why(batch: "s1"))
        XCTAssertEqual(ids.count, c.edits.count + c.removals.count - 1)
        XCTAssertEqual(b.session(thu.key), logged)

        // Taken: never offered a second time (here, or on a device whose shelf has not caught up).
        XCTAssertTrue(TuneUpRoom.takenInPlan(b.changes, tuneUp: tuneUp))
        XCTAssertFalse(TuneUpRoom.takenInPlan(b.changes, tuneUp: TuneUp(id: "u", day: "2030-03-03")), "another tune-up")
        XCTAssertEqual(try TuneUpRoom.undo(batch: "s1", in: &b), ids.count)
        XCTAssertFalse(TuneUpRoom.takenInPlan(b.changes, tuneUp: tuneUp), "undone: offered again")
    }

    // MARK: zones from sessions

    func testZonesLeaveGlitchSizedSessionsOut() {
        func s(_ id: Int, _ sport: String, pulse: Double? = nil, power: Double? = nil, powerPulse: Double? = nil, swim: Double? = nil) -> SessionZones.Sample {
            SessionZones.Sample(activityId: id, day: "2030-02-0\(id)", sport: sport, pulse: pulse, power: power, powerPulse: powerPulse, swimPace: swim)
        }
        let today = "2030-02-10"
        // A strap that slipped: 20 beats above in two sessions is not fitness. Within 10 %: offered.
        XCTAssertNil(SessionZones.proposal([s(1, "run", pulse: 181), s(2, "bike", pulse: 182)], inUse: .init(lthr: 160), today: today))
        XCTAssertEqual(SessionZones.proposal([s(1, "run", pulse: 170), s(2, "bike", pulse: 168)], inUse: .init(lthr: 160), today: today)?.row(.pulse)?.new, 168)
        // A pool length set wrong on the watch: twice as fast. A real step: offered.
        XCTAssertNil(SessionZones.proposal([s(1, "swim", swim: 57), s(2, "swim", swim: 58)], inUse: .init(css: 112), today: today))
        XCTAssertEqual(SessionZones.proposal([s(1, "swim", swim: 106), s(2, "swim", swim: 107)], inUse: .init(css: 112), today: today)?.row(.swim)?.new, 107)
        // Run power: far above the one in use, or out of reach the first time, is left out.
        XCTAssertNil(SessionZones.proposal([s(1, "run", power: 330, powerPulse: 158), s(2, "run", power: 335, powerPulse: 159)],
                                           inUse: .init(lthr: 160, runPower: 250), today: today)?.row(.runPower))
        XCTAssertNil(SessionZones.proposal([s(1, "run", power: 1210, powerPulse: 158), s(2, "run", power: 1190, powerPulse: 159)],
                                           inUse: .init(lthr: 160), today: today)?.row(.runPower))
        XCTAssertEqual(SessionZones.proposal([s(1, "run", power: 262, powerPulse: 158), s(2, "run", power: 258, powerPulse: 159)],
                                             inUse: .init(lthr: 160), today: today)?.row(.runPower)?.new, 258)
    }
}
