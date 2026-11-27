import XCTest
@testable import WorkoutCore

/*
 * Round 30, lane planmaker: the plan maker (pick 1) and "My week shape" (pick 5).
 * Every number and day here is invented; seconds, no workbook of his.
 */
final class PlanMaker30Tests: XCTestCase {

    // MARK: helpers

    private func fixtureBook() throws -> PlanBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        var b = try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: "2026-09-16").book
        b.changes = []
        return b
    }

    private func weekday(_ day: String) -> Int { WeekShape.weekday(day) }

    /* An invented half: Mon 6 Jan 2031 to Sun 31 Aug 2031, 6 to 10 hours, an easy week every 4th. */
    private let half = PlanMakerSettings(raceName: "Lakeside Half", raceDay: "2031-08-31", distance: .half,
                                         start: "2031-01-06", hoursLow: 6, hoursHigh: 10, easyEvery: 4, testEvery: 8)

    private func purposeKind(_ m: MadeSession, _ w: MadeWeek) -> PurposeKind? {
        SessionPurpose.kind(PurposeInput(sport: m.sport, title: m.title, intensity: m.zone, plannedMin: m.minutes,
                                         phase: w.phase, isKey: m.key, weekTag: w.test ? .test : (w.easy ? .easy : nil)))
    }

    // MARK: week shape

    func testTheWeekShapeKeepsItsOwnRules() {
        var shape = WeekShape(days: [["swim"], ["bike"], ["run"], ["swim"], ["swim", "bike", "mobility"], ["run"], ["run"]],
                              longRide: 5, longRun: 6, rest: 4).normalised
        XCTAssertEqual(shape.days[4], ["mobility"], "the rest day holds nothing but mobility")
        XCTAssertTrue(shape.days[5].contains("bike"), "the long ride day holds a ride")
        XCTAssertTrue(shape.problems.isEmpty)
        XCTAssertTrue(shape.fits("rest", on: 4) && !shape.fits("swim", on: 4))

        shape.longRun = 5
        XCTAssertEqual(shape.problems, ["The long ride and the long run are on the same day."])
        let noSwim = WeekShape(days: Array(repeating: ["bike", "run"], count: 7), longRide: 5, longRun: 6, rest: 4).normalised
        XCTAssertEqual(noSwim.problems, ["No day for a swim."])

        // Kept tolerantly: a shape written by a newer app with fewer or unknown words still reads.
        let data = Data(#"{"days":[["swim","kayak"],["bike"]],"longRide":9,"rest":2}"#.utf8)
        let read = try? JSONDecoder().decode(WeekShape.self, from: data)
        XCTAssertEqual(read?.days.count, 7)
        XCTAssertEqual(read?.days[0], ["swim"])
        XCTAssertEqual(read?.longRide, WeekShape.standard.longRide)
        XCTAssertEqual(read?.rest, 2)
    }

    func testTheWeekShapeIsLearnedFromThePlan() throws {
        var b = try fixtureBook()
        for w in 0..<3 {
            let monday = PlanView.addDays("2030-01-07", 7 * w)
            func add(_ d: Int, _ sport: String, _ title: String, _ m: Double) throws {
                try b.add(SessionDraft(dayKey: PlanView.addDays(monday, d), sport: sport, title: title, minutes: m, intensity: "Z2"))
            }
            try add(0, "swim", "Swim", 40); try add(1, "bike", "Ride", 60); try add(2, "run", "Run", 40)
            try add(3, "rest", "Rest", 0); try add(5, "run", "Long run", 80); try add(6, "bike", "Long ride", 150)
        }
        let plan = b.sessions.filter { $0.dayKey.hasPrefix("2030") }
        let shape = WeekShape.learned(from: plan, mapping: b.mapping)
        XCTAssertEqual(shape.longRide, 6)
        XCTAssertEqual(shape.longRun, 5)
        XCTAssertEqual(shape.rest, 3)
        XCTAssertEqual(shape.days[0], ["swim"])
        XCTAssertEqual(WeekShape.learned(from: [], mapping: b.mapping), .standard)
    }

    // MARK: laying the coming weeks out

    /* Week of Mon 14 Jan 2030 (ordinary) and week of Mon 21 Jan (easy), around invented sessions. */
    private func layOutBook() throws -> PlanBook {
        var b = try fixtureBook()
        b.weeks = [PlanWeek(number: 1, monday: "2030-01-14", phase: "Base", tag: ""),
                   PlanWeek(number: 2, monday: "2030-01-21", phase: "Base", tag: "RECOVERY WEEK")]
        func add(_ day: String, _ sport: String, _ title: String, _ m: Double, _ zone: String = "Z2") throws {
            try b.add(SessionDraft(dayKey: day, sport: sport, title: title, minutes: m, intensity: zone))
        }
        try add("2030-01-14", "run", "Easy run", 40)                 // Mon, logged below: stays
        try add("2030-01-15", "swim", "Aerobic swim", 40)            // Tue → Mon
        try add("2030-01-16", "rest", "Rest day", 0)                 // Wed → Fri
        try add("2030-01-17", "run", "Test \u{2014} run: 30 min", 50, "Test")  // Thu: a test, stays
        try add("2030-01-18", "bike", "Steady ride", 60)             // Fri (rest day) → Tue
        try add("2030-01-19", "run", "Long run: easy", 80)           // Sat → Sun
        try add("2030-01-20", "bike", "Long ride: steady", 120)      // Sun → Sat
        try add("2030-01-22", "swim", "Aerobic swim", 30)            // easy week: stays
        let monday = try XCTUnwrap(b.sessions.firstIndex { $0.dayKey == "2030-01-14" && $0.discipline.id == "run" })
        b.sessions[monday].results["done"] = ResultValue(text: "\u{2713}", number: nil, date: nil)
        b.changes = []
        return b
    }

    func testTheComingWeeksAreLaidOutToTheShape() throws {
        var b = try layOutBook()
        let c = LayOut.plan(sessions: b.sessions, weeks: b.weeks, shape: .standard, mapping: b.mapping, today: "2030-01-13")
        XCTAssertEqual(c.weeks.count, 1, "the easy week keeps its own structure")
        let words = Set(c.moves.map(\.words))
        XCTAssertEqual(words, ["Tue swim \u{2192} Mon", "Wed rest day \u{2192} Fri", "Fri ride \u{2192} Tue",
                               "Sat run \u{2192} Sun", "Sun ride \u{2192} Sat"])
        XCTAssertTrue(c.moves.allSatisfy { PlanView.weekStart($0.from) == PlanView.weekStart($0.to) }, "a session stays in its own week")
        XCTAssertFalse(c.moves.contains { $0.from == "2030-01-14" || $0.from == "2030-01-17" }, "logged and test sessions stay")

        // Not onto a day of the away period: Monday away, the swim goes to Thursday instead.
        let away = AwayPeriod(from: "2030-01-14", until: "2030-01-14", has: [])
        let c2 = LayOut.plan(sessions: b.sessions, weeks: b.weeks, shape: .standard, mapping: b.mapping, today: "2030-01-13", away: away)
        XCTAssertTrue(c2.moves.contains { $0.words == "Tue swim \u{2192} Thu" })
        // Nothing on today or before.
        XCTAssertTrue(LayOut.plan(sessions: b.sessions, weeks: b.weeks, shape: .standard, mapping: b.mapping, today: "2030-01-20").isEmpty)

        // One batch, one Undo.
        let before = Dictionary(uniqueKeysWithValues: b.sessions.map { ($0.key, $0.dayKey) })
        let ids = try LayOut.apply(c, to: &b, why: LayOut.why(batch: "w1"))
        XCTAssertEqual(ids.count, 5)
        XCTAssertTrue(LayOut.plan(sessions: b.sessions, weeks: b.weeks, shape: .standard, mapping: b.mapping, today: "2030-01-13").isEmpty,
                      "laid out once, nothing is left to move")
        XCTAssertEqual(LayOut.latest(in: b)?.batch, "w1")
        XCTAssertEqual(PlanMakerBatch.of(b.changes[0].why), "layout:w1")
        XCTAssertEqual(b.moves[c.moves[0].key]?.to, c.moves[0].to)
        XCTAssertEqual(try LayOut.undo(batch: "w1", in: &b), 5)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: b.sessions.map { ($0.key, $0.dayKey) }), before)
        XCTAssertNil(LayOut.latest(in: b))
    }

    // MARK: the plan maker

    func testTheDraftHasItsBlocksSizedToTheWeeks() {
        let weeks = PlanMaker.make(half, shape: .standard)
        XCTAssertEqual(PlanMaker.weekCount(start: half.start, raceDay: half.raceDay), 34)
        let spans = PlanMaker.spans(weeks)
        XCTAssertEqual(spans.map(\.block), [.base, .build, .peak, .taper, .raceWeek, .postSeason])
        XCTAssertEqual(spans.map(\.weeks), [17, 13, 2, 1, 1, 4])
        XCTAssertEqual(Set(weeks.map(\.phase)), ["Base 1", "Base 2", "Build 1", "Build 2", "Peak", "Taper", "Post-season"])
        XCTAssertEqual(weeks.map(\.number), Array(1...38))
        XCTAssertTrue(weeks.allSatisfy { PlanView.weekStart($0.monday) == $0.monday })

        // Race week: the race on its day, nothing hard, the plan's own heading.
        let raceWeek = weeks[33]
        XCTAssertEqual(raceWeek.tag, "RACE WEEK")
        let race = raceWeek.sessions.filter { $0.sport == "race" }
        XCTAssertEqual(race.map(\.day), ["2031-08-31"])
        XCTAssertEqual(race.first?.zone, "Race day")
        XCTAssertTrue(race.first?.key == true)
        XCTAssertFalse(raceWeek.sessions.contains { $0.sport == "strength" })

        // A full keeps two taper weeks; a sprint a single peak week.
        var full = half; full.distance = .full
        XCTAssertEqual(PlanMaker.spans(PlanMaker.make(full, shape: .standard)).first { $0.block == .taper }?.weeks, 2)
        var sprint = half; sprint.distance = .sprint
        XCTAssertEqual(PlanMaker.spans(PlanMaker.make(sprint, shape: .standard)).first { $0.block == .peak }?.weeks, 1)
    }

    func testLongSessionsGrowAtMostTenPercentAWeek() {
        for s in [half, PlanMakerSettings(raceDay: "2031-05-25", distance: .olympic, start: "2031-01-06", hoursLow: 4, hoursHigh: 12)] {
            var longest: [String: Int] = [:]
            for w in PlanMaker.make(s, shape: .standard) {
                for m in w.sessions where m.title.hasPrefix("Long ride") || m.title.hasPrefix("Long run") {
                    let kind = m.sport
                    if let top = longest[kind] {
                        XCTAssertLessThanOrEqual(Double(m.minutes), Double(top) * 1.10 + 0.001, "week \(w.number) \(m.title)")
                    }
                    longest[kind] = max(longest[kind] ?? 0, m.minutes)
                }
            }
            XCTAssertGreaterThan(longest["bike"] ?? 0, 60)
        }
    }

    func testEasyWeeksAreAboutAThirdLessAndTestsComeAboutEveryEightWeeks() {
        let weeks = PlanMaker.make(half, shape: .standard)
        let easy = weeks.filter(\.easy).map(\.number)
        XCTAssertEqual(easy, [4, 8, 12, 16, 20, 24, 28])
        for w in weeks where w.easy && !w.test {
            let ratio = Double(w.minutes) / Double(weeks[w.number - 2].minutes)
            XCTAssertTrue((0.55...0.8).contains(ratio), "week \(w.number): \(ratio)")
        }
        let tests = weeks.filter(\.test)
        XCTAssertEqual(tests.map(\.number), [4, 12, 20, 28])
        for w in tests {
            let titles = w.sessions.map(\.title)
            for sport in ["swim", "bike", "run"] {
                XCTAssertTrue(titles.contains { $0.hasPrefix("Test \u{2014} " + sport) }, "week \(w.number) has a \(sport) test")
            }
            XCTAssertTrue(w.tag.contains("TEST"))
        }
        // An easy week every 3rd: tests stay about 8 weeks apart.
        var three = half; three.easyEvery = 3
        let gaps = zip(PlanMaker.make(three, shape: .standard).filter(\.test).map(\.number).dropFirst(),
                       PlanMaker.make(three, shape: .standard).filter(\.test).map(\.number)).map { $0 - $1 }
        XCTAssertFalse(gaps.isEmpty)
        XCTAssertTrue(gaps.allSatisfy { (6...10).contains($0) }, "\(gaps)")
    }

    func testStrengthMobilityAndDaysFollowTheRulesAndTheShape() {
        let weeks = PlanMaker.make(half, shape: .standard)
        for w in weeks where (w.block == .build || w.block == .base) && !w.easy {
            let gym = w.sessions.filter { $0.sport == "strength" }.sorted { $0.minutes > $1.minutes }
            XCTAssertEqual(gym.map(\.minutes), [30, 20], "week \(w.number)")
            XCTAssertEqual(gym.map(\.zone), ["RPE 7\u{2013}8", "RPE 5"])
        }
        for w in weeks where w.block != .raceWeek {
            let mobility = w.sessions.filter { $0.sport == "mobility" }
            XCTAssertEqual(mobility.map { weekday($0.day) }.sorted(), [0, 2, 4], "week \(w.number)")
            XCTAssertTrue(mobility.allSatisfy { $0.minutes == 30 })
            XCTAssertEqual(w.sessions.filter { $0.sport == "rest" }.map { weekday($0.day) }, [4])
        }
        for w in weeks where w.block == .base || w.block == .build || w.block == .peak {
            XCTAssertEqual(w.sessions.filter { $0.title.hasPrefix("Long ride") }.map { weekday($0.day) }, [5])
            XCTAssertEqual(w.sessions.filter { $0.title.hasPrefix("Long run") }.map { weekday($0.day) }, [6])
        }
        // His own shape moves them: long ride Sunday, long run Saturday, rest Monday.
        var mine = WeekShape.standard
        mine.longRide = 6; mine.longRun = 5; mine.rest = 0
        let moved = PlanMaker.make(half, shape: mine.normalised)
        XCTAssertEqual(Set(moved.flatMap(\.sessions).filter { $0.title.hasPrefix("Long ride") }.map { weekday($0.day) }), [6])
        XCTAssertEqual(Set(moved.filter { $0.block != .raceWeek }.flatMap(\.sessions).filter { $0.sport == "rest" }.map { weekday($0.day) }), [0])
    }

    func testEverySessionHasSportMinutesZoneAndAPurposeFromTheAppsOwnRules() {
        let weeks = PlanMaker.make(half, shape: .standard)
        for w in weeks {
            for m in w.sessions {
                XCTAssertFalse(m.purpose.isEmpty, "\(m.title)")
                guard m.sport != "rest" else { continue }
                XCTAssertGreaterThan(m.minutes, 0, "\(m.title)")
                XCTAssertFalse(m.zone.isEmpty, "\(m.title)")
                XCTAssertTrue(m.day >= w.monday && m.day <= PlanView.addDays(w.monday, 6))
                if let kind = purposeKind(m, w), w.block != .raceWeek { XCTAssertEqual(m.purpose, PlanMaker.purposeWords(kind), "\(m.title)") }
            }
        }
        let base = weeks[0], build = weeks.first { $0.block == .build && !$0.easy }!
        XCTAssertEqual(purposeKind(base.sessions.first { $0.title.hasPrefix("Long ride") }!, base), .longEndurance)
        XCTAssertEqual(purposeKind(build.sessions.first { $0.title.hasPrefix("Sweet spot") }!, build), .threshold)
        XCTAssertEqual(purposeKind(build.sessions.first { $0.zone == "RPE 7\u{2013}8" }!, build), .strengthHeavy)
        XCTAssertEqual(purposeKind(build.sessions.first { $0.title.hasPrefix("Brick run") }!, build), .brick)
        let test = weeks.first(where: \.test)!
        XCTAssertEqual(purposeKind(test.sessions.first { $0.title.hasPrefix("Test") }!, test), .test)
        let post = weeks.last!
        XCTAssertEqual(post.sessions.first { $0.sport == "bike" }?.purpose, "Moving for fun, no numbers")
    }

    func testTheDraftFitsTheShelfInSeveralKeys() throws {
        let weeks = PlanMaker.make(half, shape: .standard)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        for w in weeks { XCTAssertLessThan(try encoder.encode(w).count, 64_000) }
        let meta = PlanDraftMeta(settings: half, shape: .standard, madeAt: Date(), weekCount: weeks.count,
                                 sessionCount: weeks.reduce(0) { $0 + $1.sessions.count }, note: ["a", "b", "c"])
        XCTAssertLessThan(try encoder.encode(meta).count, 64_000)
        XCTAssertEqual(PlanMaker.weekKey(12), "planmaker/draft/week/12")
        XCTAssertTrue(PlanMaker.metaKey.hasPrefix(PlanMaker.draftPrefix) && PlanMaker.weekKey(1).hasPrefix(PlanMaker.draftPrefix))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertEqual(try decoder.decode(MadeWeek.self, from: try encoder.encode(weeks[3])), weeks[3])
        XCTAssertEqual(try decoder.decode(PlanDraftMeta.self, from: try encoder.encode(meta)).settings, half)
        // Read back only whole, and only its own weeks.
        let mine = weeks.map { w -> MadeWeek in var w = w; w.draft = meta.id; return w }
        XCTAssertEqual(meta.complete(mine.reversed())?.count, weeks.count)
        XCTAssertNil(meta.complete(Array(mine.dropLast()) + [nil]), "a week still missing")
        var other = mine; other[2].draft = "another"
        XCTAssertNil(meta.complete(other), "a week of another draft")
    }

    func testTheSettingsSayPlainlyWhatIsWrong() {
        XCTAssertEqual(PlanMaker.problems(half, today: "2030-12-01"), [])
        var s = half; s.distance = .full; s.raceDay = "2031-03-30"
        XCTAssertEqual(PlanMaker.problems(s, today: "2030-12-01"), ["Only 12 weeks to the race: a full plan needs at least 16."])
        s = half; s.hoursLow = 9; s.hoursHigh = 7
        XCTAssertEqual(PlanMaker.problems(s, today: "2030-12-01"), ["The high must be at least the low."])
        s = half; s.raceDay = "2032-06-27"
        XCTAssertEqual(PlanMaker.problems(s, today: "2030-12-01"), ["More than 52 weeks to the race: choose a later first day."])
        XCTAssertEqual(PlanMaker.problems(half, today: "2031-01-06"), ["The first day must be after today."])
        XCTAssertEqual(PlanMaker.defaultStart(lastSession: "2031-08-08", today: "2030-12-01"), "2031-08-11")
        XCTAssertEqual(PlanMaker.defaultStart(lastSession: "2031-08-10", today: "2030-12-01"), "2031-08-11")
    }

    func testTweaksComeOnlyFromTheRulesMenu() {
        let weeks = PlanMaker.make(half, shape: .standard)
        let menu = PlanMaker.menu(settings: half, shape: .standard, tweaks: [], weeks: weeks)
        XCTAssertEqual(menu.filter { if case .longRideDay = $0 { return true }; return false }, [.longRideDay(0), .longRideDay(1), .longRideDay(2), .longRideDay(3)])
        XCTAssertTrue(menu.contains(.volume(.build, true)) && menu.contains(.volume(.peak, false)))
        XCTAssertFalse(menu.contains(.volume(.taper, true)))

        let more = PlanMaker.make(half, shape: .standard, tweaks: [.volume(.build, true)])
        let sum = { (list: [MadeWeek]) in list.filter { $0.block == .build }.reduce(0) { $0 + $1.minutes } }
        XCTAssertGreaterThan(sum(more), sum(weeks))
        let sunday = PlanMaker.make(half, shape: .standard, tweaks: [.longRideDay(0)])
        XCTAssertEqual(Set(sunday.flatMap(\.sessions).filter { $0.title.hasPrefix("Long ride") }.map { weekday($0.day) }), [0])
        XCTAssertEqual(PlanMaker.adding(.longRideDay(1), to: [.longRideDay(0), .volume(.base, true)]), [.volume(.base, true), .longRideDay(1)])
        XCTAssertEqual(PlanMaker.adding(.volume(.base, false), to: [.volume(.base, true)]), [.volume(.base, true)])
    }

    // MARK: Claude may only pick from the menu

    func testClaudesAnswerIsCheckedLikeAPick() {
        let weeks = PlanMaker.make(half, shape: .standard)
        let menu = PlanMaker.menu(settings: half, shape: .standard, tweaks: [], weeks: weeks)
        let facts = PlanMakerClaude.facts(settings: half, shape: .standard, tweaks: [], weeks: weeks)
        XCTAssertFalse(facts.contains("Lakeside"), "no name is sent")
        let note = ["The long sessions sit on the weekend.", "Base has 17 weeks before Build.", "The taper is short."]
        XCTAssertEqual(PlanMakerClaude.accepted(picks: [1], note: note, menu: menu, facts: facts)?.picks, [menu[0]])
        XCTAssertEqual(PlanMakerClaude.accepted(picks: [0], note: note, menu: menu, facts: facts)?.picks, [])
        XCTAssertNil(PlanMakerClaude.accepted(picks: [0, 1], note: note, menu: menu, facts: facts), "0 only on its own")
        XCTAssertNil(PlanMakerClaude.accepted(picks: [menu.count + 1], note: note, menu: menu, facts: facts), "outside the menu")
        XCTAssertNil(PlanMakerClaude.accepted(picks: [1, 2], note: note, menu: menu, facts: facts), "two moves of the long ride")
        let up = menu.firstIndex(of: .volume(.base, true))! + 1, down = menu.firstIndex(of: .volume(.peak, false))! + 1
        XCTAssertEqual(PlanMakerClaude.accepted(picks: [up, down], note: note, menu: menu, facts: facts)?.picks.count, 2)
        XCTAssertNil(PlanMakerClaude.accepted(picks: [1, up, down], note: note, menu: menu, facts: facts), "three picks")
        XCTAssertNil(PlanMakerClaude.accepted(picks: [], note: Array(note.prefix(2)), menu: menu, facts: facts), "two lines")
        XCTAssertNil(PlanMakerClaude.accepted(picks: [], note: ["Base has 19 weeks.", note[1], note[2]], menu: menu, facts: facts), "a number not in the facts")
        XCTAssertNil(PlanMakerClaude.accepted(picks: [], note: ["See a doctor first.", note[1], note[2]], menu: menu, facts: facts))
        XCTAssertNil(PlanMakerClaude.accepted(picks: [], note: ["Well done, a brilliant plan.", note[1], note[2]], menu: menu, facts: facts))

        let reply: [String: Any] = ["stop_reason": "end_turn",
                                    "content": [["type": "text", "text": #"{"picks":[1],"note":["The long sessions sit on the weekend.","Base has 17 weeks before Build.","The taper is short."]}"#]]]
        let data = try! JSONSerialization.data(withJSONObject: reply)
        XCTAssertEqual(PlanMakerClaude.read(data, menu: menu, facts: facts)?.note.count, 3)
        let cut: [String: Any] = ["stop_reason": "max_tokens", "content": reply["content"]!]
        XCTAssertNil(PlanMakerClaude.read(try! JSONSerialization.data(withJSONObject: cut), menu: menu, facts: facts))
        XCTAssertEqual(PlanMakerClaude.invented(menu: menu, facts: facts).note.count, 3)
        XCTAssertNotNil(PlanMakerClaude.accepted(picks: PlanMakerClaude.invented(menu: menu, facts: facts).picks.compactMap { t in menu.firstIndex(of: t).map { $0 + 1 } },
                                                 note: PlanMakerClaude.invented(menu: menu, facts: facts).note, menu: menu, facts: facts))
    }

    // MARK: switching to the draft

    /* His invented plan: weeks from Mon 7 Jan 2030, a bike test on 3 Feb, the race on Sun 10 Feb, two sessions after it. */
    private func switchBook() throws -> PlanBook {
        var b = try fixtureBook()
        b.weeks = (0..<7).map { i in
            PlanWeek(number: i + 1, monday: PlanView.addDays("2030-01-07", 7 * i), phase: i < 5 ? "Build" : "Post-season", tag: i == 5 ? "RACE WEEK" : "")
        }
        func add(_ day: String, _ sport: String, _ title: String, _ m: Double, _ zone: String = "Z2") throws {
            try b.add(SessionDraft(dayKey: day, sport: sport, title: title, minutes: m, intensity: zone))
        }
        try add("2030-01-08", "run", "Easy run", 40)
        try add("2030-02-03", "bike", "Test \u{2014} bike: 20 min", 60, "Test")
        try add("2030-02-10", "race", "Race \u{2014} invented", 330, "Race day")
        try add("2030-02-12", "run", "Easy run, no watch", 30)
        try add("2030-02-20", "swim", "Easy swim", 30)
        b.changes = []
        return b
    }

    func testSwitchingAddsTheDraftFromAMondayAndOneUndoTakesItBack() throws {
        var b = try switchBook()
        let s = PlanMakerSettings(raceName: "Invented Half", raceDay: "2030-07-28", distance: .half, start: "2030-02-04")
        let draft = PlanMaker.make(s, shape: .standard)
        XCTAssertEqual(DraftSwitch.firstAllowed(sessions: b.sessions, today: "2030-01-01"), "2030-02-11", "after the race and the test")
        let days = DraftSwitch.days(draft: draft, sessions: b.sessions, today: "2030-01-01")
        XCTAssertEqual(days.first, "2030-02-11")
        XCTAssertEqual(days.last, draft.first { $0.block == .raceWeek }?.monday)

        XCTAssertThrowsError(try DraftSwitch.apply(draft: draft, from: "2030-02-04", raceName: "Invented Half", to: &b, today: "2030-01-01")) {
            XCTAssertEqual($0 as? DraftSwitchError, .tooEarly("2030-02-11"))
        }
        XCTAssertThrowsError(try DraftSwitch.apply(draft: draft, from: "2030-02-12", raceName: "Invented Half", to: &b, today: "2030-01-01"))

        let keep = b.sessions.filter { $0.dayKey < "2030-02-11" }
        let preview = DraftSwitch.preview(sessions: b.sessions, draft: draft, from: "2030-02-11")
        XCTAssertEqual(preview.takenOut, 2)
        XCTAssertGreaterThan(preview.leftOut, 0, "the draft's first week is left out")
        let record = try DraftSwitch.apply(draft: draft, from: "2030-02-11", raceName: "Invented Half", to: &b, today: "2030-01-01", batch: "b1")
        XCTAssertEqual(record.added, preview.added)
        XCTAssertEqual(record.removed, 2)
        XCTAssertEqual(b.sessions.filter { $0.dayKey < "2030-02-11" }, keep, "nothing before that day changes")
        XCTAssertEqual(b.sessions.filter { $0.key.hasPrefix(DraftSwitch.keyPrefix("b1")) && $0.discipline.id != "rest" }.count, preview.added)
        XCTAssertFalse(b.sessions.contains { $0.dayKey >= "2030-02-11" && !$0.key.hasPrefix(DraftSwitch.keyPrefix("b1")) })
        // The weeks: his post-season week replaced by the draft's, the rest added and numbered on.
        XCTAssertEqual(b.week(on: "2030-02-11")?.phase, draft.first { $0.monday == "2030-02-11" }?.phase)
        XCTAssertEqual(b.week(on: "2030-02-25")?.number, 8)
        let added = try XCTUnwrap(b.sessions.first { $0.key == DraftSwitch.keyPrefix("b1") + "1" })
        XCTAssertEqual(added.phase, b.phase(on: added.dayKey))
        // One line for the switch, the two removals keep theirs, no "added" lines.
        XCTAssertEqual(b.changes.map(\.kind).sorted(), ["newplan", "remove", "remove"])
        XCTAssertEqual(DraftSwitch.latest(in: b)?.after, "\(preview.added) sessions from Mon 11 Feb")
        XCTAssertEqual(PlanMakerBatch.of(b.changes.last!.why), "switch:b1")

        // He logs one new session; then one Undo: that one stays, the rest go, his sessions and weeks come back.
        let logged = try XCTUnwrap(b.sessions.firstIndex { $0.key.hasPrefix(DraftSwitch.keyPrefix("b1")) && $0.discipline.id == "swim" })
        b.sessions[logged].results["done"] = ResultValue(text: "\u{2713}", number: nil, date: nil)
        XCTAssertEqual(DraftSwitch.loggedSince(batch: "b1", in: b), 1)
        let ours = b.sessions.filter { $0.key.hasPrefix(DraftSwitch.keyPrefix("b1")) }.count
        XCTAssertEqual(try DraftSwitch.undo(batch: "b1", record: record, in: &b), ours - 1 + 2)
        XCTAssertEqual(b.sessions.filter { $0.key.hasPrefix(DraftSwitch.keyPrefix("b1")) }.count, 1)
        XCTAssertEqual(b.sessions.filter { $0.dayKey >= "2030-02-11" && !$0.key.hasPrefix("App!np") }.map(\.dayKey).sorted(), ["2030-02-12", "2030-02-20"])
        XCTAssertEqual(b.week(on: "2030-02-11")?.phase, "Post-season")
        XCTAssertNil(DraftSwitch.latest(in: b))
        XCTAssertThrowsError(try DraftSwitch.undo(batch: "b1", record: record, in: &b))
    }
}
