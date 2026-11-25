import SwiftUI
import WorkoutCore

/*
 * The suggestion on Today, directly under the morning question, in the
 * plain voice: one change line, one reason line, and two equal buttons —
 * "Take it" and "Keep my plan" weigh exactly the same, both outlined in the
 * plan's blue (blue means changing the plan, everywhere), neither filled.
 * "Other choice" shows at most two more that also passed every limit.
 *
 * After "Take it" the card's place says "Changed — Undo" until the day ends.
 */
struct SuggestionArea: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared

    var body: some View {
        if keeper.ladderStatus != nil || keeper.card != nil || keeper.changed != nil || keeper.todaysNotice != nil {
            VStack(alignment: .leading, spacing: 10) {
                LadderLine()
                if let entry = keeper.card {
                    SuggestionCardView(entry: entry)
                } else if let entry = keeper.changed {
                    ChangedLine(entry: entry)
                }
                if let notice = keeper.todaysNotice {
                    Text(notice.text)
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(notice.id)
                }
            }
            .onAppear { keeper.todayAppeared() }
        } else {
            // Nothing to show: no room taken either (the page spaces its rows 14 apart).
            Color.clear.frame(height: 0).padding(.top, -14)
                .accessibilityHidden(true)
                .onAppear { keeper.todayAppeared() }
        }
    }
}

struct SuggestionCardView: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    let entry: SuggestionEntry
    @State private var showingOthers = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.headline)
                .font(.headline).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("suggestion-headline")
            Text(entry.why)
                .font(.subheadline).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("suggestion-why")
            if entry.claudePicked {
                Text("Picked by Claude from the rule book\u{2019}s choices")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("suggestion-claude")
            }

            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                if !entry.isReview {
                    EqualButton(title: RuleBookWords.takeIt, id: "suggestion-take") { keeper.take(0) }
                }
                EqualButton(title: RuleBookWords.keepMyPlan, id: "suggestion-keep") { keeper.keepPlan() }
            }
            .padding(.top, 2)

            if !entry.isReview && !entry.otherHeadlines.isEmpty {
                if showingOthers || debugOthers {
                    ForEach(Array(entry.otherHeadlines.prefix(2).enumerated()), id: \.offset) { i, words in
                        Button { keeper.take(i + 1) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(words).font(.subheadline).foregroundStyle(Theme.text)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                                Text(RuleBookWords.takeIt).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.plan)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("suggestion-other-\(i + 1)")
                    }
                } else {
                    Button(RuleBookWords.otherChoice) {
                        keeper.touched(entry.id)
                        withAnimation(.easeInOut(duration: 0.15)) { showingOthers = true }
                    }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.plan)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("suggestion-other")
                }
            }

            Text(RuleBookWords.footer)
                .font(.caption2).foregroundStyle(Theme.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        // Any touch on the card: Claude's late answer may no longer change its words.
        .simultaneousGesture(TapGesture().onEnded { keeper.touched(entry.id) })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suggestion-card")
    }

    private var debugOthers: Bool {
        #if DEBUG
        return keeper.debugShowsOthers
        #else
        return false
        #endif
    }
}

/* One of the two equal answers: same size, same outline, neither filled. */
private struct EqualButton: View {
    let title: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.plan)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.plan, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/* "Changed — Undo", where the card was, until the end of the day it was taken. */
struct ChangedLine: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    let entry: SuggestionEntry

    private var words: [String] { RuleBookWords.changedUndo.components(separatedBy: " — ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text((words.first ?? "Changed") + " —")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("suggestion-changed")
                Button(words.last ?? "Undo") { keeper.undo() }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("suggestion-undo")
                Spacer(minLength: 0)
            }
            Text(keeper.headline(entry, entry.takenIndex ?? 0))
                .font(.footnote).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

/* While a pause or an illness step is on: one grey line on Today ("Suggestions are paused — Stop sign"). */
struct LadderLine: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared

    var body: some View {
        if let line = keeper.ladderStatus {
            Text(line)
                .font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ladder-line")
        }
    }

    static func label(_ step: RBLadder) -> String? {
        switch step {
        case .paused: return RuleBookWords.pausedLabel
        case .rest: return RuleBookWords.restLabel
        default: return nil
        }
    }
}

/*
 * One small calm pill, "Not well?", on Today and on every session page. It
 * opens a plate with the two ways in: "Stop sign" (opening it pauses
 * suggestions) and "I'm ill", which opens only the illness questions — a cold
 * never has to read the stop sign's words. The plate and both pages are one
 * sheet whose content changes, so nothing is dismissed and presented twice.
 */
struct NotWellPill: View {
    enum Page: String, Identifiable {
        case plate, stop, ill
        var id: String { rawValue }
    }
    @State private var page: Page?

    var body: some View {
        Button("Not well?") { page = .plate }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered).controlSize(.mini).tint(Theme.today)
            .accessibilityIdentifier("not-well")
            .sheet(item: $page) { p in
                switch p {
                case .plate: NotWellPlate(pick: { page = $0 }).presentationDetents([.medium])
                case .stop: StopSignView()
                case .ill: IllnessView()
                }
            }
    }
}

/* The plate: two rows, each a button with one line under its words. */
struct NotWellPlate: View {
    let pick: (NotWellPill.Page) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                row("Stop sign",
                    "Chest pain, unusual breathlessness, dizziness, a racing or uneven heartbeat. Opens the stop sign and pauses suggestions.",
                    id: "stop-sign", page: .stop)
                row("I\u{2019}m ill",
                    "A cold, fever or stomach bug. Opens the illness questions and the steps back.",
                    id: "ill-button", page: .ill)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Not well?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("not-well-close")
                }
            }
        }
    }

    private func row(_ title: String, _ line: String, id: String, page: NotWellPill.Page) -> some View {
        Button { pick(page) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Text(line).font(.subheadline).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/* On a session page: what the session shows while paused or resting, then the pill. */
struct StopSignButton: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    var showsState = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if showsState, let label = LadderLine.label(keeper.ladder.step) {
                Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("session-ladder")
            }
            NotWellPill()
        }
    }
}

/* "Something hurts?" — offered once, under "How hard was it?". */
struct HurtsAsk: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    let workout: Workout

    static let places: [(id: String, word: String)] = [("calf", "Calf"), ("achilles", "Achilles"), ("knee", "Knee"), ("other", "Other")]

    var body: some View {
        if keeper.asksHurts(workout) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Something hurts?")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("hurts-ask")
                FlowRow(spacing: 6) {
                    ForEach(Self.places, id: \.id) { p in
                        Button(p.word) { keeper.hurts(p.id, session: workout.key) }
                            .settingsButton(tint: Theme.today)
                            .accessibilityIdentifier("hurts-\(p.id)")
                    }
                    Button("Nothing hurts") { keeper.hurts(nil, session: workout.key) }
                        .settingsButton(tint: Theme.today)
                        .accessibilityIdentifier("hurts-none")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
    }
}

/* The one calm grey line under his own change. Never a block, never red, never a question. */
struct OwnEditNote: View {
    let text: String?
    var body: some View {
        if let text {
            Text(text)
                .font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("own-edit-note")
        }
    }
}
