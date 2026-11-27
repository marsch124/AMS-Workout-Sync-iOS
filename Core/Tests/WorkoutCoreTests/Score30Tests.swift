import XCTest
@testable import WorkoutCore

final class Score30Tests: XCTestCase {
    func testScoreWords() {
        // 45 min in all, zone 2 planned.
        func z(_ below: Double, _ inz: Double, _ above: Double) -> [Double] { [below * 60, inz * 60, above * 60, 0, 0] }
        let on = SessionScore.score(zoneSeconds: z(5, 38, 2), plannedZone: 2)
        XCTAssertEqual(on?.word, .onTarget)
        XCTAssertEqual(on?.line, "38 of 45 min in zone 2")
        XCTAssertEqual(SessionScore.score(zoneSeconds: z(0, 36, 9), plannedZone: 2)?.word, .aBitHard)      // 20 % above
    }

    func testBoundaries() {
        func z(_ inz: Double, _ above: Double) -> [Double] { [0, inz * 36, above * 36, 0, 0] }   // 100 units = 60 min
        XCTAssertEqual(SessionScore.score(zoneSeconds: z(85, 15), plannedZone: 2)?.word, .onTarget)   // 15 %
        XCTAssertEqual(SessionScore.score(zoneSeconds: z(84, 16), plannedZone: 2)?.word, .aBitHard)
        XCTAssertEqual(SessionScore.score(zoneSeconds: z(65, 35), plannedZone: 2)?.word, .aBitHard)   // 35 %
        XCTAssertEqual(SessionScore.score(zoneSeconds: z(64, 36), plannedZone: 2)?.word, .tooHard)
        // Time below the zone does not make it worse, and the line says so.
        let low = SessionScore.score(zoneSeconds: [1800, 600, 0, 0, 0], plannedZone: 2)
        XCTAssertEqual(low?.word, .onTarget)
        XCTAssertEqual(low?.line, "10 of 40 min in zone 2 · most of it below zone 2")
        // Too short, or no zone: nothing.
        XCTAssertNil(SessionScore.score(zoneSeconds: [60, 60, 0, 0, 0], plannedZone: 2))
        XCTAssertNil(SessionScore.score(zoneSeconds: [], plannedZone: 2))
    }

    func testPlannedZoneAndWeek() {
        XCTAssertEqual(SessionScore.plannedZone(intensity: "Z2"), 2)
        XCTAssertEqual(SessionScore.plannedZone(intensity: "Z2 + strides"), 2)
        XCTAssertNil(SessionScore.plannedZone(intensity: "Z4–Z5"))
        XCTAssertNil(SessionScore.plannedZone(intensity: "RPE 6"))
        XCTAssertFalse(SessionScore.isScored(sport: "strength"))
        XCTAssertEqual(SessionScore.weekLine([.onTarget, .aBitHard, .onTarget]), "On target: 2 of 3 sessions this week")
        XCTAssertNil(SessionScore.weekLine([]))
    }

    func testSamePulseMonths() {
        func w(_ day: String, _ hr: Double, _ mps: Double, secs: Double = 2400, p: Double? = nil) -> SteadyWorkout {
            SteadyWorkout(sport: "run", day: day, seconds: secs, avgHr: hr, speedMps: mps, powerW: p)
        }
        let list = [w("2026-09-03", 140, 2.8, p: 200), w("2026-09-10", 138, 2.9, p: 210), w("2026-09-12", 160, 3.5),   // outside band
                    w("2026-10-02", 140, 3.0), w("2026-11-02", 141, 3.0, secs: 600), w("2026-11-04", 139, 3.1), w("2026-11-09", 139, 3.3, p: 220),
                    w("2026-11-10", 139, 3.5, p: 230)]
        let m = SamePulse.byMonth(list, sport: "run", band: 130...145, today: "2026-11-20")
        XCTAssertEqual(m.map(\.month), ["2026-09", "2026-10", "2026-11"])
        XCTAssertEqual(m[0].speedMps ?? 0, 2.85, accuracy: 0.001)
        XCTAssertEqual(m[0].powerW ?? 0, 205, accuracy: 0.001)
        XCTAssertNil(m[1].speedMps)            // one steady run is too few
        XCTAssertEqual(m[2].count, 3)          // the 10-minute one does not count
        XCTAssertEqual(m[2].speedMps ?? 0, 3.3, accuracy: 0.001)
        XCTAssertEqual(SamePulse.line(sport: "run", months: m), "Run: 5:51 /km in Sep → 5:03 /km in Nov at the same pulse")
        XCTAssertEqual(SamePulse.paceText(3.3), "5:03 /km")
        XCTAssertEqual(SamePulse.speedText(7.5), "27 km/h")
        XCTAssertEqual(SamePulse.months(today: "2027-02-03").count, 6)
    }

    func testBandFromZones() {
        let z = Zones(sheet: "x", current: [ZoneRow(label: "LTHR", value: "160")], latestTest: "",
                      tables: [ZoneTable(title: "HEART RATE ZONES", rows: [ZoneRow(label: "Z2 — Aerobic", value: "130–142")])], note: "", abbreviations: [])
        XCTAssertEqual(SamePulse.zone2Band(z), 130...142)
        let z2 = Zones(sheet: "x", current: [ZoneRow(label: "LTHR", value: "160")], latestTest: "", tables: [], note: "", abbreviations: [])
        XCTAssertEqual(SamePulse.zone2Band(z2), 130...142)
        XCTAssertNil(SamePulse.zone2Band(nil))
    }
}
