import SwiftUI
import WorkoutCore

/*
 * Repeat a session every week: the row on the New session page, "Repeat…" on a
 * planned session's page, the list of what will be added and what is left
 * out, and the one entry it leaves in Settings → Changes to the plan.
 * The rule itself (RepeatRule) is in Core.
 */
enum RepeatSession {
    @MainActor static func result(_ base: SessionDraft, until: String, store: Store) -> RepeatRule.Result {
        RepeatRule.plan(start: base.dayKey, until: until, sport: base.sport, title: base.title,
                        weeks: store.book?.weeks ?? [], sessions: store.book?.sessions ?? [])
    }

    @MainActor static func defaultUntil(_ start: String, store: Store) -> String {
        RepeatRule.defaultUntil(from: start, weeks: store.book?.weeks ?? [])
    }

    static func repeats(_ base: SessionDraft, _ r: RepeatRule.Result) -> [SessionDraft] {
        r.days.map { var d = base; d.dayKey = $0; return d }
    }

    /* The new session and its repeats in ONE change through addSessions: one entry, one Undo. */
    @MainActor static func save(_ base: SessionDraft, until: String, store: Store, includingBase: Bool) -> Bool {
        let r = result(base, until: until, store: store)
        let drafts = (includingBase ? [base] : []) + repeats(base, r)
        guard !drafts.isEmpty else { return false }
        return store.addSessions(drafts, why: RepeatRule.why(title: base.title, count: drafts.count)) == drafts.count
    }

    static func reason(_ l: RepeatRule.LeftOut, sport: String) -> String {
        let day = Dates.short(l.day)
        switch l.reason {
        case .alreadyThere:
            return "\(day) left out \u{2014} that day already has a \(FavouritesShelf.discipline(sport).label) session with this title"
        case .raceWeek: return "\(day) left out \u{2014} it is in race week"
        case .outsidePlan: return "\(day) left out \u{2014} it is outside your plan"
        }
    }
}

/* The "Repeat" row and, once it is on, the date and the list. `until` nil = does not repeat. */
struct RepeatSection: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var keeper = SuggestionKeeper.shared
    /* The session as the page stands now: its day is the first one. */
    let base: SessionDraft
    @Binding var until: String?
    @State private var note: String?

    private var lower: String { PlanView.addDays(base.dayKey, 7) }
    private var upper: String? { RepeatRule.lastDay(of: store.book?.weeks ?? []) }
    private var hasRoom: Bool { upper.map { $0 >= lower } ?? true }

    private var box: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repeat").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            HStack(spacing: 10) {
                Menu {
                    Button("Does not repeat") { until = nil }
                    Button("Every week until\u{2026}") { until = until ?? RepeatSession.defaultUntil(base.dayKey, store: store) }
                } label: {
                    HStack(spacing: 8) {
                        Text(until == nil ? "Does not repeat" : "Every week until").font(.body).foregroundStyle(Theme.text)
                        Text("\u{25BE}").foregroundStyle(Theme.secondary)
                    }
                    .padding(10).background(box)
                }
                .accessibilityIdentifier("repeat-row")
                if let u = until, hasRoom {
                    DatePicker("Until", selection: dateBinding(u), in: range, displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
                        .accessibilityIdentifier("repeat-until")
                }
                Spacer(minLength: 0)
            }
            if until != nil && !hasRoom {
                Text("Your plan ends before the next week, so there is nothing to repeat into.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("repeat-none")
            } else if let u = until {
                list(RepeatSession.result(base, until: u, store: store))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: [base.dayKey, base.sport, base.title, until ?? ""]) { await refreshNote() }
    }

    private var range: ClosedRange<Date> {
        let lo = parseDayKey(lower) ?? Date()
        let hi = upper.flatMap(parseDayKey) ?? lo.addingTimeInterval(86_400 * 365)
        return lo...max(lo, hi)
    }

    private func dateBinding(_ u: String) -> Binding<Date> {
        Binding(get: { parseDayKey(u) ?? range.lowerBound },
                set: { until = dayKey($0) ?? u })
    }

    @ViewBuilder
    private func list(_ r: RepeatSession.Result) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if r.days.isEmpty {
                Text("Nothing would be added.").font(.subheadline).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("repeat-list")
            } else {
                Text("\(r.days.count) session\(r.days.count == 1 ? "" : "s"): " + r.days.map { Dates.short($0) }.joined(separator: ", "))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.plan)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("repeat-list")
            }
            if !r.leftOut.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(r.leftOut.enumerated()), id: \.offset) { _, l in
                        Text(RepeatSession.reason(l, sport: base.sport)).font(.footnote).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("repeat-left-out")
            }
            if !r.days.isEmpty {
                Text("They are added together, and one Undo under Changes to the plan takes them all back.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("repeat-note")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.plan.opacity(0.08)))
    }

    /* The rule book's calm grey line for the repeats, if one applies (first few days, shown once each). Never blocks. */
    private func refreshNote() async {
        guard let u = until else { note = nil; return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }
        let drafts = RepeatSession.repeats(base, RepeatSession.result(base, until: u, store: store)).prefix(6)
        var lines: [String] = []
        for d in drafts { if let n = keeper.note(forChanging: nil, to: d), !lines.contains(n) { lines.append(n) } }
        note = lines.first
    }
}

extension RepeatSession { typealias Result = RepeatRule.Result }

/* "Repeat…" on an existing session's page: its own small page with Cancel and the full-colour add button. */
struct RepeatSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let key: String
    @State private var until: String?
    @State private var failed = false
    /* A second tap while the page closes adds nothing again. */
    @State private var added = false

    private var base: SessionDraft? { store.draft(of: key) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let base {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(base.title) \u{00B7} \(Dates.short(base.dayKey))")
                            .font(.headline).foregroundStyle(Theme.text)
                        RepeatSection(base: base, until: $until)
                        if failed {
                            Text(store.lastProblem ?? "The sessions could not be added. Nothing was changed.")
                                .font(.footnote).foregroundStyle(Theme.danger)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("repeat-cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let base {
                    let count = until.map { RepeatSession.result(base, until: $0, store: store).days.count } ?? 0
                    Button {
                        guard !added else { return }
                        if let u = until, RepeatSession.save(base, until: u, store: store, includingBase: false) { added = true; dismiss() } else { failed = true }
                    } label: {
                        Text(count == 0 ? "Add sessions" : "Add \(count) session\(count == 1 ? "" : "s")")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                    .disabled(count == 0)
                    .accessibilityIdentifier("repeat-add")
                    .padding(16).background(Theme.bg)
                }
            }
            .onAppear { if until == nil, let base { until = RepeatSession.defaultUntil(base.dayKey, store: store) } }
        }
    }
}

/* In Changes to the plan: the sessions of one repeat as ONE entry with ONE Undo. Newest change first. */
struct RepeatChangeRow: View {
    @EnvironmentObject var store: Store
    let changes: [PlanChange]
    let index: Int
    @State private var asking = false

    private var undoable: [PlanChange] {
        RepeatRule.undoable(changes, canUndo: { store.canUndo($0) }, loggedSince: { key in
            store.isWaiting(key) || (store.workout(key).map { $0.logged || $0.missed } ?? false)
        })
    }
    /* Sessions of this repeat logged since: Undo leaves them in the plan. */
    private var keptLogged: Int { changes.filter { !$0.undone && store.canUndo($0.id) }.count - undoable.count }
    private var allUndone: Bool { changes.allSatisfy(\.undone) }

    var body: some View {
        let lead = changes[0]
        let days = changes.compactMap { store.workout($0.key)?.dayKey }.sorted()
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("ADDED").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Theme.plan)
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
            Text("\(changes.count) sessions: \(lead.title)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Text(RepeatRule.shownWhy(lead.why)).font(.footnote).foregroundStyle(Theme.secondary)
            if !days.isEmpty {
                Text(days.map { Dates.short($0) }.joined(separator: ", ")).font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .opacity(allUndone ? 0.7 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-repeat-\(index)")
        .confirmationDialog("Undo this change?", isPresented: $asking, titleVisibility: .visible) {
            Button("Undo", role: .destructive) { for c in undoable { store.undoChange(c.id) } }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("\(undoable.count) session\(undoable.count == 1 ? " is" : "s are") taken out of the plan again." + (keptLogged > 0 ? " The \(keptLogged) you have logged since stay\(keptLogged == 1 ? "s" : "")." : ""))
        }
    }
}
