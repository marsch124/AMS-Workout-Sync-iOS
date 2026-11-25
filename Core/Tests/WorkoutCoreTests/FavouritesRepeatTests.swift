import XCTest
@testable import WorkoutCore

/* Favourite templates and the weekly repeat rule, on an invented plan. */
final class FavouritesRepeatTests: XCTestCase {
    private func weeks() -> [PlanWeek] {
        // 2030-01-07 is a Monday; ten weeks, the sixth is race week.
        (1...10).map { n in
            PlanWeek(number: n, monday: PlanView.addDays("2030-01-07", 7 * (n - 1)), phase: "Base",
                     tag: n == 6 ? "RACE WEEK \u{2014} THE RACE" : "")
        }
    }

    func testFavouriteListRules() {
        var list: [FavouriteTemplate] = []
        let a = Favourites.template(from: SessionDraft(dayKey: "2030-01-10", sport: "bike", title: " Easy ride ", minutes: 45, intensity: "Z2", purpose: "Steady"))
        XCTAssertTrue(Favourites.add(a, to: &list))
        XCTAssertEqual(list[0].title, "Easy ride")
        XCTAssertTrue(Favourites.isFavourite(sport: "bike", title: "easy  RIDE!", in: list))
        XCTAssertFalse(Favourites.isFavourite(sport: "run", title: "Easy ride", in: list))
        XCTAssertFalse(Favourites.add(FavouriteTemplate(sport: "bike", title: "easy ride"), to: &list))
        XCTAssertTrue(Favourites.add(FavouriteTemplate(id: "b", sport: "run", title: "Long run"), to: &list))
        XCTAssertTrue(Favourites.add(FavouriteTemplate(id: "c", sport: "swim", title: "Drills"), to: &list))
        Favourites.move("c", onto: a.id, in: &list)
        XCTAssertEqual(list.map(\.id), ["c", a.id, "b"])
        Favourites.move(a.id, onto: "b", in: &list)
        XCTAssertEqual(list.map(\.id), ["c", "b", a.id])
        XCTAssertTrue(Favourites.rename("b", to: "  Sunday run ", in: &list))
        XCTAssertFalse(Favourites.rename("b", to: "   ", in: &list))
        XCTAssertEqual(list[1].title, "Sunday run")
        Favourites.remove("c", from: &list)
        XCTAssertEqual(list.count, 2)
    }

    func testFavouriteListStopsAtForty() {
        var list: [FavouriteTemplate] = []
        for n in 0..<45 { Favourites.add(FavouriteTemplate(sport: "run", title: "Run \(n)"), to: &list) }
        XCTAssertEqual(list.count, 40)
    }

    func testATemplateHoldsNoDay() throws {
        let t = FavouriteTemplate(sport: "bike", title: "Ride", minutes: 60, zone: "Z2")
        let json = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        XCTAssertFalse(json.contains("2030"))
        XCTAssertEqual(t.draft(on: "2030-02-01").dayKey, "2030-02-01")
    }

    func testRepeatSkipsRaceWeekAndTheSameSessionAndTheEnd() {
        // Start Thu 10 Jan; repeats on Thu 17 … until the end of week 10.
        let start = "2030-01-10"
        let until = RepeatRule.lastDay(of: weeks())!
        XCTAssertEqual(until, "2030-03-17")
        let r = RepeatRule.plan(start: start, until: until, sport: "bike", title: "Easy ride", weeks: weeks(), sessions: [])
        // Weeks 2…10 minus week 6 (race week) = 8 days.
        XCTAssertEqual(r.days.count, 8)
        XCTAssertEqual(r.days.first, "2030-01-17")
        XCTAssertEqual(r.leftOut, [RepeatRule.LeftOut(day: "2030-02-14", reason: .raceWeek)])
        XCTAssertFalse(r.days.contains("2030-02-14"))
    }

    func testRepeatSkipsADayThatHoldsTheSameSportAndTitle() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        let book = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        let s = try XCTUnwrap(book.sessions.first { $0.discipline.id == "run" })
        let start = PlanView.addDays(s.dayKey, -7)
        let wk = [PlanWeek(number: 1, monday: PlanView.weekStart(start), phase: "Base", tag: "")]
            + (1...4).map { PlanWeek(number: $0 + 1, monday: PlanView.addDays(PlanView.weekStart(start), 7 * $0), phase: "Base", tag: "") }
        let r = RepeatRule.plan(start: start, until: PlanView.addDays(start, 14), sport: "run", title: s.title.uppercased(), weeks: wk, sessions: book.sessions)
        XCTAssertEqual(r.leftOut.first, RepeatRule.LeftOut(day: s.dayKey, reason: .alreadyThere))
        XCTAssertFalse(r.days.contains(s.dayKey))
        // Another sport on that day does not block it.
        let other = RepeatRule.plan(start: start, until: PlanView.addDays(start, 7), sport: "swim", title: s.title, weeks: wk, sessions: book.sessions)
        XCTAssertEqual(other.days, [s.dayKey])
    }

    func testRepeatNeverGoesPastThePlan() {
        let r = RepeatRule.plan(start: "2030-03-14", until: "2030-04-30", sport: "run", title: "Run", weeks: weeks(), sessions: [])
        XCTAssertEqual(r.days, [])
        XCTAssertTrue(r.leftOut.allSatisfy { $0.reason == .outsidePlan })
        XCTAssertEqual(RepeatRule.defaultUntil(from: "2030-03-14", weeks: weeks()), "2030-03-17")
        XCTAssertEqual(RepeatRule.defaultUntil(from: "2030-01-10", weeks: weeks()), "2030-03-07")
    }

    func testOneBatchMarkRunsThroughTheReasonLine() {
        let why = RepeatRule.why(title: "Easy ride", count: 7, batch: "ab12cd34")
        XCTAssertEqual(RepeatRule.batch(of: why), "ab12cd34")
        XCTAssertEqual(RepeatRule.shownWhy(why), "Repeated every week: Easy ride (7 sessions)")
        XCTAssertNil(RepeatRule.batch(of: "Thursday easy rides"))
    }
}
