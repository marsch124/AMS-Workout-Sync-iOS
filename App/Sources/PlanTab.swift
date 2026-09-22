import SwiftUI
import WorkoutCore

struct PlanTab: View {
    @EnvironmentObject var store: Store
    @State private var range: Range = {
        #if DEBUG
        // A screen walk can open a given list: AMSWS_LIST=Done.
        if let name = ProcessInfo.processInfo.environment["AMSWS_LIST"], let r = Range(rawValue: name) { return r }
        #endif
        return .upcoming
    }()
    @State private var openExtra: ExtraSummary?

    /*
     * A day's work, whether or not the plan asked for it.
     *
     * He went looking for Wednesday's walk under Done and it was not there:
     * this tab had only ever listed the workbook's own rows, so an extra lived
     * on Today for one day and after that only on its own screen — which is a
     * reasonable place for it and not the place anybody looks for "what have I
     * done". (The web app answered the same report in v1.69.0.)
     */
    enum Row: Identifiable {
        case session(Workout)
        case extra(ExtraSummary)

        var id: String {
            switch self {
            case .session(let w): return "s:" + w.key
            case .extra(let x): return "x:" + x.id
            }
        }
        var dayKey: String {
            switch self {
            case .session(let w): return w.dayKey
            case .extra(let x): return x.dayKey
            }
        }
    }

    enum Range: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming", done = "Done", missed = "Missed", all = "All"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let view = store.view {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sessions").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 12)
                            .accessibilityIdentifier("sessions-title")
                        // Four counts, each the length of the list its word opens —
                        // counted from that same list, so the two cannot disagree.
                        // A segmented control cut "Upcoming" short; the number
                        // stands under the word instead.
                        HStack(spacing: 6) {
                            ForEach(Range.allCases) { r in
                                let chosen = r == range
                                Button { withAnimation(.easeInOut(duration: 0.12)) { range = r } } label: {
                                    VStack(spacing: 1) {
                                        Text(r.rawValue).font(.caption.weight(.semibold))
                                        Text("\(rows(r, view).count)").font(.title3.weight(.bold).monospacedDigit())
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .foregroundStyle(chosen ? Theme.plan : Theme.secondary)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(chosen ? Theme.plan.opacity(0.16) : Theme.surface))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("sessions-filter-\(r.rawValue.lowercased())")
                            }
                        }

                        let days = grouped(shown(view), newestFirst: newestFirst)
                        if days.isEmpty {
                            Text(emptyText).font(.callout).foregroundStyle(Theme.secondary).padding(.top, 24)
                        }
                        ForEach(days, id: \.0) { day, list in
                            SectionHeading(text: Dates.long(day))
                            ForEach(list) { row in
                                switch row {
                                case .session(let w):
                                    NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping) }
                                        .accessibilityIdentifier("sessions-session-\(w.dayKey)-\(w.discipline.id)")
                                        .buttonStyle(.plain)
                                case .extra(let x):
                                    Button { openExtra = x } label: { ExtraCard(extra: x) }
                                        .accessibilityIdentifier("sessions-extra-\(x.dayKey)-\(x.activity)")
                                        .accessibilityIdentifier("sessions-extra-\(x.dayKey)-\(x.activity)")
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                } else {
                    EmptyWorkbook()
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .refreshable { store.refresh() }
            .navigationDestination(for: String.self) { key in SessionView(key: key) }
            .sheet(item: $openExtra) { x in ExtraDetailView(extra: x).environmentObject(store) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var emptyText: String {
        switch range {
        case .upcoming: return "Nothing left in the plan."
        case .done: return "Nothing recorded yet."
        case .missed: return "Nothing marked missed."
        case .all: return "The plan is empty."
        }
    }

    /*
     * The web app's four lists. Upcoming leads with anything from before
     * today that was never recorded, so it cannot fall between Upcoming and
     * Done and never be seen again.
     */
    private func list(_ range: Range, _ view: PlanView) -> [Workout] {
        let today = store.today
        switch range {
        case .upcoming:
            let behind = view.outstanding(before: today)
            let ahead = view.visible.filter { $0.dayKey >= today && $0.state == .todo }
            return behind + ahead
        case .done:
            return view.plan.filter { $0.state == .done }.reversed()
        case .missed:
            return view.plan.filter { $0.state == .missed }.reversed()
        case .all:
            return view.visible
        }
    }

    /*
     * Done is the one segment whose question an extra answers, and All has to
     * hold them or it would hold less than Done does. Upcoming and Missed are
     * about the plan, which an extra is never part of: it is logged at the
     * moment it is made.
     */
    private func rows(_ range: Range, _ view: PlanView) -> [Row] {
        let sessions = list(range, view).map(Row.session)
        guard range == .done || range == .all else { return sessions }
        return sessions + view.extras.map(Row.extra)
    }

    /* The list as shown. Only the length of Upcoming is capped, never its count. */
    private func shown(_ view: PlanView) -> [Row] {
        let all = rows(range, view)
        return range == .upcoming ? Array(all.prefix(120)) : all
    }

    /* Done and Missed are read backwards from now; the other two read forwards. */
    private var newestFirst: Bool { range == .done || range == .missed }

    /*
     * A day at a time, in the segment's own direction. The extras arrive after
     * the sessions, so they sit under the day's own work; a day that holds
     * nothing but an extra makes a group of its own, which is why the days are
     * put back in order afterwards rather than left where they were appended.
     */
    private func grouped(_ list: [Row], newestFirst: Bool) -> [(String, [Row])] {
        var out: [(String, [Row])] = []
        var seen: [String: Int] = [:]
        for row in list {
            if let i = seen[row.dayKey] {
                out[i].1.append(row)
            } else {
                seen[row.dayKey] = out.count
                out.append((row.dayKey, [row]))
            }
        }
        out.sort { newestFirst ? $0.0 > $1.0 : $0.0 < $1.0 }
        return out
    }
}
