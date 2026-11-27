import XCTest
@testable import WorkoutCore

/* Round 30, lane coach: drill cards, swim video check, block intro. */
final class Coach30Tests: XCTestCase {

    // MARK: drill cards

    func testEveryCardHasThreeStepsADrawingAndAUniqueId() {
        XCTAssertGreaterThanOrEqual(DrillCards.cards(of: .swim).count, 10)
        XCTAssertEqual(Set(DrillCards.all.map(\.id)).count, DrillCards.all.count)
        for c in DrillCards.all {
            XCTAssertEqual(c.steps.count, 3, c.id)
            XCTAssertFalse(c.trains.isEmpty, c.id)
            XCTAssertTrue(c.drawing.fitsTheBox, "\(c.id) leaves the box")
        }
    }

    func testASwimSessionFindsItsDrills() {
        let m = DrillCards.matches(in: "Technique: 4x50 catch-up, then 4x50 fist, 100 easy", discipline: "swim")
        XCTAssertEqual(m.map(\.id), ["catch-up", "fist"])
        XCTAssertEqual(DrillCards.rowWords(m), "Drill cards: Catch-up, Fist")
        XCTAssertEqual(DrillCards.matches(in: "6-1-6 and kick on the side", discipline: "swim").map(\.id), ["side-kick", "six-one-six"])
        XCTAssertEqual(DrillCards.matches(in: "Single arm drills", discipline: "swim").map(\.id), ["single-arm"])
    }

    func testAGeneralDrillWordFindsNoCardButIsKnown() {
        XCTAssertTrue(DrillCards.matches(in: "Easy technique: 4x50 drill, then 6x50 smooth", discipline: "swim").isEmpty)
        XCTAssertTrue(DrillCards.mentionsDrillsInGeneral("8x50 drills + 6x100 easy"))
    }

    func testStrengthWordsAndTheLongestPhraseWins() {
        XCTAssertEqual(DrillCards.matches(in: "Squat, hinge, press, row", discipline: "strength").map(\.id), ["squats", "hip-hinge", "row"])
        XCTAssertEqual(DrillCards.matches(in: "Side plank 20 s each side", discipline: "strength").map(\.id), ["side-plank"])
        XCTAssertEqual(DrillCards.matches(in: "Plank and side plank", discipline: "strength").map(\.id), ["plank", "side-plank"])
        XCTAssertEqual(DrillCards.matches(in: "Calf raises", discipline: "strength").map(\.id), ["calf-raises"])
        XCTAssertEqual(DrillCards.matches(in: "Mobility: hips, hamstrings, calves, upper back", discipline: "mobility").map(\.id),
                       ["hamstring-stretch", "calf-stretch", "open-book", "hip-flexor-stretch"])
    }

    func testOtherSportsAndWrongKindsFindNothing() {
        XCTAssertTrue(DrillCards.matches(in: "catch-up fist squat", discipline: "run").isEmpty)
        XCTAssertTrue(DrillCards.matches(in: "squat", discipline: "swim").isEmpty)
        XCTAssertTrue(DrillCards.matches(in: "catch-up", discipline: "strength").isEmpty)
    }

    // MARK: swim video check

    func testSixFramesSpreadEvenlyInsideTheVideo() {
        let t = SwimCheck.frameTimes(duration: 60)
        XCTAssertEqual(t, [5, 15, 25, 35, 45, 55])
        XCTAssertEqual(SwimCheck.frameTimes(duration: 0), [0])
    }

    private func reply(_ tips: String, stop: String = "end_turn") -> Data {
        let inner = "{\"tips\": \(tips)}"
        let root: [String: Any] = ["stop_reason": stop, "content": [["type": "text", "text": inner]]]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testExactlyThreeCleanTipsPassAndLinkToCards() {
        let ok = reply("[{\"text\":\"Reach a little further before you pull.\",\"drill\":\"catch-up\"},{\"text\":\"Keep the elbow high in the pull.\",\"drill\":\"none\"},{\"text\":\"Try a few strokes of fist swimming.\",\"drill\":\"squats\"}]")
        let tips = SwimCheck.read(ok)
        XCTAssertEqual(tips?.count, 3)
        XCTAssertEqual(tips?[0].drill, "catch-up")
        XCTAssertNil(tips?[1].drill)
        XCTAssertEqual(tips?[2].drill, "fist")       // a strength card is no swim link; the words name the fist drill
    }

    func testTipsAboutTheBodyTooLongOrTheWrongNumberAreRefused() {
        let body = reply("[{\"text\":\"Lose some weight to float better.\",\"drill\":\"none\"},{\"text\":\"Keep the elbow high.\",\"drill\":\"none\"},{\"text\":\"Breathe to the side.\",\"drill\":\"none\"}]")
        XCTAssertNil(SwimCheck.read(body))
        let long = String(repeating: "Reach further. ", count: 12)
        XCTAssertNil(SwimCheck.read(reply("[{\"text\":\"\(long)\",\"drill\":\"none\"},{\"text\":\"a\",\"drill\":\"none\"},{\"text\":\"b\",\"drill\":\"none\"}]")))
        XCTAssertNil(SwimCheck.read(reply("[{\"text\":\"Reach further.\",\"drill\":\"none\"}]")))
        XCTAssertNil(SwimCheck.read(reply("[]", stop: "max_tokens")))
        XCTAssertEqual(SwimCheck.accepted(SwimCheck.invented.map { ($0.text, $0.drill) }), SwimCheck.invented)
    }

    func testTheRequestCarriesSixPicturesAndNothingElse() throws {
        let data = SwimCheck.body(jpegBase64: Array(repeating: "AAAA", count: 6))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.filter { $0["type"] as? String == "image" }.count, 6)
        XCTAssertEqual(content.count, 7)
        XCTAssertEqual(SwimCheck.shelfKey(day: "2026-09-16"), "coach/swimcheck/2026-09-16")
    }

    // MARK: block intro

    private func weeks() -> [BlockWeek] {
        // Base 1 (2 weeks), Build 1 (3 weeks, the last one easy), Taper (2 weeks, the race in the last), Post-season.
        var out: [BlockWeek] = []
        var monday = "2026-09-07"
        func add(_ phase: String, _ n: Int, easyLast: Bool = false) {
            for i in 0..<n { out.append(BlockWeek(monday: monday, phase: phase, isEasy: easyLast && i == n - 1)); monday = PlanView.addDays(monday, 7) }
        }
        add("Base 1 \u{2014} Aerobic Development", 2)
        add("Build 1", 3, easyLast: true)
        add("Taper", 2)
        add("Post-season", 1)
        return out
    }

    func testBlocksFollowThePlansPhasesEasyWeeksAndTheRace() {
        let raceDay = "2026-10-25"   // Sunday of the second Taper week
        let b = BlockIntro.blocks(weeks: weeks(), raceDay: raceDay)
        XCTAssertEqual(b.map(\.kind), [.base, .build, .easyWeek, .taper, .raceWeek, .postSeason])
        XCTAssertEqual(b.map(\.name), ["Base 1", "Build 1", "Easy week", "Taper", "Race week", "Post-season"])
        XCTAssertEqual(b[0].first, "2026-09-07")
        XCTAssertEqual(BlockIntro.kind(ofPhase: "Peak \u{2014} Race Specific"), .peak)
        XCTAssertNil(BlockIntro.kind(ofPhase: "Holiday"))
    }

    func testTheCardShowsOnTheFirstThreeDaysOnlyAndNotOnceSeen() {
        let w = weeks()
        let day1 = "2026-09-21"                          // Monday of Build 1
        let block = BlockIntro.block(on: PlanView.addDays(day1, 2), weeks: w, raceDay: nil)
        XCTAssertEqual(block?.name, "Build 1")
        XCTAssertEqual(block?.first, day1)
        XCTAssertEqual(BlockIntro.dayInBlock(PlanView.addDays(day1, 2), block!), 2)
        XCTAssertTrue(BlockIntro.isShowing(on: day1, block: block!, seen: false))
        XCTAssertTrue(BlockIntro.isShowing(on: PlanView.addDays(day1, 2), block: block!, seen: false))
        XCTAssertFalse(BlockIntro.isShowing(on: PlanView.addDays(day1, 3), block: block!, seen: false))
        XCTAssertFalse(BlockIntro.isShowing(on: day1, block: block!, seen: true))
        // The second week of Build 1 is still the same block, which began a week earlier: no card.
        let later = BlockIntro.block(on: PlanView.addDays(day1, 8), weeks: w, raceDay: nil)
        XCTAssertEqual(later?.first, day1)
        XCTAssertFalse(BlockIntro.isShowing(on: PlanView.addDays(day1, 8), block: later!, seen: false))
        XCTAssertEqual(BlockIntro.shelfKey(first: day1), "coach/blockintro/2026-09-21")
    }

    func testEveryBlockHasThreeShortCalmLines() {
        for k in BlockKind.allCases {
            let t = BlockIntro.text(k)
            for line in [t.forIt, t.different, t.watch] {
                XCTAssertFalse(line.isEmpty)
                XCTAssertLessThanOrEqual(line.count, 100, "\(k): too long")
                XCTAssertFalse(line.contains("!"))
            }
        }
    }

    func testRaceWeekAndEasyWeekTakeTheirOwnDays() {
        let w = weeks()
        XCTAssertEqual(BlockIntro.block(on: "2026-10-21", weeks: w, raceDay: "2026-10-25")?.kind, .raceWeek)
        XCTAssertEqual(BlockIntro.block(on: "2026-10-06", weeks: w, raceDay: "2026-10-25")?.kind, .easyWeek)
        XCTAssertEqual(BlockIntro.block(on: "2026-10-08", weeks: w, raceDay: "2026-10-25")?.kind, .easyWeek)
    }
}
