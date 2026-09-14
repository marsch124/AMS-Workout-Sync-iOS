import SwiftUI
import WorkoutCore

struct SessionView: View {
    @EnvironmentObject var store: Store
    let key: String

    var body: some View {
        ScrollView {
            if let w = store.workout(key), let mapping = store.mapping {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        SportBadge(discipline: w.discipline, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.discipline.label.uppercased())
                                .font(.caption.weight(.bold)).tracking(0.6)
                                .foregroundStyle(Theme.sportInk(w.discipline.id))
                            Text(Dates.long(w.dayKey)).font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if w.state == .done { DoneTick() }
                    }

                    Text(w.title).font(.title2.weight(.bold)).foregroundStyle(Theme.text)

                    HStack(spacing: 6) {
                        if let s = Plan.plannedSeconds(w, mapping), s > 0 { Pill(text: formatDuration(s)) }
                        if let d = w.planned.distanceRaw { Pill(text: jsNumberString(d) + " " + mapping.units.distance) }
                        if !w.planned.intensity.isEmpty { Pill(text: w.planned.intensity) }
                        if !w.phase.isEmpty { Pill(text: w.phase) }
                    }

                    ForEach(Array(w.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.label.uppercased()).font(.caption.weight(.bold)).tracking(0.6)
                                .foregroundStyle(Theme.secondary)
                            Text(section.text).font(.body).foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                    }

                    if store.isWaiting(w.key) {
                        Text("Logged on this phone · waiting to sync").font(.headline).foregroundStyle(Theme.today)
                    } else if w.state == .todo, w.discipline.id != "rest", store.canLog,
                              let planned = Plan.plannedSeconds(w, mapping), planned > 0 {
                        Button {
                            store.logAsPlanned(w)
                        } label: {
                            HStack(spacing: 10) {
                                Glyph(name: "icon-check", size: 22)
                                Text("Done as planned · \(formatDuration(planned))")
                            }
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.today)
                    }

                    if w.missed {
                        Text("Marked missed").font(.headline).foregroundStyle(Theme.danger)
                    }

                    let figures = Self.figures(w, mapping)
                    if !figures.isEmpty {
                        SectionHeading(text: "What you did")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(figures, id: \.0) { label, value in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                                    Text(label).font(.caption).foregroundStyle(Theme.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                            }
                        }
                    }
                    if let notes = w.results["notes"]?.text, !notes.isEmpty {
                        Text(notes).font(.body).foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                    }
                }
                .padding(16)
            } else {
                Text("This session is no longer in the plan.").foregroundStyle(Theme.secondary).padding(32)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    /* The recorded numbers, each in its own unit, only where the sheet holds one. */
    static func figures(_ w: Workout, _ mapping: Mapping) -> [(String, String)] {
        var out: [(String, String)] = []
        if let d = w.results["actualDuration"] {
            let seconds = d.number.flatMap { durationFromCell($0, mapping.units.duration) }
            out.append(("Duration", seconds.map(formatDuration) ?? d.text))
        }
        if let d = w.results["actualDistance"] { out.append(("Distance", d.text + " " + mapping.units.distance)) }
        if let p = w.results["avgPace"] {
            let label = w.discipline.id == "bike" ? "Speed" : (w.discipline.id == "swim" ? "Pace /100 m" : "Pace /km")
            out.append((label, p.text))
        }
        if let h = w.results["avgHr"] { out.append(("Heart rate", h.text + " bpm")) }
        if let h = w.results["maxHr"] { out.append(("Max heart rate", h.text + " bpm")) }
        if let e = w.results["rpe"] { out.append(("Effort", e.text + " / 10")) }
        return out
    }
}
