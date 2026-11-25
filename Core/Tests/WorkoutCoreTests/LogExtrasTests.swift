import XCTest
@testable import WorkoutCore

final class LogExtrasTests: XCTestCase {
    func testBrickSumOnlyWhenAllThree() {
        let two = BrickLog.make(bike: "1:10", change: "", run: "40")
        XCTAssertNil(two?.total)
        XCTAssertNil(two?.useSumWords)
        let all = BrickLog.make(bike: "1:10", change: "1:30", run: "40")!
        XCTAssertEqual(all.total, 4200 + 90 + 2400)
        XCTAssertEqual(all.sumAsClock, "1:52")
        XCTAssertTrue(all.useSumWords!.hasPrefix("Use 1h"))
        XCTAssertTrue(all.useSumWords!.hasSuffix("52m as the length"))
        XCTAssertEqual(BrickLog.parseMinutesSeconds("2"), 120)
        XCTAssertEqual(BrickLog.parseMinutesSeconds("0:45"), 45)
        XCTAssertNil(BrickLog.parseMinutesSeconds("1:75"))
    }

    func testStomachTallyAndTolerantDecoding() {
        let notes = [StomachNote(answer: .fine), StomachNote(answer: .fine), StomachNote(answer: .upset, line: "gels")]
        XCTAssertEqual(FuelTally(notes).headline, "3 long sessions · 2 fine · 1 upset")
        XCTAssertEqual(FuelTally([StomachNote(answer: .soso)]).headline, "1 long session · 1 so-so")
        let odd = try! JSONDecoder().decode(StomachNote.self, from: Data(#"{"answer":"great","line":5,"extra":1}"#.utf8))
        XCTAssertNil(odd.answer)
        XCTAssertEqual(odd.line, "")
        XCTAssertTrue(StomachNote.applies(seconds: 5400))
        XCTAssertFalse(StomachNote.applies(seconds: 5399))
        XCTAssertNil(StomachNote.make(answer: nil, line: "  "))
    }

    func testNiggleCountingAndWords() {
        let calf = NiggleNote(place: "Calf", side: "left", line: "tight")
        let items: [(day: String, note: NiggleNote)] = [
            ("2026-11-09", calf), ("2026-11-02", calf), ("2026-11-12", calf),
            ("2026-11-05", NiggleNote(place: "Back")), ("2026-11-06", NiggleNote(place: "Calf", side: "right")),
        ]
        let spots = NiggleCount.spots(items)
        XCTAssertEqual(spots[0], NiggleSpot(label: "Left calf", count: 3, sinceDay: "2026-11-02"))
        XCTAssertEqual(spots.map(\.label), ["Left calf", "Back", "Right calf"])
        XCTAssertEqual(calf.doneLine, "Niggle: left calf — tight")
        XCTAssertEqual(NiggleNote.make(place: "Back", side: "left", line: "")!.side, nil)
        XCTAssertNil(NiggleNote.make(place: "Elbow", side: nil, line: ""))
    }

    func testOpenWaterAndKeys() {
        XCTAssertNil(OpenWaterNote.make(on: false, wetsuit: true, temp: "17", line: ""))
        let w = OpenWaterNote.make(on: true, wetsuit: true, temp: "17", line: " choppy ")!
        XCTAssertEqual(w, OpenWaterNote(wetsuit: true, tempC: 17, line: "choppy"))
        XCTAssertEqual(OpenWaterNote.make(on: true, wetsuit: nil, temp: "abc", line: "")!.tempC, nil)
        XCTAssertEqual(LogExtrasKeys.workoutKey(from: "session/Weekly Schedules!7/niggle", fact: "niggle"), "Weekly Schedules!7")
        XCTAssertNil(LogExtrasKeys.workoutKey(from: "away", fact: "niggle"))
    }
}
