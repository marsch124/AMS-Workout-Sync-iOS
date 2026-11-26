import SwiftUI
import WorkoutCore

/*
 * Settings → Mobility and strength (2.14): mobility every Monday, Wednesday and
 * Friday, strength every Tuesday and Thursday, 30 minutes each, from tomorrow
 * to race week. The page shows each week's change first; nothing changes
 * until the one full-colour button is tapped, and the whole lot is one entry
 * with one Undo under Changes to the plan.
 */
struct MobilityStrengthView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var done: MobilityStrength.Done?
    @State private var failed = false

    /* From tomorrow on: today is left as it is. */
    private var start: String { PlanView.addDays(store.today, 1) }

    private var change: MobilityStrength.Change {
        guard let book = store.book else { return MobilityStrength.Change() }
        return MobilityStrength.plan(weeks: book.weeks, sessions: book.sessions, changes: book.changes,
                                     mapping: book.mapping, from: start)
    }

    private var weeksAhead: Bool {
        (store.book?.weeks ?? []).contains { PlanView.addDays(PlanView.weekStart($0.monday), 6) >= start }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static let weekdayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE"
        return f
    }()

    private func day(_ key: String) -> String { parseDayKey(key).map(Self.dayFormat.string(from:)) ?? key }
    private func weekday(_ key: String) -> String { parseDayKey(key).map(Self.weekdayFormat.string(from:)) ?? key }
    private func hoursMinutes(_ m: Double) -> String { formatDuration(m.rounded() * 60) }

    var body: some View {
        let c = change
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mobility every Monday, Wednesday and Friday, strength every Tuesday and Thursday \u{2014} 30 min each, from tomorrow to your race. Your plan\u{2019}s own strength sessions move to Tuesday and Thursday with their exercises; a week with only one gets a second on Thursday. Race week keeps mobility only.")
                    .font(.callout).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("ms-title")
                if let done {
                    Text("Done: \(done.mobility) mobility sessions added, \(done.moved) strength sessions moved, \(done.strength) added. Undo it all under Changes to the plan.")
                        .font(.callout.weight(.semibold)).foregroundStyle(Theme.today)
                        .accessibilityIdentifier("ms-done")
                } else if !weeksAhead {
                    Text("There are no weeks ahead in the plan to change.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("ms-none")
                } else if c.isEmpty {
                    Text("These days are already in your plan.")
                        .font(.callout.weight(.semibold)).foregroundStyle(Theme.today)
                        .accessibilityIdentifier("ms-already")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(c.weeks.enumerated()), id: \.offset) { index, w in
                            if index > 0 { Divider().overlay(Theme.border) }
                            weekRow(w)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Mobility and strength")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(done != nil ? "Done" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("ms-cancel")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if done == nil && !c.isEmpty {
                VStack(spacing: 8) {
                    if failed {
                        Text(store.lastProblem ?? "The plan could not be changed. Nothing was changed.")
                            .font(.footnote).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("ms-problem")
                    }
                    Button {
                        done = store.applyMobilityStrength(c)
                        failed = done == nil
                    } label: {
                        Text("Change \(c.weeks.count) weeks").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                    .accessibilityIdentifier("ms-change")
                }
                .padding(16)
                .background(Theme.bg)
            }
        }
    }

    /* "Week 13 · Mon 30 Nov", then a mobility line, a strength line, and the week's minutes before → after. */
    private func weekRow(_ w: MobilityStrength.Week) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Week \(w.number) \u{00B7} \(day(w.monday))").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(hoursMinutes(w.before)) \u{2192} \(hoursMinutes(w.after))").font(.footnote).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
            if !w.mobility.isEmpty {
                Text("Mobility " + w.mobility.map(weekday).joined(separator: " \u{00B7} "))
                    .font(.footnote).foregroundStyle(Theme.sportInk("mobility"))
            }
            let strength = w.moves.map { "\(weekday($0.from)) \u{2192} \(weekday($0.to))" } + w.strengthAdded.map { "+ \(weekday($0))" }
            if !strength.isEmpty {
                Text("Strength " + strength.joined(separator: " \u{00B7} "))
                    .font(.footnote).foregroundStyle(Theme.sportInk("strength"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ms-week")
    }
}

/*
 * Settings → Changes to the plan: one round of Mobility and strength is one
 * entry with one Undo. Mobility and added strength sessions go out again,
 * moved strength sessions go back to their days; anything logged since stays.
 */
struct MobilityStrengthChangeRow: View {
    @EnvironmentObject var store: Store
    let changes: [PlanChange]
    let batch: String
    let index: Int
    @State private var asking = false

    private var undoable: [PlanChange] { store.mobilityStrengthUndoable(changes) }
    private var allUndone: Bool { changes.allSatisfy(\.undone) }

    var body: some View {
        let lead = changes[0]
        let added = changes.filter { $0.kind == "add" }.count
        let moved = changes.count - added
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("CHANGED").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Theme.plan)
                Text(lead.at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if allUndone {
                    Text("Undone").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("change-undone-\(index)")
                } else if !undoable.isEmpty {
                    Button("Undo") { asking = true }
                        .settingsButton(tint: Theme.danger)
                        .accessibilityIdentifier("change-undo-\(index)")
                } else {
                    Text("Changed again since").font(.caption).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("change-older-\(index)")
                }
            }
            Text(MobilityStrength.why).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Text("\(added) sessions added, \(moved) moved").font(.footnote).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .opacity(allUndone ? 0.7 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-ms-\(index)")
        .confirmationDialog("Undo this change?", isPresented: $asking, titleVisibility: .visible) {
            Button("Undo", role: .destructive) { store.undoMobilityStrength(batch: batch) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The mobility sessions and the added strength sessions are taken out again, and the moved strength sessions go back to their days. What you have logged since stays.")
        }
    }
}
