import SwiftUI
import WorkoutCore

/*
 * Away mode (round 28, pick 17). Settings › Away: a switch "I am away", the
 * first and last day, and what he HAS there. Held on the page until Save;
 * Cancel leaves everything as it was. Kept on the shelf under "away", so it
 * follows him between iPhone, iPad and Mac; nothing here touches the plan.
 *
 * While a day lies inside the period: a calm grey chip on a session that needs
 * something he does not have, one grey line under Today's heading, and the rule
 * book's "away" trigger (Core, Away.swift) which only suggests.
 */

enum AwayStore {
    static let key = "away"

    /* The period now, or nil. DEBUG: AMSWS_AWAY=nopool shows an invented one (never stored). */
    @MainActor static func current(today: String) -> AwayPeriod? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_AWAY"] == "nopool" {
            return AwayPeriod(from: PlanView.addDays(today, -1), until: PlanView.addDays(today, 5), has: ["bike"])
        }
        #endif
        return ShelfStore.shared.value(AwayPeriod.self, for: key)
    }
}

// MARK: - the page

struct AwayPage: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var on: Bool
    @State private var from: String
    @State private var until: String
    @State private var has: Set<String>

    init() {
        let today = PlanView.todayKey()
        var period = ShelfStore.shared.value(AwayPeriod.self, for: AwayStore.key)
        #if DEBUG
        // AMSWS_AWAY_PAGE=1: an invented period, so the page shows something.
        if ProcessInfo.processInfo.environment["AMSWS_AWAY_PAGE"] != nil, period == nil {
            period = AwayPeriod(from: today, until: PlanView.addDays(today, 8), has: ["bike", "openwater"])
        }
        #endif
        _on = State(initialValue: period != nil)
        _from = State(initialValue: period?.from.isEmpty == false ? period!.from : today)
        _until = State(initialValue: period?.until.isEmpty == false ? period!.until : PlanView.addDays(today, 7))
        _has = State(initialValue: Set(period?.has ?? []))
    }

    private var period: AwayPeriod { AwayPeriod(from: from, until: until, has: AwayThing.allCases.map(\.rawValue).filter { has.contains($0) }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $on) {
                        Text("I am away").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.settings)
                    .accessibilityIdentifier("away-switch")
                    dayRow("From", $from, id: "away-from")
                    dayRow("Until", $until, id: "away-until")
                    Text("Until is your last day away. Sessions you cannot do there get a grey note, and the app may suggest a swap; nothing in your plan changes until you tap Take it.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT I HAVE THERE").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.settings)
                    ForEach(AwayThing.allCases, id: \.self) { thing in
                        Toggle(isOn: Binding(get: { has.contains(thing.rawValue) },
                                             set: { if $0 { has.insert(thing.rawValue) } else { has.remove(thing.rawValue) } })) {
                            Text(thing.tickWord).font(.body).foregroundStyle(Theme.text)
                        }
                        .tint(Theme.settings)
                        .accessibilityIdentifier("away-has-\(thing.rawValue)")
                    }
                    Text("Switch on only what you will really have. Everything left off counts as missing.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
                .opacity(on ? 1 : 0.45)
                .disabled(!on)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.settings.opacity(0.07).background(Theme.bg).ignoresSafeArea())
        .navigationTitle("Away")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier("settings-away")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("away-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .accessibilityIdentifier("away-save")
            }
        }
        .onChange(of: from) { _, new in if until < new { until = new } }
    }

    private func save() {
        if on {
            _ = shelf.set(AwayPeriod(from: from, until: max(from, until), has: period.has), for: AwayStore.key)
        } else if shelf.has(AwayStore.key) {
            shelf.remove(for: AwayStore.key)
        }
        dismiss()
    }

    /* The head card, filled with Settings' slate. */
    private var head: some View {
        let shown: String = on
            ? "Away until " + Away.dayWords(max(from, until))
            : "Not away"
        let missing = period.lacking.map(\.shortNo).joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 2) {
            Text("AWAY").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            Text(shown).font(.title2.weight(.bold))
            Text(on ? (missing.isEmpty ? "You have everything there" : missing.prefix(1).uppercased() + missing.dropFirst())
                    : "Switch it on for a trip, and say what you will have there")
                .font(.footnote).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.settings))
    }

    private func dayRow(_ title: String, _ day: Binding<String>, id: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
            DatePicker(title, selection: Binding(
                get: { parseDayKey(day.wrappedValue) ?? Date() },
                set: { day.wrappedValue = dayKey($0) ?? day.wrappedValue }),
                       displayedComponents: .date)
                .labelsHidden()
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
                .accessibilityIdentifier(id)
            Spacer(minLength: 0)
        }
        .opacity(on ? 1 : 0.45)
        .disabled(!on)
    }
}

// MARK: - the way in

/* Settings: one row. */
struct AwaySettingsRow: View {
    @ObservedObject private var shelf = ShelfStore.shared
    var body: some View {
        let period = shelf.value(AwayPeriod.self, for: AwayStore.key)
        NavigationLink { AwayPage() } label: {
            SettingsRow(title: "Away",
                        sub: period.map { "Until \(Away.dayWords($0.until)) \u{2014} sessions you cannot do there are marked" }
                            ?? "Off \u{2014} for a trip: say what you will have there", chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-away-row")
    }
}

/* On the Suggestions page: a small word button. */
struct AwayLinkButton: View {
    var body: some View {
        HStack {
            NavigationLink { AwayPage() } label: { Text("Away") }
                .settingsButton(tint: Theme.settings)
                .accessibilityIdentifier("suggest-away")
            Text("Tell the app where you are travelling").font(.footnote).foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - what shows while away

/* The calm grey chip: words only, no colour of its own. Hidden when there is nothing to say. */
struct AwayChip: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    let workout: Workout

    var body: some View {
        if !workout.logged, !workout.missed, let words = Away.chip(
            sport: RBSport(disciplineID: workout.discipline.id), text: workout.title + " " + workout.sections.map(\.text).joined(separator: " "),
            day: workout.dayKey, period: AwayStore.current(today: store.today)) {
            Pill(text: words)
                .accessibilityIdentifier("away-chip")
        }
    }
}

/* One grey line under Today's heading while away; a tap opens the page. */
struct AwayTodayLine: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        if let line = Away.todayLine(period: AwayStore.current(today: store.today), today: store.today) {
            NavigationLink { AwayPage() } label: {
                Text(line).font(.footnote).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("away-today-line")
        }
    }
}
