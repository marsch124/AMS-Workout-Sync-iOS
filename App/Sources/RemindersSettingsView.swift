import SwiftUI
import UserNotifications
import WorkoutCore

/*
 * Settings › Reminders: three switches, each with its time, a plain line on what
 * it sends, a test button, and a calm line when iOS has refused notifications.
 * Held on the page until Save; Cancel leaves everything as it was (as the
 * Suggestions page does). iOS is asked for permission only when the first
 * reminder is switched on.
 */
struct RemindersSettingsView: View {
    @ObservedObject private var centre = ReminderCentre.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReminderSettings

    init() {
        _draft = State(initialValue: ReminderCentre.shared.settings)
    }

    private var refused: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_REMINDERS_PAGE"] == "denied" { return true }
        #endif
        return centre.refused
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head
                if refused { refusedLine }
                block("Evening reminder", sends: "Tomorrow\u{2019}s session in one line, like \u{201C}Tomorrow: Run \u{00B7} 45 min easy\u{201D}. Tapping it opens Today.",
                      on: $draft.eveningOn, minutes: $draft.eveningMinutes, id: "evening")
                block("Sunday card", sends: "On Sunday evening: \u{201C}Next week: 7 sessions \u{00B7} 8h 40m\u{201D}. From then until Monday morning Today shows next week day by day, with a Close button.",
                      on: $draft.sundayOn, minutes: $draft.sundayMinutes, id: "sunday")
                block("Missed session", sends: "The morning after a planned session that is neither logged nor marked missed: \u{201C}Yesterday\u{2019}s Run was not logged.\u{201D} with Skip it, Move to today (when your plan allows it) and It is done. Each one is your own tap.",
                      on: $draft.missedOn, minutes: $draft.missedMinutes, id: "missed")

                Button { centre.sendTest() } label: {
                    Text("Send a test now").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.mainButton))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminder-test")
                .padding(.top, 4)

                Text("Nothing is sent while the stop sign or an illness is on. These switches belong to this \(Device.word): your other devices have their own. Reminders are worked out on the device from your plan; nothing goes through a server.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.settings.opacity(0.07).background(Theme.bg).ignoresSafeArea())
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier("settings-reminders")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("reminders-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { centre.apply(draft); dismiss() }
                    .accessibilityIdentifier("reminders-save")
            }
        }
        .onChange(of: draft.anyOn) { was, now in
            // The first switch turned on is when iOS is asked.
            if now, !was, !centre.settings.anyOn { centre.askForPermissionNow() }
        }
        .task { await centre.refreshStatus() }
    }

    /* The head card, filled with Settings' slate. */
    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("REMINDERS").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(onCount)").font(.largeTitle.weight(.bold))
                Text(onCount == 1 ? "switched on" : "switched on").font(.subheadline.weight(.semibold))
            }
            Text("On this \(Device.word) only").font(.footnote).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.settings))
    }

    private var onCount: Int { [draft.eveningOn, draft.sundayOn, draft.missedOn].filter { $0 }.count }

    private var refusedLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications are switched off for this app in iOS, so no reminder can appear. Nothing else is affected.")
                .font(.footnote).foregroundStyle(Theme.text)
            Button("Open iOS settings") { centre.openSystemSettings() }
                .settingsButton(tint: Theme.settings)
                .accessibilityIdentifier("reminders-open-settings")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminders-refused")
    }

    /* One reminder: its switch and time side by side, then what it sends. */
    private func block(_ title: String, sends: String, on: Binding<Bool>, minutes: Binding<Int>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: on) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            }
            .tint(Theme.settings)
            .accessibilityIdentifier("reminder-\(id)-switch")
            HStack(spacing: 8) {
                Text(id == "missed" ? "Asked at" : "Sent at").font(.subheadline).foregroundStyle(Theme.secondary)
                DatePicker("Time", selection: timeBinding(minutes), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
                    .accessibilityIdentifier("reminder-\(id)-time")
                Spacer(minLength: 0)
            }
            .opacity(on.wrappedValue ? 1 : 0.45)
            .disabled(!on.wrappedValue)
            Text(sends).font(.footnote).foregroundStyle(Theme.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    /* Minutes after midnight as a clock time (read in UTC, so no zone moves it). */
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: Double(minutes.wrappedValue * 60)) },
                set: { minutes.wrappedValue = Int($0.timeIntervalSince1970 / 60) % (24 * 60) })
    }
}

/* The card at the top of Today: next week's sessions, from Sunday evening until Monday morning. */
struct SundayCardArea: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var centre = ReminderCentre.shared

    private var debug: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_SUNDAY_CARD"] != nil
        #else
        return false
        #endif
    }

    private var monday: String? {
        if debug {
            let next = PlanView.addDays(PlanView.weekStart(store.today), 7)
            return centre.closedCardWeek == next ? nil : next
        }
        return centre.cardWeek(today: store.today)
    }

    var body: some View {
        if let monday, let card = centre.card(monday: monday, store: store) {
            SundayCardView(card: card) { centre.closeCard(monday) }
        }
    }
}

struct SundayCardView: View {
    let card: SundayCard
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            head
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        Text(weekday(row.dayKey)).font(.footnote.weight(.semibold)).foregroundStyle(Theme.plan)
                            .frame(width: 34, alignment: .leading)
                        SportBadge(discipline: Disciplines.classify(row.disciplineId), size: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                            if let s = row.seconds, s > 0 {
                                Text(formatDuration(s)).font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sunday-card")
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEXT WEEK").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                Spacer(minLength: 0)
                Button("Close", action: close)
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.22)))
                    .accessibilityIdentifier("sunday-card-close")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(card.rows.count)").font(.largeTitle.weight(.bold))
                Text(card.rows.count == 1 ? "session" : "sessions").font(.subheadline.weight(.semibold))
                Text(formatDuration(card.totalSeconds)).font(.title2.weight(.bold)).padding(.leading, 6)
            }
            HStack(spacing: 8) {
                if !card.phase.isEmpty { Text(card.phase).font(.footnote.weight(.semibold)) }
                if let letter = card.letter, let word = card.weekWord {
                    // The season bars' own letter: E easy week, T test week.
                    Text("\(letter) \u{00B7} \(word)").font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.plan)
    }

    private func weekday(_ key: String) -> String { String((parseDayKey(key).map { Dates.weekday.string(from: $0) } ?? "").prefix(3)) }
}
