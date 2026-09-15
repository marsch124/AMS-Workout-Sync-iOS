import SwiftUI
import WorkoutCore

struct PlanTab: View {
    @EnvironmentObject var store: Store
    @State private var range: Range = .upcoming

    enum Range: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming", done = "Done", missed = "Missed", all = "All"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let view = store.view {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Plan").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 12)
                        Picker("Show", selection: $range) {
                            ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        let days = grouped(workouts(view))
                        if days.isEmpty {
                            Text(emptyText).font(.callout).foregroundStyle(Theme.secondary).padding(.top, 24)
                        }
                        ForEach(days, id: \.0) { day, list in
                            SectionHeading(text: Dates.long(day))
                            ForEach(list) { w in
                                NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping) }
                                    .buttonStyle(.plain)
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
    private func workouts(_ view: PlanView) -> [Workout] {
        let today = store.today
        switch range {
        case .upcoming:
            let behind = view.outstanding(before: today)
            let ahead = view.visible.filter { $0.dayKey >= today && $0.state == .todo }
            return Array((behind + ahead).prefix(120))
        case .done:
            return view.plan.filter { $0.state == .done }.reversed()
        case .missed:
            return view.plan.filter { $0.state == .missed }.reversed()
        case .all:
            return view.visible
        }
    }

    private func grouped(_ list: [Workout]) -> [(String, [Workout])] {
        var out: [(String, [Workout])] = []
        for w in list {
            if let last = out.last, last.0 == w.dayKey {
                out[out.count - 1].1.append(w)
            } else {
                out.append((w.dayKey, [w]))
            }
        }
        return out
    }
}
