import XCTest
@testable import WorkoutCore

/* Every number here is invented. */
final class GarminActivityTests: XCTestCase {

    private func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }

    private func run(_ id: Int, _ day: String, _ type: String, _ minutes: Double, start: String? = nil) -> GarminActivitySummary {
        GarminActivitySummary(id: id, typeKey: type, day: day, startGMT: start.flatMap { GarminMorning.parseGMT($0) }, seconds: minutes * 60)
    }

    func testTwoRunsOnOneDayAreNotMixedUpAndASwimIsNeverARun() {
        let list = [run(1, "2026-11-25", "running", 25), run(2, "2026-11-25", "running", 62),
                    run(3, "2026-11-25", "lap_swimming", 60), run(4, "2026-11-24", "running", 60)]
        XCTAssertEqual(GarminActivity.match(day: "2026-11-25", sport: "run", seconds: 60 * 60, among: list)?.id, 2)
        XCTAssertEqual(GarminActivity.match(day: "2026-11-25", sport: "run", seconds: 27 * 60, among: list)?.id, 1)
        XCTAssertEqual(GarminActivity.match(day: "2026-11-25", sport: "swim", seconds: 55 * 60, among: list)?.id, 3)
        // Start time wins when it is known.
        let dated = [run(1, "2026-11-25", "running", 40, start: "2026-11-25T06:00:00"), run(2, "2026-11-25", "running", 40, start: "2026-11-25T17:00:00")]
        XCTAssertEqual(GarminActivity.match(day: "2026-11-25", sport: "run", seconds: 40 * 60, start: GarminMorning.parseGMT("2026-11-25T16:50:00"), among: dated)?.id, 2)
        // No length and two candidates: not guessed. Far-off length: not the same session. No bike: nothing.
        XCTAssertNil(GarminActivity.match(day: "2026-11-25", sport: "run", seconds: nil, among: list))
        XCTAssertNil(GarminActivity.match(day: "2026-11-25", sport: "run", seconds: 10 * 60, among: [run(5, "2026-11-25", "running", 90)]))
        XCTAssertNil(GarminActivity.match(day: "2026-11-25", sport: "bike", seconds: 60 * 60, among: list))
    }

    func testTheListIsReadForgivingly() {
        let a = GarminActivity.summaries(json(#"[{"activityId":7,"activityName":"Easy","startTimeLocal":"2026-11-25 07:12:00","startTimeGMT":"2026-11-25 06:12:00","duration":"3600.5","distance":10000,"averageHR":138,"maxHR":156,"activityType":{"typeKey":"running"},"hrTimeInZone_1":300,"hrTimeInZone_2":"2400"},{"nothing":1}]"#))
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].day, "2026-11-25")
        XCTAssertEqual(a[0].zoneSeconds, [300, 2400, 0, 0, 0])
        XCTAssertEqual(a[0].avgHr, 138)
        XCTAssertEqual(GarminActivity.summaries(json(#"{"activities":[{"activityId":8,"startTimeLocal":"2026-11-24 07:00:00","duration":60}]}"#)).count, 1)
        XCTAssertTrue(GarminActivity.summaries("garbage").isEmpty)
        XCTAssertTrue(GarminActivity.summaries(nil).isEmpty)
        XCTAssertFalse(GarminActivity.isOutdoor("lap_swimming"))
        XCTAssertTrue(GarminActivity.isOutdoor("trail_running"))
    }

    func testLapsFromTheDetailAnswerKeepOnlyGarminsOwnNumbers() {
        let laps = GarminActivity.laps(detail: json(#"{"splitSummaries":[{"splitType":"INTERVAL_ACTIVE","distance":1000,"duration":300,"averageHR":150,"averageSpeed":3.33},{"splitType":"INTERVAL_ACTIVE","distance":1000,"duration":310}]}"#))
        XCTAssertEqual(laps.count, 2)
        XCTAssertEqual(laps[0].speedMps, 3.33)
        XCTAssertNil(laps[1].speedMps)
        XCTAssertTrue(GarminActivity.laps(detail: json("[]")).isEmpty)
    }

    /* A tiny FIT file by hand: two records (with position and pulse) and one lap. */
    func testTheRecordedFileGivesRouteAndPulseAndLaps() {
        func le32(_ v: Int32) -> [UInt8] { let u = UInt32(bitPattern: v); return [UInt8(u & 255), UInt8(u >> 8 & 255), UInt8(u >> 16 & 255), UInt8(u >> 24)] }
        func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8)] }
        var body: [UInt8] = []
        // definition, local 0 = record: lat(0) 4 bytes, lon(1) 4 bytes, heart_rate(3) 1 byte
        body += [0x40, 0, 0] + le16(20) + [3, 0, 4, 0x85, 1, 4, 0x85, 3, 1, 0x02]
        let deg = { (d: Double) in Int32(d / 180.0 * 2147483648.0) }
        body += [0x00] + le32(deg(58.5)) + le32(deg(16.2)) + [140]
        body += [0x00] + le32(deg(58.6)) + le32(deg(16.3)) + [152]
        body += [0x00] + le32(0x7FFFFFFF) + le32(0x7FFFFFFF) + [0xFF]   // nothing recorded: ignored
        // definition, local 1 = lap: total_timer_time(8) 4, total_distance(9) 4, avg_heart_rate(15) 1, avg_speed(13) 2
        body += [0x41, 0, 0] + le16(19) + [4, 8, 4, 0x86, 9, 4, 0x86, 15, 1, 0x02, 13, 2, 0x84]
        body += [0x01] + le32(300_000) + le32(100_000) + [148] + le16(3333)
        var file: [UInt8] = [14, 0x20, 0, 0] + le32(Int32(body.count)) + [0x2E, 0x46, 0x49, 0x54, 0, 0]
        file += body + [0, 0]
        let r = GarminFit.parse(Data(file))
        XCTAssertEqual(r.track.count, 2)
        XCTAssertEqual(r.track[0].lat, 58.5, accuracy: 0.0001)
        XCTAssertEqual(r.pulse, [140, 152])
        XCTAssertEqual(r.laps.count, 1)
        XCTAssertEqual(r.laps[0].metres, 1000)
        XCTAssertEqual(r.laps[0].seconds, 300)
        XCTAssertEqual(r.laps[0].avgHr, 148)
        XCTAssertEqual(r.laps[0].speedMps!, 3.333, accuracy: 0.001)
        // A cut-off or foreign file gives nothing and does not crash.
        XCTAssertTrue(GarminFit.parse(Data(file.prefix(30))).laps.isEmpty)
        XCTAssertTrue(GarminFit.recording(fromDownload: Data("nope".utf8)).isEmpty)
    }

    func testSameKindAndTheLastTimeCard() {
        let now = LastTime.Entry(key: "k5", dayKey: "2026-11-25", sport: "run", title: "Easy run — Z2", row: 5)
        let all = [
            LastTime.Entry(key: "k1", dayKey: "2026-11-03", sport: "run", title: "easy run - z2", row: 1),
            LastTime.Entry(key: "k2", dayKey: "2026-11-18", sport: "run", title: "Intervals", row: 2),
            LastTime.Entry(key: "k3", dayKey: "2026-11-18", sport: "bike", title: "Easy run — Z2", row: 3),
            LastTime.Entry(key: "k4", dayKey: "2026-11-10", sport: "run", title: "Easy  run, Z2", row: 4, done: false),
            LastTime.Entry(key: "k6", dayKey: "2026-12-02", sport: "run", title: "Easy run — Z2", row: 6),
            now,
        ]
        XCTAssertEqual(LastTime.previous(of: now, among: all)?.key, "k1")
        XCTAssertNil(LastTime.previous(of: all[1], among: all))
        let rows = LastTime.rows(now: .init(minutes: 62, km: 10.2, hr: 138, rpe: 0), last: .init(minutes: 58, km: 9.6, hr: 0, rpe: 6))
        XCTAssertEqual(rows.map(\.name), ["Length", "Distance", "Average pulse", "How hard"])
        XCTAssertEqual(rows[2].last, "—")
        XCTAssertEqual(rows[3].now, "—")
        XCTAssertTrue(LastTime.rows(now: .init(minutes: 0, km: 0, hr: 0, rpe: 0), last: .init(minutes: 0, km: 0, hr: 0, rpe: 0)).isEmpty)
    }

    func testTimeInZonesThisWeekAgainstLastAndThePlansWords() {
        func act(_ day: String, _ z: [Double]) -> GarminActivitySummary { GarminActivitySummary(id: 1, typeKey: "running", day: day, seconds: 0, zoneSeconds: z) }
        let r = GarminZoneWeeks.build([act("2026-11-24", [60, 600, 0, 0, 0]), act("2026-11-25", [0, 300, 120, 0, 0]),
                                       act("2026-11-17", [0, 900, 0, 0, 0]), act("2026-11-09", [999, 0, 0, 0, 0])], weekStart: "2026-11-23")
        XCTAssertEqual(r.thisWeek, [60, 900, 120, 0, 0])
        XCTAssertEqual(r.lastWeek, [0, 900, 0, 0, 0])
        XCTAssertEqual(GarminZoneWeeks.planLine(sessions: [("Z1", 3000), ("Z2", 3000), ("Z4–Z5", 600)]), "The plan asks for mostly Z1–Z2 this week")
        XCTAssertEqual(GarminZoneWeeks.planLine(sessions: [("Z2", 3600), ("Z2 + strides", 1800)]), "The plan asks for mostly Z2 this week")
        XCTAssertNil(GarminZoneWeeks.planLine(sessions: [("RPE 6", 3600), ("", 600)]))
    }
}
