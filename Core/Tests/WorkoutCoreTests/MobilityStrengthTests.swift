import XCTest
@testable import WorkoutCore

/* Mobility Mon · Wed · Fri and strength Tue · Thu (2.14), on a little invented plan: seconds, no workbook of his. */
final class MobilityStrengthTests: XCTestCase {

    /* Five weeks from Mon 7 Jan 2030: two ordinary, one easy, race week, one after. */
    private func book() throws -> PlanBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        var b = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        b.weeks = [("", 1), ("", 2), ("RECOVERY WEEK", 3), ("RACE WEEK \u{2014} THE RACE", 4), ("", 5)].map { tag, n in
            PlanWeek(number: n, monday: PlanView.addDays("2030-01-07", 7 * (n - 1)), phase: "Base", tag: tag)
        }
        func gym(_ day: String, _ title: String, _ m: Double) throws {
            try b.add(SessionDraft(dayKey: day, sport: "strength", title: title, minutes: m, intensity: "RPE 6", purpose: "Invented"))
        }
        try gym("2030-01-07", "Gym A: main lifts", 35)              // week 1 Mon
        try gym("2030-01-09", "Gym B: single-leg + core", 30)       // week 1 Wed
        try gym("2030-01-14", "Gym A: main lifts (single weekly session)", 30)  // week 2 Mon, alone
        try gym("2030-01-21", "Gym light: core only", 25)           // week 3 Mon, a light one
        b.changes = []
        return b
    }

    private func weekday(_ day: String) -> Int {
        (0..<7).first { PlanView.addDays(PlanView.weekStart(day), $0) == day } ?? -1
    }

    func testTheWeeksBecomeMobilityMonWedFriAndStrengthTueThu() throws {
        var b = try book()
        let c = MobilityStrength.plan(weeks: b.weeks, sessions: b.sessions, changes: b.changes, mapping: b.mapping, from: "2030-01-01")

        // Mobility Mon, Wed, Fri in weeks 1–4 (race week too), nothing after the race.
        let mobility = c.adds.filter { $0.draft.sport == "mobility" }
        XCTAssertEqual(mobility.count, 12)
        XCTAssertEqual(Set(mobility.map { weekday($0.draft.dayKey) }), [0, 2, 4])
        XCTAssertTrue(mobility.allSatisfy { $0.draft.minutes == 30 && $0.key == MobilityStrength.mobilityKey($0.draft.dayKey) })
        XCTAssertFalse(mobility.contains { $0.draft.dayKey >= "2030-02-04" }, "nothing after race week")

        // Strength: Mon → Tue, Wed → Thu; a week with one gets a second on Thursday; race week none.
        XCTAssertEqual(c.moves.map(\.from), ["2030-01-07", "2030-01-09", "2030-01-14", "2030-01-21"])
        XCTAssertEqual(c.moves.map(\.draft.dayKey), ["2030-01-08", "2030-01-10", "2030-01-15", "2030-01-22"])
        XCTAssertTrue(c.moves.allSatisfy { $0.draft.minutes == 30 })
        XCTAssertEqual(c.moves[2].draft.title, "Gym A: main lifts", "the words about a single session go")
        let gym = c.adds.filter { $0.draft.sport == "strength" }
        XCTAssertEqual(gym.map(\.draft.dayKey), ["2030-01-17", "2030-01-24"])
        XCTAssertEqual(gym[0].draft.title, "Gym B: single-leg + core", "a copy of the last second session")
        XCTAssertEqual(gym[1].draft.title, "Gym light: core only", "a light week stays light")
        XCTAssertEqual(c.weeks.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(c.weeks[0].before, 65)
        XCTAssertEqual(c.weeks[0].after, 150)   // 65 − 5 + 3 × 30 mobility

        // Written: then nothing is left to offer; one Undo takes it all back.
        let before = b.sessions
        let ids = try MobilityStrength.apply(c, to: &b, why: MobilityStrength.why(batch: "t1"))
        XCTAssertEqual(ids.count, 18)
        XCTAssertEqual(b.moves[c.moves[0].key]?.to, "2030-01-08")
        XCTAssertTrue(MobilityStrength.plan(weeks: b.weeks, sessions: b.sessions, changes: b.changes, mapping: b.mapping, from: "2030-01-01").isEmpty)
        XCTAssertEqual(try MobilityStrength.undo(batch: "t1", in: &b), 18)
        XCTAssertEqual(b.sessions.map(\.key).sorted(), before.map(\.key).sorted())
        XCTAssertEqual(b.sessions.filter { $0.discipline.id == "strength" && $0.dayKey.hasPrefix("2030") }.map(\.dayKey).sorted(),
                       ["2030-01-07", "2030-01-09", "2030-01-14", "2030-01-21"])
    }

    func testMidWeekAndLoggedSessionsAreLeftAlone() throws {
        var b = try book()
        // Week 2's Monday session was logged ahead: it stays where it is and counts as one of the two.
        let monday2 = try XCTUnwrap(b.sessions.first { $0.dayKey == "2030-01-14" && $0.discipline.id == "strength" })
        b.sessions[b.sessions.firstIndex { $0.key == monday2.key }!].results["done"] = ResultValue(text: "\u{2713}", number: nil, date: nil)
        let c = MobilityStrength.plan(weeks: b.weeks, sessions: b.sessions, changes: b.changes, mapping: b.mapping, from: "2030-01-09")
        // From Wednesday of week 1: Monday's past session stays, Wednesday's moves to Thursday, Tuesday is past.
        XCTAssertEqual(c.moves.first?.from, "2030-01-09")
        XCTAssertEqual(c.moves.first?.draft.dayKey, "2030-01-10")
        XCTAssertFalse(c.adds.contains { $0.draft.dayKey < "2030-01-09" })
        XCTAssertFalse(c.moves.contains { $0.key == monday2.key }, "a logged session never moves")
        XCTAssertEqual(c.adds.filter { $0.draft.sport == "strength" && $0.draft.dayKey.hasPrefix("2030-01-1") }.map(\.draft.dayKey),
                       ["2030-01-17"], "week 2: the logged Monday counts, one more on Thursday, apart from it")
    }
}
