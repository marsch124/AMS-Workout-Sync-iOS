import SwiftUI
import WorkoutCore

/*
 * The stop sign and the illness taps (spec section 5). The words of the stop
 * sign and of each illness step are fixed and come from the rule book as
 * they are — this page adds no advice of its own and never reads a watch
 * number. The heading alone is in the app's red.
 *
 * The pause starts only with his own tap, so opening the page to say "I'm
 * ill" never pauses anything by accident; it ends only with "A doctor has
 * seen me".
 */
struct StopSignView: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    @Environment(\.dismiss) private var dismiss
    @State private var askingIll = false
    @State private var freeSince = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    stopSign
                    illness
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
        }
    }

    private var stopSign: some View {
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
            } else {
                Button("Pause suggestions") { keeper.pause() }
                    .settingsButton(tint: Theme.today, filled: true)
                    .accessibilityIdentifier("stop-pause")
                    .padding(.top, 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    @ViewBuilder
    private var illness: some View {
        let state = keeper.ladder
        let health = keeper.keep.health
        VStack(alignment: .leading, spacing: 10) {
            if state.step != .none && state.step != .paused {
                Text(state.text)
                    .font(.subheadline).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stop-step")
            }

            // A new illness can be told whenever none is running.
            if health.illSince == nil || state.step == .none || state.step == .back {
                if askingIll {
                    Text(RuleBookWords.illQuestion).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    FlowRow(spacing: 6) {
                        Button(RuleBookWords.illYes) { keeper.ill(.belowNeck); askingIll = false }
                            .settingsButton(tint: Theme.today)
                            .accessibilityIdentifier("stop-fever")
                        Button(RuleBookWords.illNo) { keeper.ill(.aboveNeck); askingIll = false }
                            .settingsButton(tint: Theme.today)
                            .accessibilityIdentifier("stop-neck")
                    }
                } else {
                    Button("I\u{2019}m ill") { askingIll = true }
                        .settingsButton(tint: Theme.today)
                        .accessibilityIdentifier("stop-ill")
                }
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .onAppear { freeSince = parseDayKey(keeper.today) ?? Date() }
    }
}
