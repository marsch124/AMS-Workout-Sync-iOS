import XCTest
@testable import WorkoutCore

/* Round 28: the shelf — small things that follow him between devices, apart from the plan. Invented data only. */
final class ShelfTests: XCTestCase {

    private struct Gear: Codable, Equatable { var name: String; var km: Double; var since: Date }
    private func t(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    private func doc(_ ops: [(String, Int?, Int64, String)]) -> ShelfDoc {
        var d = ShelfDoc()
        for (key, value, ms, device) in ops {
            if let value { try! d.set(value, for: key, device: device, now: t(ms)) } else { d.remove(key, device: device, now: t(ms)) }
        }
        return d
    }

    // MARK: typed front

    func testSetGetRemoveRoundTrip() throws {
        var d = ShelfDoc()
        let shoe = Gear(name: "Trail shoe", km: 123.5, since: t(1_700_000_000_123))
        try d.set(shoe, for: "gear", device: "A", now: t(1000))
        XCTAssertEqual(d.get(Gear.self, for: "gear"), shoe)
        XCTAssertNil(d.get(Int.self, for: "gear"))
        let back = try ShelfDoc.decoded(d.encoded())
        XCTAssertEqual(back, d)
        XCTAssertEqual(back.get(Gear.self, for: "gear"), shoe)
        d.remove("gear", device: "A", now: t(2000))
        XCTAssertNil(d.get(Gear.self, for: "gear"))
        XCTAssertEqual(d.keys(), [])
        XCTAssertEqual(d.entries["gear"]?.removed, true)
    }

    func testTooLargeAndBadKeysAreRefused() {
        var d = ShelfDoc()
        XCTAssertThrowsError(try d.set(String(repeating: "x", count: ShelfDoc.maxValueBytes + 1), for: "big", device: "A"))
        XCTAssertThrowsError(try d.set(1, for: "", device: "A"))
        XCTAssertTrue(d.entries.isEmpty)
    }

    func testStampNeverGoesBackwardsWithTheClockSetBack() throws {
        var d = ShelfDoc()
        try d.set(1, for: "k", device: "A", now: t(5000))
        try d.set(2, for: "k", device: "A", now: t(1000))
        XCTAssertEqual(d.entries["k"]?.stampMs, 5001)
        XCTAssertEqual(d.get(Int.self, for: "k"), 2)
    }

    // MARK: the three laws

    func testMergeIsCommutativeAssociativeIdempotent() {
        let a = doc([("x", 1, 100, "A"), ("y", 2, 300, "A"), ("z", nil, 50, "A")])
        let b = doc([("x", 5, 200, "B"), ("y", 7, 250, "B"), ("w", 9, 10, "B")])
        let c = doc([("x", 8, 200, "C"), ("w", nil, 20, "C"), ("y", 3, 300, "C")])
        XCTAssertEqual(ShelfDoc.merge(a, b), ShelfDoc.merge(b, a))
        XCTAssertEqual(ShelfDoc.merge(ShelfDoc.merge(a, b), c), ShelfDoc.merge(a, ShelfDoc.merge(b, c)))
        XCTAssertEqual(ShelfDoc.merge(a, a), a)
        let all = ShelfDoc.merge([a, b, c])
        XCTAssertEqual(all.get(Int.self, for: "x"), 8)   // stamp tie 200: device "C" > "B"
        XCTAssertEqual(all.get(Int.self, for: "y"), 3)   // stamp tie 300: device "C" > "A"
        XCTAssertNil(all.get(Int.self, for: "w"))        // removed later on C
    }

    func testClockTieWithTheSameDeviceStillAgrees() {
        let a = doc([("k", 1, 100, "A")]), b = doc([("k", 2, 100, "A")])
        XCTAssertEqual(ShelfDoc.merge(a, b), ShelfDoc.merge(b, a))
        XCTAssertEqual(ShelfDoc.merge(a, b).get(Int.self, for: "k"), 2)
    }

    // MARK: tombstones

    func testARemovalIsNotBroughtBackByAnOlderCopy() {
        var phone = doc([("away", 1, 100, "P")])
        var mac = phone
        phone.remove("away", device: "P", now: t(200))
        // The Mac, still holding the value, meets the phone's shelf: the value stays gone, either way round.
        XCTAssertNil(ShelfDoc.merge(mac, phone).get(Int.self, for: "away"))
        XCTAssertNil(ShelfDoc.merge(phone, mac).get(Int.self, for: "away"))
        // A newer set after the removal does bring it back.
        try! mac.set(3, for: "away", device: "M", now: t(300))
        XCTAssertEqual(ShelfDoc.merge(phone, mac).get(Int.self, for: "away"), 3)
    }

    // MARK: a newer build's data survives an older build

    func testUnknownEntriesAndFieldsSurviveByteForByte() throws {
        let newer = """
        {"format":3,"newTop":{"a":[1,2.5,true,null,"s"]},"entries":{\
        "gear":{"device":"N","removed":false,"stamp":1000,"value":"{\\"km\\":12.50,\\"z\\":[1]}","weight":7},\
        "strange":{"stamp":"not a number","value":42},\
        "plain":{"device":"N","removed":false,"stamp":900,"value":"5"}}}
        """
        let read = try ShelfDoc.decoded(Data(newer.utf8))
        XCTAssertEqual(read.format, 3)
        XCTAssertNotNil(read.unreadable["strange"])
        XCTAssertEqual(read.entries["gear"]?.extra["weight"], .int(7))
        // An older build adds its own entry and joins with an empty shelf, then writes.
        var mine = ShelfDoc()
        try mine.set(true, for: "race/checklist", device: "O", now: t(500))
        let joined = ShelfDoc.merge(mine, read)
        let again = try ShelfDoc.decoded(joined.encoded())
        XCTAssertEqual(again, joined)
        XCTAssertEqual(again.format, 3)
        XCTAssertEqual(again.entries["gear"]?.value, "{\"km\":12.50,\"z\":[1]}")   // value text, byte for byte
        XCTAssertEqual(again.entries["gear"]?.extra["weight"], .int(7))
        XCTAssertEqual(again.unreadable["strange"], read.unreadable["strange"])
        XCTAssertEqual(again.extra["newTop"], .object(["a": .array([.int(1), .double(2.5), .bool(true), .null, .string("s")])]))
        XCTAssertEqual(again.get(Int.self, for: "plain"), 5)
        XCTAssertEqual(again.get(Bool.self, for: "race/checklist"), true)
        // Setting a key that was unreadable replaces it, and the new entry wins on every device.
        var later = again
        try later.set(1, for: "strange", device: "O", now: t(2000))
        XCTAssertEqual(ShelfDoc.merge(later, read).get(Int.self, for: "strange"), 1)
        XCTAssertEqual(ShelfDoc.merge(read, later), ShelfDoc.merge(later, read))
    }

    func testAFileThatIsNotAShelfFailsAsAWhole() {
        XCTAssertThrowsError(try ShelfDoc.decoded(Data("[1,2]".utf8)))
        XCTAssertThrowsError(try ShelfDoc.decoded(Data("{\"entries\":[]}".utf8)))
        XCTAssertThrowsError(try ShelfDoc.decoded(Data("not json".utf8)))
        XCTAssertEqual(try ShelfDoc.decoded(Data("{}".utf8)), ShelfDoc())
    }

    // MARK: one meeting

    func testJoinWithNothingInICloudWritesUpAndNeverEmpties() {
        let mine = doc([("k", 1, 100, "A")])
        let first = ShelfDoc.join(local: mine, cloud: [], cloudFileThere: false)
        XCTAssertEqual(first.doc, mine)
        XCTAssertFalse(first.changesLocal)
        XCTAssertTrue(first.changesCloud)
        let same = ShelfDoc.join(local: mine, cloud: [mine], cloudFileThere: true)
        XCTAssertFalse(same.changesLocal)
        XCTAssertFalse(same.changesCloud)
        // A conflict copy beside the file: joined, and the file is written to clear it.
        let copy = doc([("j", 2, 50, "B")])
        let three = ShelfDoc.join(local: mine, cloud: [mine, copy], cloudFileThere: true)
        XCTAssertEqual(three.doc.get(Int.self, for: "j"), 2)
        XCTAssertTrue(three.changesLocal)
        XCTAssertTrue(three.changesCloud)
    }

    // MARK: soak

    func testRandomInterleavingsOfThreeDevicesEndEqual() throws {
        var rng = Seeded(seed: 28)
        for round in 0..<300 {
            let count = 2 + Int(rng.next() % 2)
            var devices = Array(repeating: ShelfDoc(), count: count)
            var cloud: ShelfDoc?
            var clock: Int64 = 1_000
            let keys = ["favourites", "away", "gear", "session/Weekly Schedules!7/niggle", "race/checklist"]
            for _ in 0..<(10 + Int(rng.next() % 30)) {
                let i = Int(rng.next() % UInt64(count))
                clock += Int64(rng.next() % 3)   // ties happen
                let skew = Int64(rng.next() % 5) - 2
                let key = keys[Int(rng.next() % UInt64(keys.count))]
                switch rng.next() % 4 {
                case 0, 1: try devices[i].set(Int(rng.next() % 100), for: key, device: "dev\(i)", now: t(clock + skew))
                case 2: devices[i].remove(key, device: "dev\(i)", now: t(clock + skew))
                default:
                    // Meets iCloud: reads, joins, writes back what is joined.
                    let j = ShelfDoc.join(local: devices[i], cloud: cloud.map { [$0] } ?? [], cloudFileThere: cloud != nil)
                    devices[i] = j.doc
                    if j.changesCloud { cloud = try ShelfDoc.decoded(j.doc.encoded()) }
                }
            }
            let expected = ShelfDoc.merge(devices + (cloud.map { [$0] } ?? []))
            // Everyone meets twice, in turn.
            for _ in 0..<2 {
                for i in 0..<count {
                    let j = ShelfDoc.join(local: devices[i], cloud: cloud.map { [$0] } ?? [], cloudFileThere: cloud != nil)
                    devices[i] = j.doc
                    if j.changesCloud { cloud = try ShelfDoc.decoded(j.doc.encoded()) }
                }
            }
            for d in devices { XCTAssertEqual(d, cloud, "round \(round)") }
            XCTAssertEqual(cloud, expected, "round \(round)")
        }
    }
}

/* A small repeatable random source, so a failing round can be found again. */
private struct Seeded {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
