import SwiftUI
import WorkoutCore

/* The row in Settings: one line, leads to the page. */
struct ClaudeSettingsEntry: View {
    @ObservedObject private var client = ClaudeClient.shared
    var body: some View {
        NavigationLink { ClaudeSettingsView() } label: {
            SettingsRow(title: "Claude",
                        sub: client.isOn ? "On · \(client.monthLine)"
                                         : "Off · lets Claude choose among the suggestions, and shares your plan as text",
                        chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-claude")
    }
}

/*
 * Claude built in. The rule book decides whether a suggestion appears and
 * writes its menu; Claude may only pick one item of it and word the reason.
 * Off until he has typed his own key. Nothing here ever changes the plan.
 * Below it: the plan as plain text for the Claude app, which works with no
 * key and sends nothing anywhere by itself.
 */
struct ClaudeSettingsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var client = ClaudeClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var problem: String?
    @State private var saving = false
    @State private var confirmRemove = false
    @State private var payload: SharePayload?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Claude").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 8)
                    .accessibilityIdentifier("claude-title")
                explanation
                if client.keySaved { keySaved } else { keyField }
                switchRow
                month
                answered
                SectionHeading(text: "Export for Claude")
                exportRow
                Text("Your key stays on this device only.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $payload) { p in ActivitySheet(items: p.items) }
        .confirmationDialog("Remove the key?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove the key", role: .destructive) {
                ClaudeKey.remove()
                client.keyChanged()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Claude stops choosing. The suggestions come from the rule book alone. You can type a key again at any time.")
        }
    }

    private var explanation: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("It picks among the choices the rule book offers and words the reason. It changes nothing; you still tap.")
                Text("For each suggestion, one question goes from your iPhone to Anthropic. It holds: the choices on the card and the rule book\u{2019}s reason; today\u{2019}s date; for each of the last 14 days, the minutes planned and done, how hard the hardest session felt, how you felt that morning, and any extras, such as a walk or hike of 30 minutes or more your watch recorded; and the next 7 days of your plan, each session\u{2019}s sport, minutes and effort. Your key goes with it, so Anthropic knows the question is yours.")
                Text("Nothing else is sent: not your name, notes, session titles, photographs, tests, zones, weight, or the Health and Garmin morning numbers.")
                    .accessibilityIdentifier("claude-sent")
                Text("It costs about a dollar a month, never more than 5 US dollars a month. The app stops asking when the month reaches it.")
            }
            .font(.footnote).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var keyField: some View {
        SecureField("Type your Anthropic key", text: $typed)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            .accessibilityIdentifier("claude-key")
        if let problem {
            Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("claude-problem")
        }
        HStack(spacing: 8) {
            Button("Cancel") { typed = ""; problem = nil; dismiss() }
                .settingsButton(tint: Theme.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("claude-cancel")
            Button(saving ? "Checking…" : "Save") { Task { await save() } }
                .settingsButton(tint: Theme.today, filled: true)
                .accessibilityIdentifier("claude-save")
        }
    }

    @ViewBuilder private var keySaved: some View {
        Card {
            VStack(alignment: .leading, spacing: 3) {
                Text("Key saved").font(.body.weight(.semibold)).foregroundStyle(Theme.today)
                    .accessibilityIdentifier("claude-status")
                Text(ClaudeKey.masked).font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityHidden(true)
            }
        }
        if client.rejectedKey {
            Text("Anthropic did not accept this key.").font(.footnote).foregroundStyle(Theme.danger)
                .accessibilityIdentifier("claude-problem")
        }
        Button("Remove the key") { confirmRemove = true }
            .settingsButton(tint: Theme.danger)
            .accessibilityIdentifier("claude-remove")
    }

    private var switchRow: some View {
        Card {
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Let Claude choose among the suggestions", isOn: Binding(get: { client.isOn }, set: { client.isOn = $0 }))
                    .font(.body.weight(.semibold))
                    .tint(Theme.today)
                    .disabled(!client.keySaved)
                    .accessibilityIdentifier("claude-on")
                if !client.keySaved {
                    Text("Needs a key first.").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var month: some View {
        Text(client.monthLine).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
            .accessibilityIdentifier("claude-month")
    }

    @ViewBuilder private var answered: some View {
        SectionHeading(text: "What Claude answered")
        if client.log.isEmpty {
            Text("Nothing yet.").font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 2)
        } else {
            ForEach(client.log.prefix(30)) { entry in
                Card {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.when(entry.at) + " · " + entry.choiceWords).font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        if !entry.why.isEmpty { Text(entry.why).font(.footnote).foregroundStyle(Theme.text) }
                        Text(String(format: "%.2f US dollars", entry.dollars)).font(.caption).foregroundStyle(Theme.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("claude-log-row")
            }
        }
    }

    private var exportRow: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your season as plain text: the phases, your tests and zones, the last 8 weeks and the next 4. Paste it into the Claude app to talk it over. This sends nothing by itself.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Share the plan as text") {
                    if let book = store.book {
                        payload = SharePayload(items: [ClaudeExport.brief(book, today: store.today)])
                    }
                }
                .settingsButton(tint: Theme.today)
                .accessibilityIdentifier("claude-export")
            }
        }
    }

    private static func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: date)
    }

    private func save() async {
        let key = typed.filter { !$0.isWhitespace }
        guard !key.isEmpty else {
            problem = "Nothing typed yet. Type your Anthropic key into the field first."
            return
        }
        saving = true
        problem = nil
        switch await client.check(key) {
        case .ok:
            if ClaudeKey.save(key) {
                typed = ""
                client.keyChanged()
            } else {
                problem = "This device could not keep the key. Try again."
            }
        case .rejected:
            problem = "Anthropic did not accept this key."
        case .unreachable:
            problem = "Anthropic could not be reached just now. Try again in a minute."
        }
        saving = false
    }
}
