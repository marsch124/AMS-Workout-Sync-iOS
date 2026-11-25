import Foundation

/*
 * Claude's pick wired into the suggestion card: the pure part.
 *
 * The rule book makes the card and shows its own pick at once. Later, if
 * Claude is on and a valid answer arrives while the card is still open and
 * exactly as it was asked about, the chosen item of the SAME menu takes the
 * card's first place and Claude's reason replaces the rule book's. Anything
 * else — no answer, a pick outside the menu, "keep the plan" (the card has
 * its own Keep button), a changed or answered card — leaves the card alone.
 */

extension SuggestionEntry {
    /* The menu Claude is shown: the card's own pick, then its other choices. */
    public var claudeMenuCount: Int { record.choices.count }

    /*
     * The card with Claude's pick as its own, or nil when the answer may not be used.
     * `menu` is the menu exactly as it was sent (pick 1 = menu[0]); the chosen item is
     * found in this card by its moves, never by its place, and must be there once.
     * The card's sessions and closing day become those of the chosen move (from
     * `input`, the plan now), so "Take it", the stale check and the expiry all
     * belong to what the card shows. Words and moves of the menu never change.
     */
    public func applyingClaude(_ answer: ClaudeAnswer?, menu: [[Move]], input: RuleBookInput) -> SuggestionEntry? {
        guard let answer, !isReview, record.answer == nil, !claudePicked,
              menu.count == record.choices.count,
              answer.pick >= 1, answer.pick <= menu.count,
              ClaudePick.accepts(answer, menuCount: menu.count) else { return nil }
        let picked = menu[answer.pick - 1]
        let found = record.choices.indices.filter { record.choices[$0] == picked }
        guard !picked.isEmpty, found.count == 1, let chosen = found.first else { return nil }
        let headlines = [record.headline] + otherHeadlines
        guard headlines.count == record.choices.count, before.count == record.choices.count else { return nil }
        let changed = RuleBook.changedSessions(picked, input: input)
        guard !changed.isEmpty else { return nil }
        let closes = changed.map(\.day).filter { $0 >= input.today }.min() ?? input.today
        let order = [chosen] + record.choices.indices.filter { $0 != chosen }
        let r = SuggestionRecord(day: record.day, trigger: record.trigger, step: record.step, key: record.key,
                                 headline: headlines[chosen], why: answer.why,
                                 choices: order.map { record.choices[$0] }, tried: record.tried,
                                 sessions: changed.map(\.id), closesOn: closes)
        var e = self
        e.record = r
        e.otherHeadlines = order.dropFirst().map { headlines[$0] }
        e.before = order.map { before[$0] }
        e.claudePicked = true
        return e
    }
}

extension SuggestionKeep {
    /*
     * The card Claude may be asked about: open today and made today, a real card,
     * not asked before, and never while paused, ill or on the way back (the stop
     * sign and illness cards are his own taps, never Claude's to word).
     */
    public func askable(on today: String, ladder: RBLadder) -> SuggestionEntry? {
        guard ladder == .none, let e = openEntry(on: today), e.record.day == today, !e.isReview, !e.claudeAsked,
              e.record.trigger != .section5, !e.record.choices.isEmpty else { return nil }
        return e
    }

    /* Marks the card as asked, once, so a second check or a restart never asks again. */
    public mutating func markAsked(_ id: String) {
        guard let i = entries.lastIndex(where: { $0.id == id }) else { return }
        entries[i].claudeAsked = true
    }

    /*
     * An answer came back for `asked`. It is used only the same day, when the card
     * is still the one shown, unanswered and unchanged (same words, moves and
     * snapshot), still fits the plan as it is now, and fits it with Claude's pick too.
     */
    @discardableResult
    public mutating func applyClaude(_ answer: ClaudeAnswer?, to asked: SuggestionEntry, on today: String,
                                     input: RuleBookInput) -> Bool {
        guard asked.record.day == today, input.today == today,
              let i = entries.lastIndex(where: { $0.id == asked.id }),
              openEntry(on: today)?.id == asked.id,
              entries[i].record.isOpen(on: today),
              entries[i].record == asked.record, entries[i].before == asked.before,
              entries[i].changeIDs.isEmpty, !entries[i].undone,
              SuggestionApply.fits(entries[i], choice: 0, input: input),
              let swapped = entries[i].applyingClaude(answer, menu: asked.record.choices, input: input),
              SuggestionApply.fits(swapped, choice: 0, input: input) else { return false }
        entries[i] = swapped
        return true
    }
}

extension ClaudeContext {
    /* What Claude is told besides the menu: 14 past days and 7 coming ones, from the engine's own view of the plan. */
    public static func make(from input: RuleBookInput) -> ClaudeContext {
        let today = input.today
        var past: [ClaudeDay] = []
        for back in stride(from: 14, through: 1, by: -1) {
            let day = PlanView.addDays(today, -back)
            let of = input.sessions.filter { $0.day == day && $0.sport != .rest }
            let extras = input.extras.filter { $0.day == day }
            let planned = of.reduce(0) { $0 + $1.plannedMin }
            let done = of.filter { $0.status == .done }.reduce(0) { $0 + ($1.actualMin ?? $1.plannedMin) }
            let rpes = of.compactMap(\.rpe).filter { $0 > 0 }
            let extraWords = extras.map { "\($0.activity) \($0.minutes) min" }.joined(separator: ", ")
            guard planned > 0 || done > 0 || !extras.isEmpty || input.feel.answer(on: day) != nil else { continue }
            past.append(ClaudeDay(day: day, plannedMinutes: planned, doneMinutes: done,
                                  hard: rpes.max().map { "\($0) of 10" },
                                  morning: input.feel.answer(on: day)?.rawValue,
                                  extras: extraWords.isEmpty ? nil : extraWords))
        }
        var ahead: [ClaudeAheadDay] = []
        for fwd in 0..<7 {
            let day = PlanView.addDays(today, fwd)
            let of = input.sessions.filter { $0.day == day && $0.sport != .rest && !$0.dropped && $0.status != .missed }
            let line = of.isEmpty ? "rest" : of.map { "\($0.sport.rawValue) \($0.plannedMin) min\($0.intensity.isEmpty ? "" : " " + $0.intensity)" }.joined(separator: "; ")
            ahead.append(ClaudeAheadDay(day: day, sessions: line))
        }
        return ClaudeContext(today: today, past: past, ahead: ahead)
    }
}
