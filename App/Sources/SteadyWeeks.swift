import SwiftUI
import WorkoutCore

/*
 * Steady weeks (his pick 36, round 28): how many weeks in a row had the plan
 * followed, as one figure, and the last twelve weeks as twelve small squares.
 * Followed = full purple; not followed = an outlined square (pale is kept for
 * "still to do"); this week has the word "now" under it. "Followed" is the
 * Plan page's own figure at or above SteadyWeeks.threshold per cent.
 */
struct SteadyWeeksCard: View {
    let plan: [Workout]
    let today: String
    /* For a picture: show it even before the plan has a week behind it. */
    var always = false

    var body: some View {
        let squares = SteadyWeeks.squares(plan, today: today)
        let row = SteadyWeeks.row(plan, today: today)
        if always || plan.contains(where: { $0.dayKey < today && $0.discipline.id != "rest" }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Steady weeks").font(.headline).foregroundStyle(Theme.progress)
                ProgTile(name: "Weeks in a row with the plan followed", id: "steady-weeks") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(row)").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
                        Text(row == 1 ? "week" : "weeks").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                    HStack(alignment: .top, spacing: 5) {
                        ForEach(Array(squares.enumerated()), id: \.offset) { i, s in
                            VStack(spacing: 3) {
                                square(s)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Week of \(Dates.short(s.start)), \(s.followed ? "plan followed" : "plan not followed")\(s.isNow ? ", this week" : "")")
                                    .accessibilityIdentifier("steady-square-\(i + 1)")
                                Text(s.isNow ? "now" : " ").font(.caption2.weight(s.isNow ? .bold : .regular))
                                    .foregroundStyle(Theme.progress)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 6)
                    ProgNote(text: "A full square is a week with at least \(SteadyWeeks.threshold) % of its due sessions done, as in Plan followed. An outlined square is a week below that. The last twelve weeks, oldest on the left.")
                        .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder private func square(_ s: SteadyWeeks.Square) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if s.followed {
            shape.fill(Theme.progress).aspectRatio(1, contentMode: .fit)
        } else {
            shape.strokeBorder(Theme.progress, lineWidth: 1.6).aspectRatio(1, contentMode: .fit)
        }
    }
}
