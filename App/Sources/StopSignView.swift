import SwiftUI
import WorkoutCore

/*
 * The stop sign (spec section 5). Its words are fixed and come from the rule
 * book as they are — this page adds no advice of its own and never reads a
 * watch number. The heading alone is in the app's red.
 *
 * The words say the app pauses all suggestions, so opening the page pauses
 * at once (and puts away a card that was open). "Opened by mistake" takes it
 * back the same day; after that only "A doctor has seen me" ends the pause.
 *
 * The illness questions have a page of their own (IllnessView): a cold never
 * has to read "Stop training now".
 */
struct StopSignView: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !keeper.notesReadable { UnreadableNotesLine() }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(RuleBookWords.stopSignTitle)
                            .font(.title3.weight(.bold)).foregroundStyle(Theme.danger)
                            .accessibilityIdentifier("stop-title")
                        Text(RuleBookWords.stopSignSigns).font(.body).foregroundStyle(Theme.text)
                        Text(RuleBookWords.stopSignDoctor).font(.body).foregroundStyle(Theme.text)
                        Text(RuleBookWords.stopSignPause).font(.subheadline).foregroundStyle(Theme.secondary)
                        Text(RuleBookWords.stopSignFooter).font(.caption).italic().foregroundStyle(Theme.secondary)
                        if keeper.paused {
                            HStack(spacing: 8) {
                                Text(RuleBookWords.pausedLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    .accessibilityIdentifier("stop-paused")
                                Button(RuleBookWords.doctorSeenButton) { keeper.doctorSeen() }
                                    .settingsButton(tint: Theme.today, filled: true)
                                    .accessibilityIdentifier("stop-doctor")
                            }
                            .padding(.top, 2)
                        }
                        if keeper.mayUndoStopSign {
                            Button("Opened by mistake") {
                                keeper.stopSignByMistake()
                                dismiss()
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("stop-mistake")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Stop sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("stop-close")
                }
            }
            .onAppear { keeper.openedStopSign() }
        }
    }
}

/* "I'm ill": only the illness questions, and the steps back. */
struct IllnessView: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    @Environment(\.dismiss) private var dismiss
    @State private var freeSince = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !keeper.notesReadable { UnreadableNotesLine() }
                    content
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("I\u{2019}m ill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("ill-close")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let state = keeper.ladder
        let health = keeper.keep.health
        VStack(alignment: .leading, spacing: 10) {
            if state.step != .none && state.step != .paused {
                Text(state.text)
                    .font(.subheadline).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stop-step")
            }

            // A new illness, or a relapse, can be told whenever he is not already resting or paused.
            if state.step != .rest && state.step != .paused && !keeper.mayUndoIll {
                Text(RuleBookWords.illQuestion).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                FlowRow(spacing: 6) {
                    Button(RuleBookWords.illYes) { keeper.ill(.belowNeck) }
                        .settingsButton(tint: Theme.today)
                        .accessibilityIdentifier("stop-fever")
                    Button(RuleBookWords.illNo) { keeper.ill(.aboveNeck) }
                        .settingsButton(tint: Theme.today)
                        .accessibilityIdentifier("stop-neck")
                }
                .disabled(!keeper.notesReadable)
            }

            // Still ill: the day the symptoms went.
            if let since = health.illSince, health.symptomFreeSince == nil, state.step == .rest || state.step == .cold {
                HStack(spacing: 8) {
                    Text("Symptom-free since").font(.subheadline).foregroundStyle(Theme.text)
                    DatePicker("Symptom-free since", selection: $freeSince,
                               in: (parseDayKey(since) ?? Date.distantPast)...(parseDayKey(keeper.today) ?? Date()),
                               displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
                    Button("Save") { if let day = dayKey(freeSince) { keeper.symptomFree(since: day) } }
                        .settingsButton(tint: Theme.today, filled: true)
                        .accessibilityIdentifier("stop-free")
                }
            }

            if state.step == .week1 {
                Button(RuleBookWords.stillNotRightButton) { keeper.stillNotRight() }
                    .settingsButton(tint: Theme.today)
                    .disabled(health.stillNotRight.contains(keeper.today))
                    .accessibilityIdentifier("stop-not-right")
            }

            if keeper.mayUndoIll {
                Button("I tapped this by mistake") { keeper.illByMistake() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ill-mistake")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .onAppear { freeSince = parseDayKey(keeper.today) ?? Date() }
    }
}

/* The suggestions' own notes cannot be read: nothing is changed, and they rest. */
struct UnreadableNotesLine: View {
    var body: some View {
        Text(SuggestionKeeper.unreadableWords)
            .font(.footnote).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("suggest-unreadable")
    }
}
