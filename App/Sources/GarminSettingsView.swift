import SwiftUI
import WorkoutCore

/* The row in Settings, under Apple Health: one line, leads to the page. */
struct GarminSettingsEntry: View {
    @ObservedObject private var reader = GarminReader.shared
    var body: some View {
        NavigationLink { GarminSettingsView() } label: {
            SettingsRow(title: reader.keySaved ? "Garmin · connected" : "Garmin · not connected",
                        sub: reader.keySaved ? "Today and Body show your Garmin numbers"
                                             : "Overnight HRV, sleep, Body Battery and stress from your Garmin watch",
                        chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-garmin")
    }
}

/*
 * Connect Garmin once: he makes a personal key at connect.garmin.com and
 * pastes it here. It goes to the Keychain and is shown only as dots after
 * that. The numbers are shown on Today and on the Body page; they never change the plan.
 */
struct GarminSettingsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var reader = GarminReader.shared
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var problem: String?
    @State private var saving = false
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if reader.keySaved { connected } else { notConnected }
                Text("The key stays on this device only. The numbers are shown, they never change your plan.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        // The small centred title every other Settings page has.
        .navigationTitle("Garmin")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Garmin").font(.headline).foregroundStyle(Theme.text).accessibilityIdentifier("garmin-title")
            }
        }
        .confirmationDialog("Remove the key?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove the key", role: .destructive) {
                GarminKey.remove()
                Task { await GarminClient.shared.forgetToken() }
                reader.keyChanged()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Today and Body stop showing Garmin numbers. You can paste a key again at any time.")
        }
    }

    @ViewBuilder private var notConnected: some View {
        Text("Your Garmin watch knows things Apple Health does not hand over: overnight HRV, sleep, Body Battery and stress. Make a personal key once in your Garmin Connect account at connect.garmin.com, paste it here once, and Today and the Body page show those numbers beside your own normal.")
            .font(.footnote).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
        SecureField("Paste your Garmin key", text: $typed)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            .accessibilityIdentifier("garmin-key")
        if let problem {
            Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("garmin-problem")
        }
        HStack(spacing: 8) {
            Button("Cancel") { typed = ""; problem = nil; dismiss() }
                .settingsButton(tint: Theme.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("garmin-cancel")
            Button(saving ? "Checking…" : "Save") { Task { await save() } }
                .mainSmallButton()
                .accessibilityIdentifier("garmin-save")
        }
    }

    @ViewBuilder private var connected: some View {
        // The key itself is never shown again: dots only.
        Card {
            VStack(alignment: .leading, spacing: 3) {
                Text("Connected").font(.body.weight(.semibold)).foregroundStyle(Theme.today)
                    .accessibilityIdentifier("garmin-status")
                Text("••••••••••••").font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityHidden(true)
                if let g = reader.numbers {
                    Text("Last read \(GarminWords.time(g.readAt))").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
        if let p = reader.problem {
            Text(p).font(.footnote).foregroundStyle(Theme.danger)
                .accessibilityIdentifier("garmin-problem")
        }
        HStack(spacing: 8) {
            Button(reader.reading ? "Reading…" : "Read again now") { Task { await reader.read(today: store.today) } }
                .settingsButton(tint: Theme.today)
                .disabled(reader.reading)
                .accessibilityIdentifier("garmin-again")
            Button("Remove the key") { confirmRemove = true }
                .settingsButton(tint: Theme.danger)
                .accessibilityIdentifier("garmin-remove")
        }
    }

    private func save() async {
        let key = typed.filter { !$0.isWhitespace }
        guard !key.isEmpty else {
            problem = "Nothing typed yet. Paste your Garmin key into the field first."
            return
        }
        saving = true
        problem = nil
        do {
            try await GarminClient.shared.checkKey(key)
            guard GarminKey.save(key) else {
                problem = "This device could not keep the key. Try again."
                saving = false
                return
            }
            typed = ""
            reader.keyChanged()
            saving = false
            await reader.read(today: store.today)
        } catch let f as GarminFailure {
            problem = f.words
            saving = false
        } catch {
            problem = GarminFailure.other.words
            saving = false
        }
    }
}
