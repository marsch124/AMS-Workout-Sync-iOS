import SwiftUI
import WorkoutCore

/*
 * Settings → Safety copies: the plan as it was at the start of each day, kept
 * for 30 days, each with a way to put it back.
 */
struct SafetyCopiesView: View {
    @EnvironmentObject var store: Store
    @State private var asking: String?
    @State private var doneLine: String?
    @State private var problem: String?

    private static func format(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = pattern
        return f
    }
    private static let key = format("yyyy-MM-dd")
    private static let long = format("EEE d MMM yyyy")
    private static let short = format("EEE d MMM")

    private func dayWords(_ day: String, long isLong: Bool) -> String {
        guard let d = Self.key.date(from: day) else { return day }
        return (isLong ? Self.long : Self.short).string(from: d)
    }

    var body: some View {
        ScrollView {
            let days = store.safetyCopyDays
            VStack(alignment: .leading, spacing: 8) {
                Text("The plan as it was at the start of each day, kept for 30 days. Put one back if the plan went wrong.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                if let doneLine {
                    Text(doneLine).font(.callout.weight(.semibold)).foregroundStyle(Theme.today)
                        .accessibilityIdentifier("safety-done")
                }
                if let problem {
                    Text(problem).font(.callout).foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("safety-problem")
                }
                if days.isEmpty {
                    // A copy is filed when the plan is first saved on a day, so the first one
                    // appears the next time the plan changes.
                    Text("No safety copies yet. The first one is made the next time the plan changes.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("safety-none")
                }
                ForEach(days, id: \.self) { day in
                    row(day)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Safety copies").font(.headline).accessibilityIdentifier("safety-title")
            }
        }
        .confirmationDialog("Put this copy back?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), titleVisibility: .visible) {
            Button("Put it back", role: .destructive) {
                if let day = asking { putBack(day) }
                asking = nil
            }
            .accessibilityIdentifier("safety-confirm")
            Button("Cancel", role: .cancel) { asking = nil }
        } message: {
            Text("The plan goes back to how it was at the start of \(asking.map { dayWords($0, long: false) } ?? "that day"). Everything logged or changed since then is taken out of the plan. The plan as it is now is kept aside first.")
        }
    }

    private func putBack(_ day: String) {
        if store.restoreSafetyCopy(day) {
            problem = nil
            doneLine = "The plan is back as it was on \(dayWords(day, long: false))."
        } else {
            doneLine = nil
            problem = store.lastProblem ?? "That safety copy could not be put back. Nothing was changed."
        }
    }

    private func row(_ day: String) -> some View {
        let summary = store.safetyCopySummary(day)
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayWords(day, long: true)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if let s = summary {
                    Text("\(s.sessions) sessions · \(s.done) done · \(s.changes) change\(s.changes == 1 ? "" : "s")")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                } else {
                    Text("Cannot be opened").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 8)
            if summary != nil {
                Button("Put this copy back") { asking = day }
                    .settingsButton(tint: Theme.danger)
                    .accessibilityIdentifier("safety-put-back")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("safety-row")
    }
}
