import SwiftUI
import WorkoutCore

/*
 * The week so far, per sport, under today's card: the sport's mark and name,
 * "done of planned" right beside the name, and one slim round bar. The bar's
 * signs are the app's own: done is the sport's full colour, what is still to
 * do is its pale version. The numbers are the Plan page's "By sport" count
 * (WeekSoFar.sums) plus the extras that count as training, as done time only.
 */
struct WeekSoFarStrip: View {
    let view: PlanView
    let today: String

    var body: some View {
        let sums = WeekSoFar.sums(plan: view.plan, extras: view.extras, mapping: view.mapping, today: today)
        if sums.isEmpty {
            // Nothing planned this week: no room taken either (the page spaces its rows 14 apart).
            Color.clear.frame(height: 0).padding(.top, -14).accessibilityHidden(true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("WEEK SO FAR")
                    .font(.caption.weight(.bold)).tracking(0.8)
                    .foregroundStyle(Theme.today)
                ForEach(sums) { s in row(s) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("week-so-far")
        }
    }

    private func mark(_ id: String) -> String {
        switch id {
        case "swim", "bike", "run", "strength", "mobility": return "icon-" + id
        case "brick": return "icon-bike"
        case "rest": return "icon-rest"
        case "race": return "icon-race"
        default: return "icon-other"
        }
    }

    private func row(_ s: PlanOverview.SportHours) -> some View {
        let share = min(1, s.hours.done / max(s.hours.planned, 1))
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Glyph(name: mark(s.sport), size: 14).foregroundStyle(Theme.sportInk(s.sport))
                Text(s.label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(formatDuration(s.hours.done)) of \(formatDuration(s.hours.planned))")
                    .font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stillToDo(s.sport))
                    Capsule().fill(Theme.sport(s.sport)).frame(width: geo.size.width * share)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("week-so-far-\(s.sport)")
    }
}
