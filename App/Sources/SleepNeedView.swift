import SwiftUI
import WorkoutCore

/*
 * 2.19, his ask (27 Nov 2026): "Settings: Sleep Need = 6h". His own sleep need, used by
 * Body › Sleep debt in place of Garmin's per-night estimate. Kept on the shelf (iCloud),
 * so every device counts the same. 0 = Garmin's estimate, as before 2.19. Never set = 6h.
 */
enum SleepNeed {
    static let key = "sleep/needMinutes"
    /* His word: six hours. */
    static let standard = 360
    static let choices = [0, 300, 330, 360, 390, 420, 450, 480, 510, 540]

    @MainActor static var minutes: Int {
        #if DEBUG
        if let v = ProcessInfo.processInfo.environment["AMSWS_SLEEP_NEED"], let m = Int(v) { return m }
        #endif
        return ShelfStore.shared.value(Int.self, for: key) ?? standard
    }

    /* For the Sleep debt card: nil = Garmin's estimate. */
    @MainActor static var own: Double? { minutes > 0 ? Double(minutes) : nil }

    static func words(_ m: Int) -> String { m > 0 ? BodyHealth.needText(Double(m)) : "Garmin\u{2019}s estimate" }

    static func rowLine(_ m: Int) -> String {
        m > 0 ? "\(words(m)) a night \u{2014} your setting" : "Garmin\u{2019}s estimate for each night"
    }
}

/* Settings › Garmin: the row under the Garmin row. */
struct SleepNeedEntry: View {
    @ObservedObject private var shelf = ShelfStore.shared
    var body: some View {
        let _ = shelf.revision
        NavigationLink { SleepNeedView() } label: {
            SettingsRow(title: "Sleep need", sub: SleepNeed.rowLine(SleepNeed.minutes), chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("garmin-sleep-need")
    }
}

struct SleepNeedView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var chosen = SleepNeed.minutes
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SleepNeed.choices, id: \.self) { m in
                        Button { chosen = m } label: {
                            HStack(spacing: 10) {
                                Text(SleepNeed.words(m)).font(.body).foregroundStyle(Theme.text)
                                if m == SleepNeed.standard {
                                    Text("your ask").font(.caption).foregroundStyle(Theme.secondary)
                                }
                                Spacer(minLength: 0)
                                if chosen == m {
                                    Glyph(name: "icon-check", size: 15).foregroundStyle(Theme.settings)
                                        .accessibilityLabel("chosen")
                                }
                            }
                            .padding(.vertical, 9).padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sleep-need-\(m)")
                        .accessibilityAddTraits(chosen == m ? .isSelected : [])
                        if m != SleepNeed.choices.last { Divider().padding(.leading, 12) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                Text("Body \u{203A} Sleep debt counts each night against this. Garmin\u{2019}s estimate uses the need your watch gives for each night (8h where it gives none). The same on all your devices.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if failed {
                    Text("Not saved: iCloud could not keep it just now. Try again in a moment.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("sleep-need-failed")
                }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.settings.opacity(0.07).background(Theme.bg).ignoresSafeArea())
        .navigationTitle("Sleep need")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier("settings-sleep-need")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("sleep-need-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if shelf.set(chosen, for: SleepNeed.key) { dismiss() } else { failed = true }
                }
                .accessibilityIdentifier("sleep-need-save")
            }
        }
    }
}
