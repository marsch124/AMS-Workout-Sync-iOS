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

    /* The card with Claude's pick as its own, or nil when the answer may not be used. Nothing else about it changes. */
    public func applyingClaude(_ answer: ClaudeAnswer?) -> SuggestionEntry? {
        guard let answer, !isReview, record.answer == nil, !claudePicked,
              answer.pick >= 1, answer.pick <= claudeMenuCount,
              ClaudePick.accepts(answer, menuCount: claudeMenuCount) else { return nil }
        let chosen = answer.pick - 1
        let headlines = [record.headline] + otherHeadlines
        guard headlines.count == record.choices.count else { return nil }
        let order = [chosen] + record.choices.indices.filter { $0 != chosen }
        var newBefore = before
        if before.count == record.choices.count { newBefore = order.map { before[$0] } }
        let r = SuggestionRecord(day: record.day, trigger: record.trigger, step: record.step, key: record.key,
                                 headline: headlines[chosen], why: answer.why,
                                 choices: order.map { record.choices[$0] }, tried: record.tried,
                                 sessions: record.sessions, closesOn: record.closesOn)
        var e = self
        e.record = r
        e.otherHeadlines = order.dropFirst().map { headlines[$0] }
        e.before = newBefore
        e.claudePicked = true
        return e
    }
}

extension SuggestionKeep {
    /* The card Claude may be asked about: open today, a real card, not asked before. */
    public func askable(on today: String) -> SuggestionEntry? {
        guard let e = openEntry(on: today), !e.isReview, !e.claudeAsked, !e.record.choices.isEmpty else { return nil }
        return e
    }

    /* Marks the card as asked, once, so a second check or a restart never asks again. */
    public mutating func markAsked(_ id: String) {
        guard let i = entries.lastIndex(where: { $0.id == id }) else { return }
        entries[i].claudeAsked = true
    }

    /*
     * An answer came back for `asked`. It is used only when the card is still the one
     * open today, unanswered and unchanged (same words, moves and snapshot).
     */
    @discardableResult
    public mutating func applyClaude(_ answer: ClaudeAnswer?, to asked: SuggestionEntry, on today: String) -> Bool {
        guard let i = entries.lastIndex(where: { $0.id == asked.id }),
              entries[i].record.isOpen(on: today),
              entries[i].record == asked.record, entries[i].before == asked.before,
              entries[i].changeIDs.isEmpty,
              let swapped = entries[i].applyingClaude(answer) else { return false }
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
