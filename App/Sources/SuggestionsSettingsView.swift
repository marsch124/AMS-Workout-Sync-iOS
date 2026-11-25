import SwiftUI
import WorkoutCore

/*
 * Settings › Suggestions: the one switch, his five answers as plain
 * switches, and "What was suggested" — every card, newest first, with what
 * he answered. The switches are held on the page until Save; Cancel leaves
 * everything as it was.
 */
struct SuggestionsSettingsView: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    @Environment(\.dismiss) private var dismiss
    @State private var on: Bool
    @State private var settings: RuleBookSettings

    init() {
        let keep = SuggestionKeeper.shared.keep
        _on = State(initialValue: keep.isOn)
        _settings = State(initialValue: keep.settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !keeper.readable {
                    Text("The list of suggestions on this \(Device.word) could not be read, so none are made. Nothing in it was changed.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("suggest-unreadable")
                }
                switchRow("Suggest changes to my plan",
                          "The app suggests, you decide: nothing in your plan changes until you tap Take it.",
                          $on, id: "suggest-on")

                SectionHeading(text: "Your answers")
                switchRow("Keep hard bike and hard run on days in a row",
                          settings.keepBackToBackQuality ? "As your plan has them."
                              : "The app may suggest the run quality on Thursday instead.",
                          $settings.keepBackToBackQuality, id: "suggest-q1")
                switchRow("Ask \u{201C}Something hurts?\u{201D} after a session",
                          "Calf, Achilles or knee: the app may suggest a row or an easy spin instead of the Thursday run.",
                          $settings.somethingHurtsTap, id: "suggest-q2")
                switchRow("An easy week brought forward leaves the later one easy too",
                          settings.laterEasyWeekStaysEasy ? "Both weeks stay easy." : "The later easy week becomes a normal week.",
                          $settings.laterEasyWeekStaysEasy, id: "suggest-q3")
                switchRow("Long rides and runs grow a step at a time",
                          settings.longSessionsGrowSlowly ? "A step is about a tenth of your longest one in the last 3 weeks."
                              : "The plan\u{2019}s own numbers stand.",
                          $settings.longSessionsGrowSlowly, id: "suggest-q4")
                switchRow("Resting pulse is shown only",
                          settings.restingPulseShownOnly ? "It never starts a suggestion."
                              : "It would count only together with how you feel; the app does not count it yet.",
                          $settings.restingPulseShownOnly, id: "suggest-q5")

                SectionHeading(text: "What was suggested")
                let entries = keeper.keep.newestFirst
                if entries.isEmpty {
                    Text("Nothing yet.").font(.callout).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("suggest-log-empty")
                }
                ForEach(entries) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Dates.short(e.record.day)).font(.caption).foregroundStyle(Theme.secondary)
                        Text(e.headline).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(e.why).font(.footnote).foregroundStyle(Theme.secondary)
                        Text(keeper.keep.answerWords(e, today: keeper.today))
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("suggest-log-row")
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("suggest-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    keeper.set(on: on, settings: settings)
                    dismiss()
                }
                .disabled(!keeper.readable)
                .accessibilityIdentifier("suggest-save")
            }
        }
    }

    private func switchRow(_ title: String, _ sub: String, _ value: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Text(sub).font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .tint(Theme.plan)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityIdentifier(id)
    }
}
