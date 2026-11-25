import XCTest
@testable import WorkoutCore

/* Spotlight's words, Siri's sentences, "log today's run", the Keys list. All invented sessions. */
final class SystemWordsTests: XCTestCase {
    private func brief(_ key: String, _ day: String, _ sport: String, _ label: String, _ minutes: Double?,
                       title: String = "", done: Bool = false, missed: Bool = false) -> SessionBrief {
        SessionBrief(key: key, dayKey: day, sportID: sport, sportLabel: label, title: title,
                     plannedSeconds: minutes.map { $0 * 60 }, done: done, missed: missed)
    }

    func testSpotlightWindowAndWords() {
        let today = "2026-12-01"   // a Tuesday
        let all = [
            brief("a", "2026-12-01", "swim", "Swim", 40, title: "Easy swim drills"),
            brief("b", "2026-12-14", "run", "Run", 45),                         // day 13: in
            brief("c", "2026-12-15", "run", "Run", 45),                         // day 14: out
            brief("d", "2026-11-17", "bike", "Bike", 60, done: true),           // 14 days back: in
            brief("e", "2026-11-16", "bike", "Bike", 60, done: true),           // 15 days back: out
            brief("f", "2026-11-25", "run", "Run", 30),                         // past, not done: out
            brief("g", "2026-12-02", "rest", "Rest", nil),                      // rest: out
            brief("h", "2026-12-03", "run", "Run", 30, missed: true)            // missed: out
        ]
        let out = SystemWords.spotlightEntries(all, today: today)
        XCTAssertEqual(out.map(\.key), ["d", "a", "b"])
        XCTAssertEqual(out[1].title, "Tue 1 Dec \u{00B7} Swim \u{00B7} 40 min")
        XCTAssertTrue(out[1].keywords.contains("Tuesday"))
        XCTAssertTrue(out[1].keywords.contains("Swim"))
        XCTAssertTrue(out[1].keywords.contains("drills"))
        XCTAssertEqual(Set(out[1].keywords.map { $0.lowercased() }).count, out[1].keywords.count, "no word twice")
    }

    func testSpokenDay() {
        let day = "2026-12-01"
        XCTAssertEqual(SystemWords.spokenDay([], day: day, word: "Today"), "Today is a rest day.")
        XCTAssertEqual(SystemWords.spokenDay([brief("r", day, "rest", "Rest", nil)], day: day, word: "Tomorrow"), "Tomorrow is a rest day.")
        XCTAssertEqual(SystemWords.spokenDay([brief("a", day, "run", "Run", 45)], day: day, word: "Today"), "Today: Run, 45 min.")
        let two = [brief("a", day, "swim", "Swim", 40, done: true), brief("b", day, "run", "Run", 75)]
        XCTAssertEqual(SystemWords.spokenDay(two, day: day, word: "Today"), "Today: Swim, 40 min, done, and Run, 1 h 15 min.")
    }

    func testWeekSentence() {
        XCTAssertEqual(SystemWords.spokenWeek(doneSeconds: 12000, plannedSeconds: 21600), "This week: 3 h 20 min done of 6 h planned.")
        XCTAssertEqual(SystemWords.spokenWeek(doneSeconds: 0, plannedSeconds: 3600), "This week: Nothing done of 1 h planned.")
        XCTAssertEqual(SystemWords.spokenWeek(doneSeconds: 0, plannedSeconds: 0), "Nothing is planned this week.")
    }

    func testLogTodaysRunPicksOnlyOneOpenSession() {
        let day = "2026-12-01"
        let run = brief("r", day, "run", "Run", 45)
        XCTAssertEqual(SystemWords.pickToLog([run, brief("s", day, "swim", "Swim", 40)], today: day, sportID: "run"), .log(run))
        XCTAssertEqual(SystemWords.loggedWords(run), "Logged: Run \u{00B7} 45 min")
        XCTAssertEqual(SystemWords.pickToLog([run], today: day, sportID: "swim"), .noSession)
        XCTAssertEqual(SystemWords.pickToLog([run], today: "2026-12-02", sportID: "run"), .noSession)
        XCTAssertEqual(SystemWords.pickToLog([run, brief("r2", day, "run", "Run", 20)], today: day, sportID: "run"), .two)
        let done = brief("d", day, "run", "Run", 45, done: true)
        XCTAssertEqual(SystemWords.pickToLog([done], today: day, sportID: "run"), .alreadyDone(done))
        let missed = brief("m", day, "run", "Run", 45, missed: true)
        XCTAssertEqual(SystemWords.pickToLog([missed], today: day, sportID: "run"), .missed(missed))
        let blank = brief("n", day, "run", "Run", nil)
        XCTAssertEqual(SystemWords.pickToLog([blank], today: day, sportID: "run"), .noLength(blank))
        XCTAssertFalse(SystemWords.refusal(.two, sport: "Run").isEmpty)
    }

    func testSessionLinkRoundTrip() {
        let key = "Week 3!12 & more"
        let text = SystemLink.sessionURL(key)
        let url = URL(string: text)!
        XCTAssertEqual(SystemLink.sessionKey(host: url.host, path: url.path), key)
        XCTAssertNil(SystemLink.sessionKey(host: "today", path: ""))
    }

    func testKeysListAndNewSessionDay() {
        XCTAssertEqual(KeyGuide.rows.count, Set(KeyGuide.rows.map(\.keys)).count, "no key listed twice")
        XCTAssertTrue(KeyGuide.rows.contains { $0.keys == "\u{2318}N" })
        let today = "2026-12-01"
        XCTAssertEqual(KeyGuide.newSessionDay(today: today, onPlan: false, mode: "week", weekStart: "2026-12-07", month: ""), today)
        XCTAssertEqual(KeyGuide.newSessionDay(today: today, onPlan: true, mode: "week", weekStart: "2026-11-30", month: ""), today)
        XCTAssertEqual(KeyGuide.newSessionDay(today: today, onPlan: true, mode: "week", weekStart: "2026-12-07", month: ""), "2026-12-07")
        XCTAssertEqual(KeyGuide.newSessionDay(today: today, onPlan: true, mode: "month", weekStart: "", month: "2027-01"), "2027-01-01")
        XCTAssertEqual(KeyGuide.newSessionDay(today: today, onPlan: true, mode: "month", weekStart: "", month: "2026-12"), today)
    }
}
