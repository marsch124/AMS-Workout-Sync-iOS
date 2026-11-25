import XCTest
@testable import WorkoutCore

/*
 * The plan changes only by his tap, exactly as the card he sees says, and
 * nothing he logged is ever lost or hidden. A card that no longer fits the
 * plan as it is now is put away and nothing is written. Invented data only.
 */
final class SuggestionSafetyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_789_000_000)
    private let today = "2026-09-16"

    private func book() throws -> PlanBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        return try PlanImport.read(try Data(contentsOf: url), fileName: "plan.xlsx", today: today, now: now).book
    }

    private func log(_ book: inout PlanBook, _ key: String) throws {
        let w = try XCTUnwrap(book.session(key))
        var e = LogEntry(); e.actualDuration = "40"
        _ = try book.apply(QueuedEntry(workout: w, entry: e, now: now), now: now)
    }

    private func entry(_ trigger: RBTrigger, _ moves: [Move], input: RuleBookInput) -> SuggestionEntry {
        let changed = SuggestionApply.touched(moves, input: input) ?? []
        let record = SuggestionRecord(day: input.today, trigger: trigger, step: 0, key: "test", headline: "A test card",
                                      why: "Why: a test.", choices: [moves], tried: [], sessions: changed.map(\.id),
                                      closesOn: changed.map(\.day).filter { $0 >= input.today }.min() ?? input.today)
        return SuggestionEntry(record: record,
                               before: [changed.map(RBBefore.init)])
    }

    /* An open session from today on that a card may drop, and the card. */
    private func dropCard(_ book: PlanBook) throws -> (RBSession, SuggestionEntry) {
        let input = RuleBook.input(book: book, today: today)
        for s in input.sessions where s.counts && s.status == .open && s.day >= today && s.plannedMin >= 20 {
            let e = entry(.section5, [.drop(session: s.id)], input: input)
            if SuggestionApply.fits(e, choice: 0, input: input) { return (s, e) }
        }
        throw XCTSkip("no session a card may drop")
    }

    func testAStaleCardAfterLoggingWritesNothing() throws {
        var book = try book()
        let (s, card) = try dropCard(book)
        try log(&book, s.id)
        let input = RuleBook.input(book: book, today: today)
        XCTAssertFalse(SuggestionApply.fits(card, choice: 0, input: input), "logged since: the card is put away")
        XCTAssertThrowsError(try RuleBook.apply([.drop(session: s.id)], to: input.sessions, input: input),
                             "a logged session is never dropped, whatever asks")
    }

    func testAStaleCardAfterAShorterEditNeverMakesItLonger() throws {
        var book = try book()
        let input = RuleBook.input(book: book, today: today)
        let s = try XCTUnwrap(input.sessions.first { $0.counts && $0.status == .open && $0.day >= today && $0.plannedMin >= 40 })
        let card = entry(.section5, [.shorten(session: s.id, minutes: RuleBook.percent(s.plannedMin, 75))], input: input)
        XCTAssertTrue(SuggestionApply.fits(card, choice: 0, input: input))
        var d = try XCTUnwrap(book.draft(of: s.id))
        d.minutes = 20
        try book.change(s.id, to: d, now: now)
        XCTAssertFalse(SuggestionApply.fits(card, choice: 0, input: RuleBook.input(book: book, today: today)))
    }

    func testAnExtraRestDayWithALoggedSessionThatDayIsRefused() throws {
        var book = try book()
        let input = RuleBook.input(book: book, today: today)
        let day = try XCTUnwrap(Set(input.sessions.filter { $0.counts && $0.status == .open && $0.day >= today }.map(\.day))
            .sorted().first { d in SuggestionApply.fits(entry(.t1, [.extraRestDay(day: d)], input: input), choice: 0, input: input) })
        let card = entry(.t1, [.extraRestDay(day: day)], input: input)
        let s = try XCTUnwrap(input.sessions.first { $0.day == day && $0.counts })
        try log(&book, s.id)
        let later = RuleBook.input(book: book, today: today)
        XCTAssertFalse(SuggestionApply.fits(card, choice: 0, input: later))
        let after = try RuleBook.apply([.extraRestDay(day: day)], to: later.sessions, input: later)
        XCTAssertFalse(after.first { $0.id == s.id }?.dropped ?? true, "the logged session stays as he logged it")
    }

    func testACardTakenTwiceMakesOneSetOfChanges() throws {
        var book = try book()
        let (s, card) = try dropCard(book)
        let input = RuleBook.input(book: book, today: today)
        let tap = try XCTUnwrap(parseDayKey(today)).addingTimeInterval(9 * 3600)
        let ids = try SuggestionApply.take(card.record.choices[0], input: input, to: &book, why: SuggestionApply.why(card.headline), now: tap)
        XCTAssertEqual(ids.count, 1)
        let again = RuleBook.input(book: book, today: today)
        XCTAssertFalse(SuggestionApply.fits(card, choice: 0, input: again))
        XCTAssertTrue(SuggestionApply.alreadyInPlan(card, headline: card.headline, book: book))
        XCTAssertEqual(book.changes.filter { $0.key == s.id }.count, 1)
        XCTAssertEqual(book.session(s.id)?.planned.description.hasPrefix("Instead of:"), true)
    }

    func testUndoAfterALaterEditIsRefusedWhole() throws {
        var book = try book()
        let (s, card) = try dropCard(book)
        let input = RuleBook.input(book: book, today: today)
        let ids = try SuggestionApply.take(card.record.choices[0], input: input, to: &book, why: "Suggestion: x", now: now)
        var d = try XCTUnwrap(book.draft(of: s.id))
        d.title = "His own rest"
        try book.change(s.id, to: d, now: now)
        let before = book
        XCTAssertThrowsError(try SuggestionApply.undo(ids, in: &book))
        XCTAssertEqual(book, before)
    }

    func testDroppedIsReadFromThePlanNotTheLog() throws {
        var book = try book()
        let (s, card) = try dropCard(book)
        let input = RuleBook.input(book: book, today: today)
        let ids = try SuggestionApply.take(card.record.choices[0], input: input, to: &book, why: "Suggestion: x", now: now)
        var taken = card.record; taken.answer = .took(0); taken.answeredOn = today
        XCTAssertEqual(RuleBook.input(book: book, today: today, log: [taken]).sessions.first { $0.id == s.id }?.dropped, true)
        // Undone in "Changes to the plan": the log still says taken, the plan says it is back.
        try book.undo(ids[0], now: now)
        let back = try XCTUnwrap(RuleBook.input(book: book, today: today, log: [taken]).sessions.first { $0.id == s.id })
        XCTAssertFalse(back.dropped)
        XCTAssertTrue(back.counts)
        XCTAssertTrue(SuggestionApply.liveIDs(ids, in: book).isEmpty, "the card's Undo then says it is no longer in the plan")
    }

    func testAnUndoneMoveLeavesTheMoveLog() throws {
        var book = try book()
        let input = RuleBook.input(book: book, today: today)
        let s = try XCTUnwrap(input.sessions.first { $0.counts && $0.status == .open && $0.day > today })
        let day = PlanView.addDays(s.day, 1)
        let ids = try SuggestionApply.take([.moveToDay(session: s.id, day: day)], input: input, to: &book, why: "Suggestion: x", now: now)
        XCTAssertNotNil(book.moves[s.id])
        try SuggestionApply.undo(ids, in: &book, now: now)
        XCTAssertNil(book.moves[s.id])
    }

    func testCapsFromThePlanAsTakenInPlusHisAddedRides() throws {
        var book = try book()
        let base = RuleBook.takenInCaps(book, today: today)
        XCTAssertFalse(base.isEmpty)
        // His own shorter edit does not move the cap.
        let s = try XCTUnwrap(RuleBook.input(book: book, today: today).sessions.first { $0.counts && $0.plannedMin >= 40 })
        var d = try XCTUnwrap(book.draft(of: s.id)); d.minutes = 10
        try book.change(s.id, to: d, now: now)
        XCTAssertEqual(RuleBook.takenInCaps(book, today: today), base)
        XCTAssertEqual(RuleBook.weekCaps(frozen: base, book: book, today: today), base)
        // Thursday rides added on purpose raise their weeks by their minutes.
        let ride = SessionDraft(dayKey: "2026-09-17", sport: "bike", title: "Easy ride", minutes: 45, intensity: "Z1–Z2",
                                purpose: ThursdayRides.purpose)
        try book.add(ride, why: ThursdayRides.why, now: now)
        let week = RuleBook.input(book: book, today: today).week(of: ride.dayKey)
        let caps = RuleBook.weekCaps(frozen: base, book: book, today: today)
        XCTAssertEqual(caps[week], (base[week] ?? 0) + Int(ride.minutes ?? 0))
        XCTAssertEqual(RuleBook.takenInCaps(book, today: today), base, "the frozen part never moves")
        // A suggestion's own copy does not raise anything.
        try book.add(SessionDraft(dayKey: ride.dayKey, sport: "run", title: "Copy", minutes: 30), why: "Suggestion: copy", now: now)
        XCTAssertEqual(RuleBook.weekCaps(frozen: base, book: book, today: today), caps)
    }

    func testADamagedBlockMeansNothingIsReadOrWritten() throws {
        var keep = SuggestionKeep()
        keep.settings.keepBackToBackQuality = false
        keep.health.stopSignSince = today
        let good = try keep.encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        // A missing part is an older file: its default.
        json["settings"] = nil
        XCTAssertNoThrow(try SuggestionKeep.decoded(try JSONSerialization.data(withJSONObject: json)))
        // A part that is there and cannot be read is damage: the whole file is unreadable.
        for (key, bad) in [("settings", ["keepBackToBackQuality": "perhaps"]), ("health", ["stopSignSince": 7]), ("on", "yes")] as [(String, Any)] {
            var broken = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
            broken[key] = bad
            XCTAssertThrowsError(try SuggestionKeep.decoded(try JSONSerialization.data(withJSONObject: broken)), key)
        }
    }

    // MARK: the coach's review

    func testNoCardWhilePausedAndPausingPutsTheOpenCardAway() throws {
        var f = Fixture.standard()
        f.allDone(before: Fixture.day(2, 2))
        f.feel.set(.tired, on: Fixture.day(2, 1)); f.feel.set(.bad, on: Fixture.day(2, 2))
        let card = try XCTUnwrap(f.suggest(Fixture.day(2, 2)))
        var keep = SuggestionKeep()
        keep.add(SuggestionEntry(card), today: Fixture.day(2, 2))
        XCTAssertEqual(keep.putAwayOpen(.paused, on: Fixture.day(2, 2)), [card.record.id])
        XCTAssertNil(keep.openEntry(on: Fixture.day(2, 2)))
        XCTAssertEqual(keep.answerWords(keep.entries[0], today: Fixture.day(2, 2)), "Put away \u{2014} you paused")
        f.health.stopSignSince = Fixture.day(2, 2)
        XCTAssertNil(f.suggest(Fixture.day(2, 2)))
        XCTAssertNil(f.suggest(Fixture.day(2, 3)))
        f.health = RBHealthTaps(illSince: Fixture.day(2, 2), illness: .belowNeck)
        XCTAssertNil(f.suggest(Fixture.day(2, 3)), "no card in the rest step")
    }

    func testTheIllnessCardMayFollowAnotherCardTheSameDay() throws {
        var keep = SuggestionKeep()
        let day = Fixture.day(2, 2)
        func record(_ t: RBTrigger) -> SuggestionRecord {
            SuggestionRecord(day: day, trigger: t, step: 0, key: t.rawValue, headline: "h", why: "w", choices: [[]], tried: [],
                             sessions: [], closesOn: day)
        }
        keep.add(SuggestionEntry(record: record(.t1)), today: day)
        XCTAssertFalse(keep.mayShowNew(on: day, trigger: .section5), "not while the other is open")
        keep.answer(record(.t1).id, .keptPlan, on: day)
        XCTAssertFalse(keep.mayShowNew(on: day))
        XCTAssertTrue(keep.add(SuggestionEntry(record: record(.section5)), today: day))
    }

    func testOnlyCalfAchillesOrKneeMarkTheDay() {
        var keep = SuggestionKeep()
        keep.hurts("other", session: "a", on: "2030-01-01")
        XCTAssertTrue(keep.hurtDays.isEmpty)
        XCTAssertEqual(keep.hurtAsked["a"], "other")
        keep.hurts("knee", session: "b", on: "2030-01-02")
        XCTAssertEqual(keep.hurtDays, ["2030-01-02"])
    }

    func testABroughtForwardEasyWeekIsQuiet() throws {
        var f = Fixture.standard()
        let from = Fixture.day(2, 1)
        f.allDone(before: Fixture.day(2, 3))
        var r = SuggestionRecord(day: from, trigger: .t1, step: 3, key: "x", headline: "h", why: "w",
                                 choices: [[.bringEasyWeekForward(from: from, easyWeek: 4)]], tried: [], sessions: [], closesOn: from)
        r.answer = .took(0); r.answeredOn = from
        f.log = [r]
        f.feel.set(.tired, on: Fixture.day(2, 2)); f.feel.set(.bad, on: Fixture.day(2, 3))
        let input = f.input(Fixture.day(2, 3))
        XCTAssertTrue(input.easyStretch(Fixture.day(2, 3)))
        XCTAssertNil(RuleBook.t1Tired(input))
        XCTAssertNil(RuleBook.t4LongTooFar(input))
        f.log = []
        XCTAssertNotNil(RuleBook.t1Tired(f.input(Fixture.day(2, 3))), "without it, the same mornings do speak")
    }

    func testReturnWeekTwoDropsTestsInsteadOfShorteningThem() throws {
        var f = Fixture.standard()
        f.health = RBHealthTaps(illSince: Fixture.day(2, 0), illness: .belowNeck, symptomFreeSince: Fixture.day(3, 0))
        let day = Fixture.day(4, 5)
        XCTAssertEqual(RuleBook.ladderStep(f.input(day)).step, .week2)
        let moves = RuleBook.ladderWeek2(f.input(day), days: RuleBook.days(from: day, count: 7))
        let tests = f.sessions.filter { RuleBook.labels($0).test }.map(\.id)
        let touched = moves.filter { !Set($0.sessionIDs).isDisjoint(with: tests) }
        XCTAssertFalse(touched.isEmpty)
        XCTAssertTrue(touched.allSatisfy { if case .drop = $0 { return true } else { return false } })
    }
}
