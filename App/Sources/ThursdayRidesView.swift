import SwiftUI
import WorkoutCore

/*
 * Settings → Thursday rides: one easy ride every Thursday beside the easy run.
 * The page shows the rides and what each week becomes first; nothing is added
 * until the one full-colour button is tapped, and the whole lot can be undone
 * under Changes to the plan.
 */
struct ThursdayRidesView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /* How many were added by this visit; the page then says so instead of offering them again. */
    @State private var added = 0
    @State private var failed = false

    /* From the next Monday on (today, when today is a Monday). */
    private var start: String {
        let monday = PlanView.weekStart(store.today)
        return monday == store.today ? monday : PlanView.addDays(monday, 7)
    }

    private var weeksAhead: Bool {
        (store.book?.weeks ?? []).contains { PlanView.addDays($0.monday, 3) >= start }
    }

    private var drafts: [SessionDraft] {
        guard let book = store.book else { return [] }
        return ThursdayRides.drafts(weeks: book.weeks, sessions: book.sessions, changes: book.changes, from: start)
    }

    private var weekRows: [ThursdayRides.WeekMinutes] {
        guard let book = store.book else { return [] }
        return ThursdayRides.weekMinutes(weeks: book.weeks, sessions: book.sessions, mapping: book.mapping, drafts: drafts)
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = utc; f.timeZone = utc.timeZone; f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private func day(_ key: String) -> String { parseDayKey(key).map(Self.dayFormat.string(from:)) ?? key }
    private func minutes(_ m: Double) -> String { formatDuration(m.rounded() * 60) }
    /* Written as every other length of time in the app: "5h 45m", "45m". */
    private func hoursMinutes(_ m: Double) -> String { formatDuration(m.rounded() * 60) }

    var body: some View {
        let list = drafts
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("One easy ride every Thursday beside the easy run, from next Monday to your race. Easy, test and taper weeks get a short spin; race-practice weeks and race week get none.")
                    .font(.callout).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("rides-title")
                if added > 0 {
                    Text("\(added) rides added. Undo them under Changes to the plan.")
                        .font(.callout.weight(.semibold)).foregroundStyle(Theme.today)
                        .accessibilityIdentifier("rides-done")
                } else if !weeksAhead {
                    Text("There are no weeks ahead in the plan to add rides to.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("rides-none")
                } else if list.isEmpty {
                    Text("These rides are already in your plan.")
                        .font(.callout.weight(.semibold)).foregroundStyle(Theme.today)
                        .accessibilityIdentifier("rides-already")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.offset) { index, d in
                            if index > 0 { Divider().overlay(Theme.border) }
                            rideRow(d)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                    Text("Your weeks, before \u{2192} after")
                        .font(.headline).foregroundStyle(Theme.text).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(weekRows.enumerated()), id: \.offset) { index, w in
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
        .navigationTitle("Thursday rides")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(added > 0 ? "Done" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("rides-cancel")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if added == 0 && !list.isEmpty {
                VStack(spacing: 8) {
                if failed {
                    Text(store.lastProblem ?? "The rides could not be added. Nothing was changed.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("rides-problem")
                }
                Button {
                    added = store.addSessions(list, why: ThursdayRides.why)
                    failed = added == 0
                } label: {
                    Text("Add \(list.count) rides").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                .accessibilityIdentifier("rides-add")
                }
                .padding(16)
                .background(Theme.bg)
            }
        }
    }

    private func rideRow(_ d: SessionDraft) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(day(d.dayKey)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(shortTitle(d.title)).font(.subheadline).foregroundStyle(Theme.sportInk("bike"))
                Text("\(minutes(d.minutes ?? 0)) \u{00B7} \(d.intensity)").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rides-row")
    }

    /* The words before the colon: "Easy ride (trainer or road)". */
    private func shortTitle(_ t: String) -> String { t.components(separatedBy: ":").first ?? t }

    private func weekRow(_ w: ThursdayRides.WeekMinutes) -> some View {
        HStack(spacing: 8) {
            Text("Week \(w.number)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: true, vertical: false)
            Text("\(hoursMinutes(w.before)) \u{2192} \(hoursMinutes(w.after))").font(.subheadline).foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rides-week-row")
    }
}
