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
    @State private var summaries: [String: (sessions: Int, done: Int, changes: Int)?] = [:]

    private func readSummaries() {
        var out: [String: (sessions: Int, done: Int, changes: Int)?] = [:]
        for d in store.safetyCopyDays { out[d] = store.safetyCopySummary(d) }
        summaries = out
    }

    /*
     * "2026-11-25-before-0912" is the plan just before a copy was put back at 09:12;
     * "before-merge-2026-11-25-091200-from-mac-took" the plan before a meeting with iCloud took something out;
     * "other-plan-2026-11-25-091200-here" / "-icloud" the plan put aside when he chose one of two.
     */
    private func rowTitle(_ day: String) -> String {
        if day.hasPrefix("before-merge-") || day.hasPrefix("other-plan-") {
            let moment = Store.copyMoment(day)          // yyyy-MM-dd-HHmmss
            let when = dayWords(String(moment.prefix(10)), long: true) + ", "
                + String(moment.dropFirst(11).prefix(2)) + ":" + String(moment.dropFirst(13).prefix(2))
            if day.hasPrefix("other-plan-") {
                return when + (day.hasSuffix("-icloud")
                    ? " \u{2014} the other plan from iCloud, put aside when you kept this one"
                    : " \u{2014} the plan this \(Device.word) had before it took the other one")
            }
            return when + " \u{2014} before \(Self.whose(day)) changes came in"
        }
        guard day.count > 10, day.contains("-before-") else { return dayWords(day, long: true) }
        let time = String(day.suffix(4))
        let hhmm = time.prefix(2) + ":" + time.suffix(2)
        return dayWords(String(day.prefix(10)), long: true) + ", " + hhmm + " \u{2014} just before a copy was put back"
    }

    /* "your Mac's", from "…-from-mac-took". */
    private static func whose(_ id: String) -> String {
        guard let r = id.range(of: "-from-"), id.hasSuffix("-took") else { return "your other devices\u{2019}" }
        switch String(id[r.upperBound...].dropLast(5)) {
        case "mac": return "your Mac\u{2019}s"
        case "ipad": return "your iPad\u{2019}s"
        case "iphone": return "your iPhone\u{2019}s"
        default: return "your other devices\u{2019}"
        }
    }

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
        guard let d = Self.key.date(from: String(day.prefix(10))) else { return day }
        return (isLong ? Self.long : Self.short).string(from: d)
    }

    var body: some View {
        ScrollView {
            let days = store.safetyCopyDays
            VStack(alignment: .leading, spacing: 8) {
                Text("The plan as it was at the start of each day it changed, kept for 30 days. Put one back if the plan went wrong.")
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
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("safety-none")
                }
                ForEach(days, id: \.self) { day in
                    row(day)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            readSummaries()
            store.cloud.takenNoticeSeen()
        }
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
            Text(confirmWords(asking))
        }
    }

    private func confirmWords(_ id: String?) -> String {
        let when = id.map { $0.hasPrefix("before-merge-") || $0.hasPrefix("other-plan-") ? rowTitle($0).components(separatedBy: " \u{2014}").first ?? $0
                                                                                      : dayWords($0, long: false) } ?? "that day"
        if store.planIsShared {
            return "The plan goes back to how it was in this copy: its days, words and lengths, and which sessions are in it \u{2014} on all your devices. What you logged since then stays. The plan as it is now is kept aside first."
        }
        return "The plan goes back to how it was at the start of \(when). Everything logged or changed since then is taken out of the plan. The plan as it is now is kept aside first."
    }

    private func putBack(_ day: String) {
        let ok = store.restoreSafetyCopy(day)
        readSummaries()
        if ok {
            problem = nil
            doneLine = day.hasPrefix("before-merge-") || day.hasPrefix("other-plan-") ? "The plan is back as it was on \(rowTitle(day).components(separatedBy: " \u{2014}").first ?? day)." : day.contains("-before-") ? "The plan is back as it was just before the earlier copy was put back." : "The plan is back as it was at the start of \(dayWords(day, long: false))."
        } else {
            doneLine = nil
            problem = store.lastProblem ?? "That safety copy could not be put back. Nothing was changed."
        }
    }

    private func row(_ day: String) -> some View {
        let summary = summaries[day] ?? nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(rowTitle(day)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            if let s = summary {
                Text("\(s.sessions) sessions \u{00B7} \(s.done) done \u{00B7} \(s.changes) change\(s.changes == 1 ? "" : "s") so far")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                Button("Put this copy back") { asking = day }
                    .settingsButton(tint: Theme.danger)
                    .accessibilityIdentifier("safety-put-back")
            } else {
                Text("Cannot be opened").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("safety-row")
    }
}
