import XCTest
@testable import WorkoutCore

/* The week review and the question page, the pure part: invented numbers, no network. */
final class ClaudeReviewTests: XCTestCase {

    // 2030-01-07 is a Monday.
    private let monday = "2030-01-07"

    private func session(_ id: String, _ day: String, _ sport: RBSport, _ min: Int, _ hard: String = "easy",
                         status: RBStatus = .open, actual: Int? = nil, rpe: Int? = nil, week: Int = 2) -> RBSession {
        RBSession(id: id, day: day, sport: sport, title: "Secret title", plannedMin: min, intensity: hard,
                  originalWeek: week, status: status, actualMin: actual, rpe: rpe)
    }

    private func input() -> RuleBookInput {
        var feel = FeelLog()
        feel.set(.good, on: "2030-01-07"); feel.set(.tired, on: "2030-01-08")
        let sessions = [
            session("a", "2030-01-07", .bike, 60, "Z2", status: .done, actual: 55, rpe: 4),
            session("b", "2030-01-08", .run, 40, "easy", status: .missed),
            session("c", "2030-01-10", .bike, 90, "Z3", status: .done, rpe: 8),
            session("d", "2030-01-14", .swim, 45, "Z2", week: 3),
        ]
        return RuleBookInput(sessions: sessions, weeks: [], planStart: "2030-01-01", extras: [RBExtra(day: "2030-01-12", activity: "hike", minutes: 90, countsAsTraining: true)],
                             feel: feel, today: "2030-01-13")
    }

    func testTheWindowIsSundayEveningUntilMondayNight() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        func at(_ d: Int, _ h: Int) -> Date { c.date(from: DateComponents(year: 2030, month: 1, day: d, hour: h))! }
        XCTAssertFalse(ClaudeReview.inWindow(now: at(13, 16), calendar: c))   // Sunday 16:00
        XCTAssertTrue(ClaudeReview.inWindow(now: at(13, 17), calendar: c))    // Sunday 17:00
        XCTAssertTrue(ClaudeReview.inWindow(now: at(14, 23), calendar: c))    // Monday night
        XCTAssertFalse(ClaudeReview.inWindow(now: at(15, 0), calendar: c))    // Tuesday
        XCTAssertEqual(ClaudeReview.week(today: "2030-01-13"), monday)        // Sunday: this week
        XCTAssertEqual(ClaudeReview.week(today: "2030-01-14"), monday)        // Monday: the week just ended
    }

    func testTheFactsHoldNumbersAndWordsButNoTitles() {
        let text = ClaudeReview.userText(from: input(), monday: monday)
        XCTAssertTrue(text.contains("bike: 145 / 150"), text)          // done 55 + 90 (planned minutes when none logged)
        XCTAssertTrue(text.contains("Mon Good"))
        XCTAssertTrue(text.contains("Tue Tired"))
        XCTAssertTrue(text.contains("Wed no answer"))
        XCTAssertTrue(text.contains("felt 8 of 10 (planned: Z3)"))
        XCTAssertTrue(text.contains("Missed: 1"))
        XCTAssertTrue(text.contains("hike 90 min"))
        XCTAssertTrue(text.contains("Mon: swim 45 min Z2"))             // next week
        XCTAssertFalse(text.contains("Secret title"), "titles never leave the phone")
    }

    private func lines(_ n: Int = 5, _ text: String = "Most planned bike minutes were done.") -> [String] { Array(repeating: text, count: n) }

    func testFiveCleanLinesAndAQuestionPass() {
        XCTAssertNotNil(ClaudeReview.accepted(lines: lines(), question: "What made Thursday feel hard?", facts: ""))
        XCTAssertNotNil(ClaudeReview.accepted(lines: ClaudeReview.invented.lines, question: ClaudeReview.invented.question, facts: ""))
    }

    func testAnythingOffIsNotShown() {
        let q = "What made Thursday feel hard?"
        XCTAssertNil(ClaudeReview.accepted(lines: lines(4), question: q, facts: ""), "four lines")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(6), question: q, facts: ""), "six lines")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(5, String(repeating: "x", count: 141)), question: q, facts: ""), "too long")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(5, "Well done, an excellent week."), question: q, facts: ""), "praise")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(5, "A poor night of sleep explains it."), question: q, facts: ""), "sleep")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(5, "Ask your doctor about the pain."), question: q, facts: ""), "medical talk")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(5, "You stayed healthy all week."), question: q, facts: ""), "the rule book's own word check")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(), question: "Think about Thursday.", facts: ""), "the question must be a question")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(5, "See **bold** here."), question: q, facts: ""), "markup")
        XCTAssertNil(ClaudeReview.accepted(lines: lines(5, "You did 999 minutes of bike."), question: q, facts: "bike 150"), "a number that was not given")
        XCTAssertNotNil(ClaudeReview.accepted(lines: lines(5, "You did 150 minutes of bike."), question: q, facts: "bike 150"))
    }

    func testTheAnswerIsReadOnlyAfterAnOrdinaryEnd() {
        func reply(stop: String) -> Data {
            let inner = try! JSONSerialization.data(withJSONObject: ["lines": lines(), "question": "What made Thursday feel hard?"])
            let text = String(data: inner, encoding: .utf8)!
            let root: [String: Any] = ["stop_reason": stop, "content": [["type": "text", "text": text]], "usage": ["input_tokens": 900, "output_tokens": 120]]
            return try! JSONSerialization.data(withJSONObject: root)
        }
        XCTAssertNotNil(ClaudeReview.read(reply(stop: "end_turn"), facts: ""))
        XCTAssertNil(ClaudeReview.read(reply(stop: "max_tokens"), facts: ""))
        XCTAssertNil(ClaudeReview.read(reply(stop: "refusal"), facts: ""))
        XCTAssertNil(ClaudeReview.read(Data("not json".utf8), facts: ""))
    }

    func testTheRequestUsesThePicksModelAndASmallLimit() throws {
        let body = ClaudeReview.body(system: ClaudeReview.system, user: "x")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, ClaudePick.model)
        XCTAssertEqual(root["max_tokens"] as? Int, ClaudeReview.maxTokens)
        XCTAssertLessThanOrEqual(ClaudeReview.maxTokens, 1500)
        XCTAssertEqual((root["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(root["tools"], "no tools, no way to change anything")
    }

    func testOneReviewPerWeekAndTwelveKept() {
        let a = ClaudeReview.invented
        var all: [ClaudeSavedReview] = []
        for i in 0..<14 { all = all.adding(ClaudeSavedReview(week: String(format: "2030-%02d-01", i % 12 + 1), writtenAt: Date(), answer: a)) }
        XCTAssertEqual(all.count, 12)
        let again = all.adding(ClaudeSavedReview(week: all[0].week, writtenAt: Date(), answer: a))
        XCTAssertEqual(again.count, 12)
        XCTAssertEqual(again.map(\.week), again.map(\.week).sorted(by: >), "newest week first")
    }

    // MARK: Ask

    private let plan = ClaudeAskPlan(today: "2030-01-09", phase: "Build, week 2",
                                     days: [ClaudeAskDay(day: "Thu 2030-01-10", sessions: "bike 45 min Z2")], zoneNames: ["Zone 1", "Zone 2"])

    func testIllnessAndPainQuestionsAreNeverSent() {
        XCTAssertTrue(ClaudeAsk.isAboutIllness("My knee hurts, should I ride?"))
        XCTAssertTrue(ClaudeAsk.isAboutIllness("I have a fever, what now"))
        XCTAssertTrue(ClaudeAsk.isAboutIllness("Is this injury a problem?"))
        XCTAssertFalse(ClaudeAsk.isAboutIllness("Why is Thursday's ride only 45 minutes?"))
        XCTAssertFalse(ClaudeAsk.isAboutIllness("Will it still fit this week?"), "will and still are not ill")
        XCTAssertTrue(ClaudeAsk.doctorLine.contains("doctor") && ClaudeAsk.doctorLine.contains("Not well?"))
    }

    func testTheQuestionRequestHoldsPlanRulesAndZoneNamesOnly() {
        let r = ClaudeAsk.request(question: "Why 45?", plan: plan)
        XCTAssertTrue(r.user.contains("Thu 2030-01-10: bike 45 min Z2"))
        XCTAssertTrue(r.user.contains("Build, week 2"))
        XCTAssertTrue(r.user.contains("Zone 1, Zone 2"))
        XCTAssertTrue(r.user.contains("Friday is the rest day"))
        XCTAssertTrue(r.user.contains("10 per cent above the average of the last 3 weeks"))
        XCTAssertTrue(r.user.hasSuffix("His question: Why 45?"))
        XCTAssertLessThanOrEqual(ClaudeAsk.system.split(whereSeparator: { $0.isWhitespace }).count, 130)
        XCTAssertTrue(ClaudeAsk.system.contains("Move or Change"))
    }

    func testQuestionTextIsTidied() {
        XCTAssertNil(ClaudeAsk.cleanQuestion("   \n  "))
        XCTAssertEqual(ClaudeAsk.cleanQuestion("  Why \n\n 45? "), "Why 45?")
        XCTAssertEqual(ClaudeAsk.cleanQuestion(String(repeating: "a", count: 500))?.count, ClaudeAsk.longestQuestion)
    }

    func testTheAnswerPassesTheSameWordCheck() {
        XCTAssertEqual(ClaudeAsk.cleanAnswer(ClaudeAsk.inventedAnswer), ClaudeAsk.inventedAnswer)
        XCTAssertNil(ClaudeAsk.cleanAnswer("Your heart rate zone is high."))
        XCTAssertNil(ClaudeAsk.cleanAnswer("You need more sleep."))
        XCTAssertNil(ClaudeAsk.cleanAnswer("See a doctor."))
        XCTAssertNil(ClaudeAsk.cleanAnswer("It keeps you healthy."))
        XCTAssertNil(ClaudeAsk.cleanAnswer(String(repeating: "word ", count: 200)))
        XCTAssertNil(ClaudeAsk.cleanAnswer("See https://example.org"))
    }

    func testOnlyTheLastFiveQuestionsAreKept() {
        var items: [ClaudeAskItem] = []
        for i in 0..<8 { items = items.adding(ClaudeAskItem(at: Date(), question: "q\(i)", answer: "a")) }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items.first?.question, "q7")
        let body = ClaudeAsk.body(system: ClaudeAsk.system, user: "x")
        let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(root?["model"] as? String, ClaudePick.model)
    }
}
