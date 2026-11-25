import XCTest
@testable import WorkoutCore

/* Round 28, the plan tools: search (21), the swim set for the pool card (24), "Why this session?" (41). All numbers invented. */
final class PlanToolsTests: XCTestCase {

    // MARK: 21 search

    private func entry(_ id: String, _ day: String, _ group: SearchEntry.Group = .done, sport: String = "run", label: String = "Run",
                       title: String = "", description: String = "", notes: String = "", logged: String = "") -> SearchEntry {
        SearchEntry(id: id, kind: .session, dayKey: day, group: group, sportId: sport, sportLabel: label,
                    title: title, description: description, notes: notes, logged: logged)
    }

    func testSearchMatchesEveryWordAnywhereIgnoringCaseAndAccents() {
        let list = [
            entry("a", "2026-11-25", .done, notes: "Left calf felt tight on the café stop"),
            entry("b", "2026-11-28", .toCome, sport: "swim", label: "Swim", title: "Long swim", description: "Easy technique"),
            entry("c", "2026-10-02", .done, title: "Long run", description: "Steady"),
            entry("d", "2026-11-26", .missed, sport: "bike", label: "Bike", title: "Spin")
        ]
        func ids(_ q: String) -> [String] { SessionSearch.results(q, in: list).flatMap { $0.hits.map(\.entry.id) } }
        XCTAssertEqual(ids("CALF"), ["a"])
        XCTAssertEqual(ids("cafe"), ["a"], "accents do not matter")
        XCTAssertEqual(ids("long"), ["b", "c"], "newest first, To come before Done")
        XCTAssertEqual(ids("long run"), ["c"], "every word has to match")
        XCTAssertEqual(ids("swim"), ["b"], "the sport counts")
        XCTAssertEqual(ids("november"), ["b", "a", "d"], "a date word counts; groups To come, Done, Missed")
        XCTAssertEqual(ids("wed november"), ["a"], "25 Nov 2026 is a Wednesday")
        XCTAssertEqual(ids("xyz"), [])
        XCTAssertEqual(ids("   "), [], "an empty search finds nothing")
        let groups = SessionSearch.results("november", in: list).map(\.group)
        XCTAssertEqual(groups, [.toCome, .done, .missed])
        let hit = SessionSearch.results("calf", in: list)[0].hits[0]
        XCTAssertTrue(hit.found.hasPrefix("Notes: ") && hit.found.lowercased().contains("calf"), hit.found)
    }

    // MARK: 24 swim sets

    func testSwimSetReadsTheUsualWaysASetIsWritten() {
        func rows(_ text: String) -> [String] { SwimSet.parse(text).steps.map(\.line) }
        XCTAssertEqual(rows("4x100"), ["4 \u{00D7} 100 m"])
        XCTAssertEqual(rows("4 × 100m rest 20s Z3"), ["4 \u{00D7} 100 m \u{00B7} rest 20 s \u{00B7} Z3"])
        XCTAssertEqual(rows("200 easy"), ["200 m easy"])
        XCTAssertEqual(rows("Easy technique: 4x50 drill, then 6x50 smooth"),
                       ["Easy technique", "4 \u{00D7} 50 m drill", "6 \u{00D7} 50 m smooth"])
        XCTAssertEqual(rows("8x50 drills + 6x100 easy"), ["8 \u{00D7} 50 m drills", "6 \u{00D7} 100 m easy"])
        XCTAssertEqual(rows("4x100, rest 20s, Z3"), ["4 \u{00D7} 100 m \u{00B7} rest 20 s \u{00B7} Z3"], "rest and zone join the row before")

        let set = SwimSet.parse(sections: [("Warm-up", "300 easy"), ("Main set", "4 x 100 m rest 20 s\n2 x 200 pull Z3"), ("Cool-down", "100 easy")])
        XCTAssertEqual(set.steps.map(\.heading), ["Warm-up", "Main set", "Main set", "Cool-down"])
        XCTAssertEqual(set.totalMetres, 300 + 400 + 400 + 100)
        XCTAssertEqual(SwimSet.metresText(1500), "1,500 m")

        // Text it cannot read stays as its own row, word for word; the rest of the set still reads.
        let odd = SwimSet.parse("Warm-up: 200 easy\nFeel the water, long and loose\n10 min easy kick")
        XCTAssertEqual(odd.steps.map(\.line), ["200 m easy", "Feel the water", "long and loose", "10 min easy kick"])
        XCTAssertEqual(odd.steps.map(\.understood), [true, false, false, false])
        XCTAssertEqual(odd.totalMetres, 200)
        XCTAssertFalse(SwimSet.parse("Hips and T-spine").hasDistance)
        XCTAssertEqual(SwimSet.parse("Hips and T-spine").steps.map(\.line), ["Hips and T-spine"])
    }

    // MARK: 41 purpose

    func testEveryPurposeHasItsOwnPlainLine() {
        typealias I = PurposeInput
        let rows: [(PurposeKind, I)] = [
            (.race, I(sport: "race", title: "Race day", intensity: "Race day", plannedMin: 300)),
            (.test, I(sport: "run", title: "Test \u{2014} 5 km time trial", intensity: "Z4", plannedMin: 40)),
            (.rehearsal, I(sport: "bike", title: "Race sim \u{2014} 2 h at race effort", intensity: "Z3", plannedMin: 150)),
            (.postSeason, I(sport: "run", title: "Easy jog", intensity: "Z1", plannedMin: 30, phase: "Post-season")),
            (.taperSharpener, I(sport: "run", title: "Short strides", intensity: "Z3", plannedMin: 30, phase: "Taper")),
            (.taperEasy, I(sport: "bike", title: "Spin", intensity: "Z1", plannedMin: 40, phase: "Taper")),
            (.brick, I(sport: "brick", title: "Bike then run", intensity: "Z2", plannedMin: 90)),
            (.easyWeek, I(sport: "run", title: "Easy run", intensity: "Z2", plannedMin: 40, weekTag: .easy)),
            (.strengthHeavy, I(sport: "strength", title: "Squat, hinge, press", intensity: "RPE 8", plannedMin: 45)),
            (.strengthLight, I(sport: "strength", title: "Core and hips", intensity: "RPE 5", plannedMin: 30)),
            (.mobility, I(sport: "mobility", title: "Hips and T-spine", intensity: "-", plannedMin: 20)),
            (.swimTechnique, I(sport: "swim", title: "Technique: 8x50 drills", intensity: "Z1-Z2", plannedMin: 45)),
            (.swimThreshold, I(sport: "swim", title: "CSS reps", intensity: "Z4", plannedMin: 50)),
            (.swimAerobic, I(sport: "swim", title: "Steady swim", intensity: "Z2", plannedMin: 45)),
            (.longEndurance, I(sport: "run", title: "Long run", intensity: "Z2", plannedMin: 100)),
            (.vo2, I(sport: "bike", title: "5 x 3 min hard", intensity: "Z5", plannedMin: 60)),
            (.peakQuality, I(sport: "run", title: "Intervals at race pace", intensity: "Z4", plannedMin: 50, phase: "Peak")),
            (.tempo, I(sport: "bike", title: "Sweet spot", intensity: "Z3", plannedMin: 70)),
            (.threshold, I(sport: "run", title: "3 x 10 min", intensity: "Z4", plannedMin: 60, phase: "Build")),
            (.recovery, I(sport: "bike", title: "Easy spin", intensity: "Z1", plannedMin: 40)),
            (.easyAerobic, I(sport: "run", title: "Easy run", intensity: "Z2", plannedMin: 45, phase: "Base"))
        ]
        XCTAssertEqual(Set(rows.map(\.0)), Set(PurposeKind.allCases), "a row for every purpose")
        var seen = Set<String>()
        for (kind, input) in rows {
            XCTAssertEqual(SessionPurpose.kind(input), kind, "\(input.title)")
            let line = SessionPurpose.line(input)
            XCTAssertTrue(line?.hasPrefix("Why: ") ?? false)
            XCTAssertTrue(seen.insert(line ?? "").inserted, "two purposes share one line: \(line ?? "")")
        }
        // Long by its length against the others of its sport.
        XCTAssertEqual(SessionPurpose.kind(PurposeInput(sport: "bike", title: "Steady ride", intensity: "Z2", plannedMin: 150, typicalMin: 90)), .longEndurance)
        XCTAssertEqual(SessionPurpose.kind(PurposeInput(sport: "bike", title: "Steady ride", intensity: "Z2", plannedMin: 90, typicalMin: 90)), .easyAerobic)
        // Unknown kinds give no line.
        XCTAssertNil(SessionPurpose.line(PurposeInput(sport: "rest", title: "Rest day")))
        XCTAssertNil(SessionPurpose.line(PurposeInput(sport: "other", title: "Whatever")))
        XCTAssertNil(SessionPurpose.line(PurposeInput(sport: "run", title: "Run", intensity: "", plannedMin: 30)))
        XCTAssertEqual(SessionPurpose.typicalMinutes([30, 0, 90, 60]), 60)
    }
}
