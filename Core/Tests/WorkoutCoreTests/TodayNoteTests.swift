import XCTest
@testable import WorkoutCore

/* The "today" note and the guard for "done from outside". All sessions invented. */
final class TodayNoteTests: XCTestCase {
    private func brief(_ key: String, _ day: String, _ sport: String, _ label: String, _ minutes: Double?,
                       done: Bool = false, missed: Bool = false) -> SessionBrief {
        SessionBrief(key: key, dayKey: day, sportID: sport, sportLabel: label, title: "Title \(key)",
                     plannedSeconds: minutes.map { $0 * 60 }, done: done, missed: missed)
    }

    private let today = "2026-12-01"
    private var plan: [SessionBrief] { [
        brief("a", "2026-12-01", "swim", "Swim", 40, done: true),
        brief("b", "2026-12-01", "run", "Run", 45),
        brief("c", "2026-12-01", "bike", "Bike", 60, missed: true),
        brief("d", "2026-12-01", "strength", "Strength", nil),
        brief("e", "2026-11-30", "run", "Run", 30),
        brief("f", "2026-12-02", "rest", "Rest", nil),
        brief("g", "2026-12-03", "bike", "Bike", 70)
    ] }

    func testNoteContent() throws {
        let note = TodayNoteMaker.make(briefs: plan, today: today, canLog: true, planReady: true,
                                       weekDoneSeconds: 40 * 60, weekPlannedSeconds: 215 * 60,
                                       now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(note.v, 1)
        XCTAssertEqual(note.dayWords, "Tue 1 Dec")
        XCTAssertEqual(note.sessions.map(\.key), ["a", "b", "c", "d"])
        XCTAssertEqual(note.sessions.map(\.state), ["done", "todo", "missed", "todo"])
        XCTAssertEqual(note.sessions[1].length, "45 min")
        XCTAssertEqual(note.sessions[1].minutes, 45)
        XCTAssertEqual(note.sessions[1].done, "amsworkoutsync://done/b")
        XCTAssertEqual(note.sessions[1].open, "amsworkoutsync://session/b")
        XCTAssertEqual(note.sessions.map(\.canDone), [false, true, false, false], "done, missed and no length cannot be logged")
        XCTAssertNil(note.sessions[0].done)
        XCTAssertEqual(note.tomorrow, "Rest day")
        XCTAssertEqual(note.week, "40 min done of 3 h 35 min planned")
        let text = String(decoding: try XCTUnwrap(TodayNoteMaker.encoded(note)), as: UTF8.self)
        XCTAssertTrue(text.contains("\"v\":1"))
    }

    func testTomorrowAndRestDay() {
        XCTAssertEqual(TodayNoteMaker.tomorrowLine(plan, "2026-12-03"), "Bike, 1 h 10 min")
        XCTAssertNil(TodayNoteMaker.tomorrowLine(plan, "2026-12-09"))
        let rest = TodayNoteMaker.make(briefs: plan, today: "2026-12-02", canLog: true, planReady: true,
                                       weekDoneSeconds: 0, weekPlannedSeconds: 0)
        XCTAssertEqual(rest.sessions.map(\.state), ["rest"])
        XCTAssertEqual(rest.week, "Nothing planned")
    }

    func testNoLogWhenNotAllowed() {
        let off = TodayNoteMaker.make(briefs: plan, today: today, canLog: false, planReady: true, weekDoneSeconds: 0, weekPlannedSeconds: 0)
        XCTAssertFalse(off.sessions.contains { $0.canDone || $0.done != nil })
    }

    func testSameContentIgnoresWritingMoment() {
        let a = TodayNoteMaker.make(briefs: plan, today: today, canLog: true, planReady: true, weekDoneSeconds: 0, weekPlannedSeconds: 0, now: Date(timeIntervalSince1970: 0))
        let b = TodayNoteMaker.make(briefs: plan, today: today, canLog: true, planReady: true, weekDoneSeconds: 0, weekPlannedSeconds: 0, now: Date(timeIntervalSince1970: 500))
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(TodayNoteMaker.sameContent(a, b))
    }

    func testDoneGuard() {
        func v(_ key: String, canLog: Bool = true, ready: Bool = true, day: String? = nil) -> DoneFromOutside.Verdict {
            DoneFromOutside.verdict(briefs: plan, key: key, today: day ?? today, canLog: canLog, planReady: ready)
        }
        XCTAssertEqual(v("b"), .log(plan[1]))
        XCTAssertEqual(v("a"), .openOnly(.alreadyDone))
        XCTAssertEqual(v("c"), .openOnly(.missed))
        XCTAssertEqual(v("d"), .openOnly(.noLength))
        XCTAssertEqual(v("e"), .openOnly(.notToday), "yesterday's session is never logged from outside")
        XCTAssertEqual(v("g"), .openOnly(.notToday))
        XCTAssertEqual(v("f", day: "2026-12-02"), .openOnly(.rest))
        XCTAssertEqual(v("zz"), .openOnly(.unknownSession))
        XCTAssertEqual(v("b", canLog: false), .openOnly(.loggingNotAllowed))
        XCTAssertEqual(v("b", ready: false), .openOnly(.planNotReady))
    }

    func testDoneLink() {
        XCTAssertEqual(SystemLink.doneURL("a b/1"), "amsworkoutsync://done/a%20b%2F1")
        XCTAssertEqual(SystemLink.doneKey(host: "done", path: "/a b/1"), "a b/1")
        XCTAssertNil(SystemLink.doneKey(host: "session", path: "/x"))
        XCTAssertNil(SystemLink.doneKey(host: "done", path: "/"))
    }
}
