import XCTest
@testable import WorkoutCore

/*
 * Which session a photograph belongs to. A fault here says nothing at all —
 * the pictures are simply not drawn — which is how it went unnoticed until
 * he said he could not see any of them (13 October 2026).
 */
final class PhotoMatchTests: XCTestCase {

    private func belongs(photo: (String, String, String), owner: (String, String, String)) -> Bool {
        PhotoMatch.belongs(photoKey: photo.0, photoDay: photo.1, photoSport: photo.2,
                           ownerKey: owner.0, ownerDay: owner.1, ownerSport: owner.2)
    }

    func testThePlainCaseIsTheRowItWasTakenAgainst() {
        XCTAssertTrue(belongs(photo: ("Weekly Schedules!7", "2026-09-12", "run"),
                              owner: ("Weekly Schedules!7", "2026-09-12", "run")))
    }

    /* A line inserted in Excel shifts every row below it. The pictures stay
       with the session, because the day and the sport did not move. */
    func testARowThatShiftedDoesNotOrphanThePictures() {
        XCTAssertTrue(belongs(photo: ("Weekly Schedules!7", "2026-09-12", "run"),
                              owner: ("Weekly Schedules!8", "2026-09-12", "run")),
                      "a shifted row must not hide the photographs")
    }

    /* A row that has become another kind of session is a different session,
       whatever its number says. */
    func testTheSportAlwaysHasToAgree() {
        XCTAssertFalse(belongs(photo: ("Weekly Schedules!7", "2026-09-12", "run"),
                               owner: ("Weekly Schedules!7", "2026-09-12", "bike")))
        XCTAssertFalse(belongs(photo: ("Weekly Schedules!7", "2026-09-12", "run"),
                               owner: ("Weekly Schedules!8", "2026-09-12", "bike")))
    }

    func testAnotherDaysSessionIsNotIt() {
        XCTAssertFalse(belongs(photo: ("Weekly Schedules!7", "2026-09-12", "run"),
                               owner: ("Weekly Schedules!8", "2026-09-13", "run")))
    }

    /* Moving a session rewrites its date in the same row, so the row still
       names it and the pictures follow it to the new day. */
    func testAMovedSessionKeepsItsPictures() {
        XCTAssertTrue(belongs(photo: ("Weekly Schedules!7", "2026-09-12", "run"),
                              owner: ("Weekly Schedules!7", "2026-09-19", "run")),
                      "a move must not strand the photographs on the old day")
    }

    /* An extra is keyed by what it is, not by a row, so it stays exact: the
       day-and-sport fallback would hand one walk's pictures to another. */
    func testAnExtraIsMatchedExactly() {
        XCTAssertTrue(belongs(photo: ("extra:2026-09-12:walk:30", "2026-09-12", "walk"),
                              owner: ("extra:2026-09-12:walk:30", "2026-09-12", "walk")))
        XCTAssertFalse(belongs(photo: ("extra:2026-09-12:walk:30", "2026-09-12", "walk"),
                               owner: ("extra:2026-09-12:walk:45", "2026-09-12", "walk")),
                       "a different extra on the same day is not the same extra")
    }

    func testAPhotographWithNoDayFallsBackOnNothing() {
        XCTAssertFalse(belongs(photo: ("Weekly Schedules!7", "", "run"),
                               owner: ("Weekly Schedules!8", "", "run")),
                       "with no day to go on, a shifted row cannot be matched")
    }
}
