import XCTest
@testable import WorkoutCore

final class RemindersTests: XCTestCase {
    // 2026-03-02 is a Monday (invented plan).
    private func s(_ key: String, _ day: String, _ id: String, _ sport: String, min: Double? = nil, intensity: String = "",
                   done: Bool = false, missed: Bool = false, move: Bool = true) -> ReminderSession {
        ReminderSession(key: key, dayKey: day, disciplineId: id, sport: sport, title: sport, intensity: intensity,
                        seconds: min.map { $0 * 60 }, done: done, missed: missed, moveToTodayAllowed: move)
    }
    private let all = ReminderSettings(eveningOn: true, sundayOn: true, missedOn: true)

    func testTomorrowLineOneTwoRest() {
        XCTAssertEqual(Reminders.tomorrowLine([s("a", "2026-03-03", "run", "Run", min: 45, intensity: "Easy")]), "Tomorrow: Run \u{00B7} 45 min easy")
        XCTAssertEqual(Reminders.tomorrowLine([s("a", "d", "swim", "Swim", min: 40), s("b", "d", "strength", "Strength", min: 30)]),
                       "Tomorrow: Swim 40 min \u{00B7} Strength 30 min")
        XCTAssertEqual(Reminders.tomorrowLine([s("a", "d", "rest", "Rest")]), "Tomorrow: rest day")
        XCTAssertNil(Reminders.tomorrowLine([]))
    }

    func testEveningScheduleSkipsPastTimeAndFillsAWeek() {
        let plan = [s("a", "2026-03-03", "run", "Run", min: 45, intensity: "easy"), s("b", "2026-03-04", "rest", "Rest")]
        var set = ReminderSettings(eveningOn: true)
        let late = Reminders.schedule(sessions: plan, today: "2026-03-02", nowMinutes: 21 * 60, settings: set, paused: false)
        XCTAssertEqual(late.map(\.day), ["2026-03-03"])            // today 20:00 has passed; only Tuesday's evening (for Wednesday: rest) is left
        XCTAssertEqual(late.first?.body, "Tomorrow: rest day")
        set.eveningMinutes = 22 * 60
        let early = Reminders.schedule(sessions: plan, today: "2026-03-02", nowMinutes: 9 * 60, settings: set, paused: false)
        XCTAssertEqual(early.first?.body, "Tomorrow: Run \u{00B7} 45 min easy")
        XCTAssertEqual(early.first?.minutes, 22 * 60)
    }

    func testSundayTotalAndCard() {
        let week = [s("a", "2026-03-09", "run", "Run", min: 60), s("b", "2026-03-10", "swim", "Swim", min: 40),
                    s("c", "2026-03-11", "rest", "Rest"), s("d", "2026-03-12", "bike", "Bike", min: 420)]
        XCTAssertEqual(Reminders.sundayLine(week), "Next week: 3 sessions \u{00B7} 8h\u{00A0}40m")
        let out = Reminders.schedule(sessions: week, today: "2026-03-05", nowMinutes: 600, settings: ReminderSettings(sundayOn: true), paused: false)
        XCTAssertEqual(out.map(\.day), ["2026-03-08"])
        XCTAssertEqual(out.first?.minutes, 18 * 60)
        XCTAssertEqual(Reminders.cardWeek(today: "2026-03-08", nowMinutes: 18 * 60, settings: ReminderSettings(sundayOn: true)), "2026-03-09")
        XCTAssertNil(Reminders.cardWeek(today: "2026-03-08", nowMinutes: 17 * 60, settings: ReminderSettings(sundayOn: true)))
        XCTAssertEqual(Reminders.cardWeek(today: "2026-03-09", nowMinutes: 7 * 60, settings: ReminderSettings(sundayOn: true)), "2026-03-09")
        XCTAssertNil(Reminders.cardWeek(today: "2026-03-09", nowMinutes: 9 * 60, settings: ReminderSettings(sundayOn: true)))
        let card = Reminders.card(monday: "2026-03-09", sessions: week, weeks: [ReminderWeek(monday: "2026-03-09", phase: "Build", isEasy: true)])
        XCTAssertEqual(card?.rows.count, 3)
        XCTAssertEqual(card?.letter, "E")
        XCTAssertEqual(card?.phase, "Build")
        XCTAssertEqual(card?.totalSeconds, 520 * 60)
    }

    func testMissedYesterdayWithAndWithoutMove() {
        let set = ReminderSettings(missedOn: true)
        let plan = [s("a", "2026-03-03", "run", "Run", min: 45, move: true),
                    s("b", "2026-03-03", "swim", "Swim", min: 30, move: false),
                    s("c", "2026-03-03", "bike", "Bike", done: true)]
        let out = Reminders.schedule(sessions: plan, today: "2026-03-04", nowMinutes: 6 * 60, settings: set, paused: false)
        XCTAssertEqual(out.count, 2)
        let run = out.first { $0.sessionKey == "a" }, swim = out.first { $0.sessionKey == "b" }
        XCTAssertEqual(run?.body, "Yesterday\u{2019}s Run was not logged.")
        XCTAssertEqual(run?.actions, [.skip, .moveToToday, .itIsDone])
        XCTAssertEqual(swim?.actions, [.skip, .itIsDone])
        // Today's own sessions are asked about tomorrow morning, once the day has ended.
        let next = Reminders.schedule(sessions: plan, today: "2026-03-03", nowMinutes: 12 * 60, settings: set, paused: false)
        XCTAssertEqual(next.map(\.day), ["2026-03-04", "2026-03-04"])
    }

    func testSilentWhilePaused() {
        let plan = [s("a", "2026-03-03", "run", "Run", min: 45)]
        XCTAssertTrue(Reminders.schedule(sessions: plan, today: "2026-03-02", nowMinutes: 0, settings: all, paused: true).isEmpty)
        XCTAssertFalse(Reminders.schedule(sessions: plan, today: "2026-03-02", nowMinutes: 0, settings: all, paused: false).isEmpty)
        XCTAssertTrue(Reminders.schedule(sessions: plan, today: "2026-03-02", nowMinutes: 0, settings: ReminderSettings(), paused: false).isEmpty)
    }
}
