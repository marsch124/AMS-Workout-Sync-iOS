import XCTest
@testable import WorkoutCore

/* Claude built in, the pure part: invented API answers, nothing from the network. */
final class ClaudePickTests: XCTestCase {

    // MARK: invented material

    private func choice(_ headline: String) -> RBChoice { RBChoice(moves: [.drop(session: "s1")], headline: headline) }

    private func suggestion(others: Int = 2) -> Suggestion {
        let own = choice("Tue bike: 60 → 40 min, easy")
        let more = [choice("Tue bike: drop it"), choice("Wed run: swap with Thu")].prefix(others).map { $0 }
        let record = SuggestionRecord(day: "2030-01-09", trigger: .t1, step: 1, key: "k", headline: own.headline,
                                      why: "Why: you felt poor two mornings running.", choices: [own.moves] + more.map(\.moves),
                                      tried: [], sessions: ["s1"], closesOn: "2030-01-10")
        return Suggestion(trigger: .t1, step: 1, choice: own, why: "Why: you felt poor two mornings running.",
                          otherChoices: Array(more), review: nil, footer: "", record: record)
    }

    private func context() -> ClaudeContext {
        ClaudeContext(today: "2030-01-09",
                      past: [ClaudeDay(day: "2030-01-07", plannedMinutes: 80, doneMinutes: 75, hard: "4", morning: 3, extras: "hike 90 min"),
                             ClaudeDay(day: "2030-01-08", plannedMinutes: 60, doneMinutes: 0, hard: nil, morning: 2, extras: nil)],
                      ahead: [ClaudeAheadDay(day: "2030-01-10", sessions: "Thu run 40 min Z2")])
    }

    private func answer(text: String? = nil, pick: Int = 1, why: String = "Why: two poor mornings, so a shorter easy ride.",
                        stop: String = "end_turn", blocks: String? = nil) -> Data {
        let inner = text ?? "{\"pick\": \(pick), \"why\": \"\(why)\"}"
        let escaped = String(data: try! JSONSerialization.data(withJSONObject: [inner], options: []), encoding: .utf8)!
            .dropFirst().dropLast()
        let content = blocks ?? "[{\"type\":\"text\",\"text\":\(escaped)}]"
        return Data("""
        {"id":"msg_invented","type":"message","role":"assistant","stop_reason":"\(stop)","content":\(content),
         "usage":{"input_tokens":1200,"output_tokens":60,"cache_creation_input_tokens":0,"cache_read_input_tokens":500}}
        """.utf8)
    }

    // MARK: reading the answer

    func testAGoodPickIsRead() throws {
        let a = try XCTUnwrap(ClaudePick.read(answer(), menuCount: 3))
        XCTAssertEqual(a.pick, 1)
        XCTAssertEqual(a.why, "Why: two poor mornings, so a shorter easy ride.")
        XCTAssertEqual(a.usage, ClaudeUsage(input: 1200, output: 60, cacheCreation: 0, cacheRead: 500))
        XCTAssertEqual(a.takenIndex, 0)
        // 1200 × 4 + 500 × 0.2 + 60 × 20 per million
        XCTAssertEqual(a.usage.dollars, 0.0061, accuracy: 0.0000001)
    }

    func testPickZeroKeepsThePlan() throws {
        let a = try XCTUnwrap(ClaudePick.read(answer(pick: 0, why: "Why: the week looks fine as it is."), menuCount: 3))
        XCTAssertEqual(a.pick, 0)
        XCTAssertNil(a.takenIndex)
    }

    func testAPickOutsideTheMenuIsRefused() {
        XCTAssertNil(ClaudePick.read(answer(pick: 4), menuCount: 3))
        XCTAssertNil(ClaudePick.read(answer(pick: -1), menuCount: 3))
        XCTAssertNil(ClaudePick.read(answer(pick: 3), menuCount: 2))
        XCTAssertNotNil(ClaudePick.read(answer(pick: 3), menuCount: 3))
    }

    func testRefusalAndCutOffGiveNothing() {
        XCTAssertNil(ClaudePick.read(answer(stop: "refusal"), menuCount: 3))
        XCTAssertNil(ClaudePick.read(answer(stop: "max_tokens"), menuCount: 3))
        XCTAssertNil(ClaudePick.read(Data("{\"content\":[]}".utf8), menuCount: 3))
    }

    func testAThinkingBlockBeforeTheTextIsSkipped() throws {
        let inner = "{\\\"pick\\\": 2, \\\"why\\\": \\\"Why: a lighter day suits this week.\\\"}"
        let blocks = "[{\"type\":\"thinking\",\"thinking\":\"hmm\"},{\"type\":\"fallback\"},{\"type\":\"text\",\"text\":\"\(inner)\"}]"
        let a = try XCTUnwrap(ClaudePick.read(answer(blocks: blocks), menuCount: 3))
        XCTAssertEqual(a.pick, 2)
        XCTAssertNil(ClaudePick.read(answer(blocks: "[{\"type\":\"thinking\",\"thinking\":\"hmm\"}]"), menuCount: 3))
    }

    func testBadJsonAndBadWhysGiveNothing() {
        XCTAssertNil(ClaudePick.read(answer(text: "not json"), menuCount: 3))
        XCTAssertNil(ClaudePick.read(answer(text: "{\"pick\": 1.5, \"why\": \"Why: x.\"}"), menuCount: 3))
        XCTAssertNil(ClaudePick.read(answer(text: "{\"pick\": true, \"why\": \"Why: x.\"}"), menuCount: 3))
        XCTAssertNil(ClaudePick.read(answer(why: ""), menuCount: 3))
        XCTAssertNil(ClaudePick.read(answer(why: "Why: " + String(repeating: "a long ", count: 30)), menuCount: 3))
    }

    func testAWhyThatMentionsSleepOrTheBodyIsRefused() {
        for bad in ["Why: you slept badly.", "Why: your sleep was short.", "Why: your HRV is low.", "Why: ask your doctor.",
                    "Why: your resting pulse is up.", "Why: that injury again.", "Why: a medication change."] {
            XCTAssertNil(ClaudePick.read(answer(why: bad), menuCount: 3), bad)
        }
    }

    func testAWhyWithoutItsOpeningGetsIt() throws {
        let a = try XCTUnwrap(ClaudePick.read(answer(why: "two poor mornings."), menuCount: 3))
        XCTAssertEqual(a.why, "Why: two poor mornings.")
    }

    // MARK: the request

    func testTheRequestHoldsEveryMenuLineAndNoNewNumber() {
        let s = suggestion(), c = context()
        let r = ClaudePick.request(for: s, context: c)
        XCTAssertTrue(r.user.contains("0 = keep my plan as it is"))
        XCTAssertTrue(r.user.contains("1 = " + s.choice.headline))
        XCTAssertTrue(r.user.contains(s.why))
        XCTAssertTrue(r.user.contains("2 = " + s.otherChoices[0].headline))
        XCTAssertTrue(r.user.contains("3 = " + s.otherChoices[1].headline))
        XCTAssertTrue(r.user.contains("2030-01-07: planned 80, done 75, hard 4, morning 3, extra hike 90 min"))
        XCTAssertTrue(r.user.contains("2030-01-10: Thu run 40 min Z2"))
        XCTAssertTrue(r.system.contains("120 characters"))

        // Every run of digits in the text came from what was handed in, or is a menu number or a count.
        var handed: [String] = [s.choice.headline, s.why, c.today, String(c.past.count), String(c.ahead.count), "0", "1", "2", "3"]
        handed += s.otherChoices.map { $0.headline }
        for d in c.past {
            handed += [d.day, String(d.plannedMinutes), String(d.doneMinutes)]
            handed.append(d.hard ?? "")
            handed.append(d.morning.map { String($0) } ?? "")
            handed.append(d.extras ?? "")
        }
        for d in c.ahead { handed += [d.day, d.sessions] }
        let allowed = Set(handed.flatMap { digitRuns($0) } + ["5"])
        for run in digitRuns(r.user) {
            XCTAssertTrue(allowed.contains(run), "a number that was not handed in: \(run)")
        }
        // "morning 1 to 5" is the scale he answers on, the one fixed number pair in the text.
    }

    func testTheOneChoiceMenuHasNoSecondLine() {
        let r = ClaudePick.request(for: suggestion(others: 0), context: context())
        XCTAssertFalse(r.user.contains("2 = "))
        XCTAssertEqual(ClaudePick.menuCount(for: suggestion(others: 0)), 1)
        XCTAssertEqual(ClaudePick.menuCount(for: suggestion()), 3)
    }

    func testTheBodyIsExactlyTheAgreedShape() throws {
        let body = ClaudePick.body(system: "s", user: "u")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["model", "max_tokens", "fallbacks", "output_config", "system", "messages"])
        XCTAssertEqual(root["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(root["max_tokens"] as? Int, 16000)
        for forbidden in ["thinking", "temperature", "top_p", "top_k", "tool_choice"] { XCTAssertNil(root[forbidden]) }
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let test = try XCTUnwrap(try JSONSerialization.jsonObject(with: ClaudePick.testBody()) as? [String: Any])
        XCTAssertEqual(test["max_tokens"] as? Int, 16)
        XCTAssertNil(test["output_config"])
    }

    private func digitRuns(_ text: String) -> [String] {
        var runs: [String] = [], current = ""
        for ch in text {
            if ch.isNumber { current.append(ch) } else if !current.isEmpty { runs.append(current); current = "" }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    // MARK: the meter

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func testTheMeterStopsAtTheCap() {
        let now = date(2030, 1, 20)
        var m = ClaudeMeter.fresh(now: now, calendar: cal)
        XCTAssertTrue(m.canSpend(now: now, calendar: cal))
        m.dollars = 4.99
        XCTAssertTrue(m.canSpend(now: now, calendar: cal))
        m.add(usage: ClaudeUsage(input: 1_000_000, output: 0), now: now, calendar: cal)   // 4.00 more
        XCTAssertEqual(m.answers, 1)
        XCTAssertEqual(m.inputTokens, 1_000_000)
        XCTAssertFalse(m.canSpend(now: now, calendar: cal))
        XCTAssertTrue(m.canSpend(cap: 20, now: now, calendar: cal))
    }

    func testTheMeterStartsAgainInANewMonth() {
        var m = ClaudeMeter(month: "2030-01", inputTokens: 5, outputTokens: 5, dollars: 5.2, answers: 9)
        let feb = date(2030, 2, 1)
        XCTAssertFalse(m.canSpend(now: date(2030, 1, 31), calendar: cal))
        XCTAssertTrue(m.canSpend(now: feb, calendar: cal))
        m.add(usage: ClaudeUsage(input: 1000, output: 100), now: feb, calendar: cal)
        XCTAssertEqual(m.month, "2030-02")
        XCTAssertEqual(m.answers, 1)
        XCTAssertEqual(m.dollars, 0.006, accuracy: 0.0000001)
    }

    func testTheMeterRoundTripsThroughJson() throws {
        let m = ClaudeMeter(month: "2030-01", inputTokens: 10, outputTokens: 2, dollars: 0.12, answers: 6)
        XCTAssertEqual(try JSONDecoder().decode(ClaudeMeter.self, from: JSONEncoder().encode(m)), m)
    }

    // MARK: export for Claude

    func testTheExportHasItsHeadingsAndNoKey() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        let book = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        let text = ClaudeExport.brief(book, today: "2026-09-16")
        for heading in ["MY TRAINING SEASON", "PHASES", "TESTS AND ZONES", "THE LAST 8 WEEKS", "THE NEXT 4 WEEKS"] {
            XCTAssertTrue(text.contains(heading), heading)
        }
        XCTAssertFalse(text.contains("{"))
        XCTAssertFalse(text.contains("sk-"))
        XCTAssertNil(text.range(of: "[A-Za-z0-9_-]{32,}", options: .regularExpression), "nothing key-like")
        XCTAssertEqual(text.components(separatedBy: "\nWeek of ").count - 1, 12, "eight weeks back and four ahead")
    }
}
