import XCTest
@testable import WorkoutCore

final class ClaudeTroubleTests: XCTestCase {
    private func body(_ type: String, _ message: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["type": "error", "error": ["type": type, "message": message]])
    }

    func testWhatAnthropicsReplyMeans() {
        XCTAssertNil(ClaudeTrouble.read(status: 200, body: Data()))
        XCTAssertEqual(ClaudeTrouble.read(status: 401, body: body("authentication_error", "invalid x-api-key")), .keyRefused)
        XCTAssertEqual(ClaudeTrouble.read(status: 403, body: body("permission_error", "not allowed")), .keyRefused)
        XCTAssertEqual(ClaudeTrouble.read(status: 402, body: Data()), .noCredit)
        XCTAssertEqual(ClaudeTrouble.read(status: 400, body: body("invalid_request_error", "Your credit balance is too low to access the Anthropic API.")), .noCredit)
        XCTAssertEqual(ClaudeTrouble.read(status: 403, body: body("billing_error", "payment needed")), .noCredit)
        // Hiccups pass by themselves: no line on the card.
        for status in [400, 404, 429, 500, 529] {
            XCTAssertNil(ClaudeTrouble.read(status: status, body: body("overloaded_error", "busy")), "\(status)")
        }
        XCTAssertNil(ClaudeTrouble.read(status: 500, body: Data("not json".utf8)))
    }

    func testEveryCaseSaysWhatToDoInPlainWords() {
        for t in ClaudeTrouble.allCases {
            XCTAssertTrue(t.cardLine.hasPrefix("Claude could not choose: "))
            XCTAssertTrue(t.pageLine.contains("the rule book chooses alone"))
            XCTAssertFalse(t.rowWords.isEmpty)
        }
        XCTAssertFalse(ClaudeTrouble.capReached.needsHim)
    }
}

/* 2.4: where a morning answer came from travels with the answer between devices. */
final class DiaryFeelFromTests: XCTestCase {
    func testTheSourceFollowsTheWinningAnswer() throws {
        let early = Date(timeIntervalSince1970: 1_000), late = Date(timeIntervalSince1970: 2_000)
        var phone = DiaryDoc()
        phone.setFeel(4, on: "2026-11-25", from: "morning", now: late)
        var pad = DiaryDoc()
        pad.setFeel(2, on: "2026-11-25", now: early)
        // Either way round: the later answer wins and brings its source along.
        for joined in [DiaryDoc.merged(phone, pad), DiaryDoc.merged(pad, phone)] {
            XCTAssertEqual(joined.feel["2026-11-25"], 4)
            XCTAssertEqual(joined.feelFrom["2026-11-25"], "morning")
        }
        // An answer given in this app afterwards carries no source.
        var own = DiaryDoc.merged(phone, pad)
        own.setFeel(3, on: "2026-11-25", now: Date(timeIntervalSince1970: 3_000))
        XCTAssertNil(own.feelFrom["2026-11-25"])
        XCTAssertNil(DiaryDoc.merged(own, phone).feelFrom["2026-11-25"])
        // It survives the file, and a file without the field reads as before.
        XCTAssertEqual(try DiaryDoc.decoded(phone.encoded()).feelFrom, ["2026-11-25": "morning"])
        XCTAssertEqual(try DiaryDoc.decoded(Data(#"{"format":1,"feel":{"2026-11-25":4}}"#.utf8)).feelFrom, [:])
        // The same answer on both, the source known on one only: it is kept.
        var plain = phone
        plain.feelFrom = [:]
        XCTAssertEqual(DiaryDoc.merged(plain, phone).feelFrom["2026-11-25"], "morning")
    }
}
