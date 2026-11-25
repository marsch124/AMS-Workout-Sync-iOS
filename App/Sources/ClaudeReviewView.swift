import SwiftUI
import WorkoutCore

/* DEBUG picture switches for the two Claude pages (AMSWS_FAKE_CLAUDE goes with them: no network, no key). */
enum ClaudeDebug {
    /* AMSWS_CLAUDE_REVIEW=1: the card with an invented answer; =write: the card before it, with its button. */
    static var review: String? {
        #if DEBUG
        guard ClaudeKey.isFake else { return nil }
        return ProcessInfo.processInfo.environment["AMSWS_CLAUDE_REVIEW"]
        #else
        return nil
        #endif
    }

    /* AMSWS_CLAUDE_ASK=1: the page with one invented question and answer; =empty: the page with nothing asked yet. */
    static var ask: String? {
        #if DEBUG
        guard ClaudeKey.isFake else { return nil }
        return ProcessInfo.processInfo.environment["AMSWS_CLAUDE_ASK"]
        #else
        return nil
        #endif
    }

    static var forced: Bool { review != nil || ask != nil }
}

extension ClaudeClient {
    /* Claude is on (with a key), or a picture switch stands in for it. */
    var canWrite: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_ASK_BUTTON"] != nil { return true }
        #endif
        return isOn || ClaudeDebug.forced
    }
}

/* The reviews kept on this device, one per week. */
@MainActor
final class ClaudeReviewKeeper: ObservableObject {
    static let shared = ClaudeReviewKeeper()

    @Published private(set) var saved: [ClaudeSavedReview]
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let storing: ClaudeReviewStoring
    /* A picture shows an invented answer and never keeps it. */
    private var inMemory: Bool { ClaudeDebug.review != nil }

    init(storing: ClaudeReviewStoring = UserDefaultsReviewStore()) {
        self.storing = storing
        saved = storing.load()
    }

    func review(for week: String) -> ClaudeSavedReview? {
        if ClaudeDebug.review == "1" {
            return saved.first { $0.week == week } ?? ClaudeSavedReview(week: week, writtenAt: Date(), answer: ClaudeReview.invented)
        }
        return saved.first { $0.week == week }
    }

    func write(week: String, input: RuleBookInput?) async {
        guard !busy else { return }
        let client = ClaudeClient.shared
        let facts = input.map { ClaudeReview.userText(from: $0, monday: week) } ?? ""
        guard !facts.isEmpty || ClaudeKey.isFake else {
            message = "The plan is not ready yet. Try again in a moment."
            return
        }
        busy = true
        message = nil
        let result = await client.run(kind: "review", label: "Wrote the week review",
                                      body: ClaudeReview.body(system: ClaudeReview.system, user: facts),
                                      fake: ClaudeReview.invented, read: { ClaudeReview.read($0, facts: facts) })
        busy = false
        switch result {
        case .answer(let answer):
            let item = ClaudeSavedReview(week: week, writtenAt: Date(), answer: answer)
            saved = saved.adding(item)
            if !inMemory { storing.save(saved) }
        case .notPassed:
            message = ClaudeReview.didNotPass
        case .none:
            // A refusal only he can set right is said by the card's own calm line; a hiccup is said here.
            message = client.trouble == nil ? ClaudeReview.nothingCame : nil
        }
    }
}

/*
 * "Your week with Claude" on Today, from Sunday 17:00 until Monday night.
 * Off and invisible without a saved key and the switch on. The head is filled
 * with Today's green and holds the one question; the five lines stand under it.
 */
struct ClaudeReviewCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var client = ClaudeClient.shared
    @ObservedObject private var keeper = ClaudeReviewKeeper.shared

    var body: some View {
        let week = ClaudeReview.week(today: store.today)
        let shown = keeper.review(for: week)
        if client.canWrite, ClaudeDebug.review != nil || (ClaudeReview.inWindow(now: Date()) && store.book != nil) {
            card(week: week, review: shown)
        }
    }

    @ViewBuilder
    private func card(week: String, review: ClaudeSavedReview?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR WEEK WITH CLAUDE").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                if let review {
                    Text(review.answer.question).font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claude-review-question")
                } else {
                    Text("Five short lines about the week, and one question to think about.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.mainButton)

            VStack(alignment: .leading, spacing: 8) {
                if let review {
                    ForEach(Array(review.answer.lines.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.subheadline).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("claude-review-line-\(i + 1)")
                    }
                    Text("Written by Claude from this week\u{2019}s numbers. Kept under Settings \u{2192} Claude.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                } else {
                    Text(ClaudeReview.sentWords + " " + ClaudeReview.costWords)
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claude-review-sent")
                    if let trouble = client.trouble {
                        Text(trouble.restLine).font(.footnote).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("claude-review-trouble")
                    } else {
                        Button {
                            Task { await keeper.write(week: week, input: SuggestionKeeper.shared.input(.evening)) }
                        } label: {
                            Text(keeper.busy ? "Writing\u{2026}" : "Write my week").font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                        .disabled(keeper.busy)
                        .accessibilityIdentifier("claude-review-write")
                    }
                    if let message = keeper.message {
                        Text(message).font(.footnote).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("claude-review-message")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude-review-card")
    }
}

/* Settings → Claude, under the log: every week Claude has written about, newest first. */
struct ClaudeReviewList: View {
    @ObservedObject private var keeper = ClaudeReviewKeeper.shared

    var body: some View {
        SectionHeading(text: "Your weeks with Claude")
        let all = ClaudeDebug.review != nil && keeper.saved.isEmpty
            ? [ClaudeSavedReview(week: "2026-09-14", writtenAt: Date(), answer: ClaudeReview.invented)] : keeper.saved
        if all.isEmpty {
            Text("Nothing yet. On Sunday evening Today offers to write your week.")
                .font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 2)
        } else {
            ForEach(all) { r in
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WEEK OF " + Dates.short(r.week).uppercased()).font(.caption.weight(.bold)).tracking(0.8)
                            .foregroundStyle(Theme.today)
                        ForEach(Array(r.answer.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote).foregroundStyle(Theme.text)
                        }
                        Text(r.answer.question).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("claude-review-saved-row")
            }
        }
    }
}
