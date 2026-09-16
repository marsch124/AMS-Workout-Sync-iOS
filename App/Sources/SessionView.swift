import SwiftUI
import WorkoutCore

struct SessionView: View {
    @EnvironmentObject var store: Store
    let key: String
    @State private var logging = false
    @State private var moving = false
    @State private var askingMissed = false
    @State private var missedNote = ""
    @State private var fromHealth = 0
    @State private var zoneAsk: ZoneAsk?
    @State private var sharing = false
    @State private var payload: SharePayload?

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
                        if !w.planned.intensity.isEmpty {
                            if store.zones != nil {
                                // What Z2 means for him this season — the zones sheet, one tap away.
                                Button { zoneAsk = ZoneAsk(intensity: w.planned.intensity, sport: w.discipline.id) } label: {
                                    ZonePill(text: w.planned.intensity, sport: w.discipline.id)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Pill(text: w.planned.intensity)
                            }
                        }
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

                    if let label = w.waitingLabel {
                        Text("Logged on this phone · " + label.lowercased()).font(.headline).foregroundStyle(Theme.today)
                    }
                    if store.canLog, w.discipline.id != "rest" {
                        VStack(spacing: 10) {
                            if !w.logged || w.missed, let planned = Plan.plannedSeconds(w, mapping), planned > 0 {
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
                            Button {
                                logging = true
                            } label: {
                                HStack(spacing: 8) {
                                    Text(w.logged && !w.missed ? "Adjust logged data" : "Log details")
                                    if fromHealth > 0 {
                                        // Health has this day's workout: the numbers are one tap away inside.
                                        Glyph(name: "icon-heart", size: 18)
                                        Text("Garmin").font(.subheadline.weight(.semibold))
                                    }
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.today)
                            HStack(spacing: 10) {
                                if !w.missed {
                                    Button {
                                        missedNote = ""
                                        askingMissed = true
                                    } label: {
                                        Text("Missed").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.danger)
                                }
                                Button {
                                    moving = true
                                } label: {
                                    Text("Move").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.plan)
                            }
                        }
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
                    PhotoStrip(owner: PhotoOwner(w))

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.workout(key) != nil {
                    Button { sharing = true } label: { Glyph(name: "icon-share", size: 22) }
                        .accessibilityLabel("Send it to somebody")
                }
            }
        }
        .confirmationDialog("Send it to somebody", isPresented: $sharing, titleVisibility: .visible) {
            if let w = store.workout(key), let mapping = store.mapping {
                if w.state == .done {
                    Button("Send what you did") {
                        payload = SharePayload(items: [ShareText.done(w, mapping, today: store.today)] + ShareText.photos(w))
                    }
                }
                Button("Send the whole session") {
                    payload = SharePayload(items: [ShareText.session(w, mapping)] + ShareText.photos(w))
                }
            }
        }
        .sheet(item: $payload) { p in ActivitySheet(items: p.items) }
        .sheet(item: $zoneAsk) { ask in ZoneSheet(ask: ask).environmentObject(store) }
        .task(id: key) {
            guard let w = store.workout(key),
                  HealthImport.shared.inUse || ProcessInfo.processInfo.environment["AMSWS_FAKE_HEALTH"] != nil else { return }
            let all = await HealthImport.shared.workouts(on: w.dayKey)
            let sport = w.discipline.id
            fromHealth = all.filter { sport == "other" || sport == "brick" || $0.sport == sport || (sport == "run" && $0.sport == "walk") }.count
        }
        .sheet(isPresented: $logging) {
            if let w = store.workout(key), let mapping = store.mapping {
                LogFormView(workout: w, mapping: mapping).environmentObject(store)
            }
        }
        .sheet(isPresented: $moving) {
            if let w = store.workout(key) {
                MoveView(workout: w).environmentObject(store)
            }
        }
        .alert("Mark this session as missed?", isPresented: $askingMissed) {
            TextField("Why? (optional)", text: $missedNote)
            Button("Mark missed", role: .destructive) {
                if let w = store.workout(key) { store.markMissed(w, note: missedNote) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the missed marker and your note are written. Nothing else in the row changes, and you can still log it later if you did it after all.")
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["AMSWS_LOGFORM"] != nil { logging = true }
            if ProcessInfo.processInfo.environment["AMSWS_MOVE"] != nil { moving = true }
            if ProcessInfo.processInfo.environment["AMSWS_ZONE"] != nil, let w = store.workout(key) { zoneAsk = ZoneAsk(intensity: w.planned.intensity, sport: w.discipline.id) }
            if ProcessInfo.processInfo.environment["AMSWS_SHARE"] != nil { sharing = true }
        }
        #endif
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
