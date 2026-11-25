import SwiftUI
import WorkoutCore

/*
 * Your bests (his pick 33, round 28): the longest ride, run and swim by time
 * (and the distance when it was logged), the biggest week and the longest row
 * of weeks — each with its date. Only from logged sessions. A session's best
 * opens that session's page.
 */
struct PersonalBestsCard: View {
    let plan: [Workout]
    let mapping: Mapping
    let today: String

    var body: some View {
        let bests = PersonalBests.all(plan, mapping, today: today)
        if !bests.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your bests").font(.headline).foregroundStyle(Theme.progress)
                ProgTileGrid {
                    ForEach(bests) { b in
                        if let key = b.key {
                            NavigationLink { SessionView(key: key) } label: { tile(b) }
                                .buttonStyle(.plain)
                        } else {
                            tile(b)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bests-card")
        }
    }

    private func tile(_ b: PersonalBests.Best) -> some View {
        ProgTile(name: b.kind.title, id: "best-\(b.kind.rawValue)") {
            switch b.kind {
            case .ride, .run, .swim:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ProgFigure(figure: formatDuration(b.seconds))
                    if let km = b.km { Text(Self.distance(km, swim: b.kind == .swim)).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text) }
                }
                ProgNote(text: Dates.short(b.dayKey))
                if let f = b.farther { ProgNote(text: "Farthest: \(Self.distance(f.km, swim: b.kind == .swim)), \(Dates.short(f.dayKey))") }
            case .week:
                ProgFigure(figure: formatDuration(b.seconds))
                ProgNote(text: "Week of \(Dates.short(b.dayKey))")
            case .row:
                ProgFigure(figure: "\(b.weeks)", unit: b.weeks == 1 ? "week" : "weeks")
                ProgNote(text: "Ending the week of \(Dates.short(b.dayKey))")
            }
        }
    }

    /* "62.4 km", and a swim in metres: "2,000 m". */
    static func distance(_ km: Double, swim: Bool) -> String {
        swim ? "\(Int((km * 1000).rounded()).formatted(.number.locale(Locale(identifier: "en_GB")))) m" : jsNumberString((km * 10).rounded() / 10) + " km"
    }
}
