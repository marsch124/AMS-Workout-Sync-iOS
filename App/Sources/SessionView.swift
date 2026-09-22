import SwiftUI
import WorkoutCore

struct SessionView: View {
    @EnvironmentObject var store: Store
    let key: String
    @State private var logging = false
    @State private var moving = false
    @State private var askingMissed = false
    @State private var missedNote = ""
    /* The day's workouts in Apple Health that could be this session. */
    @State private var healthMatches: [HealthWorkout] = []
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
                        .accessibilityIdentifier("session-title")

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
                                .accessibilityIdentifier("zone-pill")
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
                        if w.state == .done {
                            // Logged: the session is finished. Missed and Move no
                            // longer apply; a small grey Adjust stays for a typo,
                            // and the Garmin numbers are offered only until they
                            // are in (his answers, 2026-09-21).
                            HStack(spacing: 10) {
                                if !garminIn(w, mapping) && !healthMatches.isEmpty {
                                    Button { logging = true } label: {
                                        HStack(spacing: 5) {
                                            Glyph(name: "icon-heart", size: 13)
                                            Text("Fill from Garmin")
                                        }
                                    }
                                    .settingsButton(tint: Theme.today)
                                    .accessibilityIdentifier("session-fill-from-garmin")
                                }
                                Spacer(minLength: 0)
                                Button("Adjust") { logging = true }
                                    .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.secondary)
                                    .accessibilityIdentifier("session-adjust")
                            }
                        } else {
                            /*
                             * All four on one line, at one size — his screenshot of
                             * 22 September, the green button ringed and an arrow
                             * down to the row beneath it. A full-width button 60
                             * points tall took the whole screen's attention and
                             * left the other three reading as an afterthought.
                             *
                             * It keeps its colour, filled where the others are
                             * outlined, because it is still the one that finishes
                             * the session: same size is what he asked for, not the
                             * same weight. The planned length stays on it — that
                             * number is the promise that nothing is invented, and
                             * it is the whole reason one tap is safe. "Done as
                             * planned" shortens to "Done" only so that all four
                             * fit a 390-point screen without shrinking.
                             */
                            HStack(spacing: 6) {
                                if let planned = Plan.plannedSeconds(w, mapping), planned > 0 {
                                    Button {
                                        store.logAsPlanned(w)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Glyph(name: "icon-check", size: 12)
                                            Text("Done · \(formatDuration(planned))")
                                        }
                                    }
                                    .settingsButton(tint: Theme.today, filled: true)
                                    .accessibilityIdentifier("session-done-as-planned")
                                }
                                Button { logging = true } label: {
                                    HStack(spacing: 5) {
                                        if !healthMatches.isEmpty { Glyph(name: "icon-heart", size: 13) }
                                        Text(w.missed ? "Log it after all" : "Log details")
                                    }
                                }
                                .settingsButton(tint: Theme.today)
                                .accessibilityIdentifier("session-log-details")
                                if !w.missed {
                                    Button("Missed") {
                                        missedNote = ""
                                        askingMissed = true
                                    }
                                    .settingsButton(tint: Theme.danger)
                                    .accessibilityIdentifier("session-missed")
                                }
                                Button("Move") { moving = true }
                                    .settingsButton(tint: Theme.plan)
                                    .accessibilityIdentifier("session-move")
                                Spacer(minLength: 0)
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
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
                    /*
                     * What he wrote sits with what he did, above the pictures —
                     * his arrow, same screenshot. Under the photographs it came
                     * after the strip, the two buttons and the line about where
                     * pictures are kept, which put three unrelated things between
                     * the session's numbers and his own words about them.
                     */
                    if let notes = w.results["notes"]?.text, !notes.isEmpty {
                        // Always in full: without fixedSize the last line of a long
                        // note was cut to "It was ver…" (screen walk, 2026-09-22).
                        Text(notes).font(.body).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                    }

                    PhotoStrip(owner: PhotoOwner(w))
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
            healthMatches = all.filter { sport == "other" || sport == "brick" || $0.sport == sport || (sport == "run" && $0.sport == "walk") }
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

    /*
     * Are the Garmin numbers in? Yes if this phone saw them used in the form,
     * or — so it also holds on a new phone, or after logging in Excel — if the
     * recorded time matches a workout from Health within a minute and, where
     * the watch measured a distance, the recorded distance matches it too.
     */
    private func garminIn(_ w: Workout, _ mapping: Mapping) -> Bool {
        if HealthMark.used(w) { return true }
        guard let seconds = ShareText.actualSeconds(w, mapping) else { return false }
        let minutes = Int((seconds / 60).rounded())
        let km = Self.loggedKm(w, mapping)
        return healthMatches.contains { h in
            guard abs(Int((h.seconds / 60).rounded()) - minutes) <= 1 else { return false }
            guard let metres = h.metres, metres > 0 else { return true }
            guard let km else { return false }
            let watch = metres / 1000
            return abs(km - watch) <= max(0.02, watch * 0.02)
        }
    }

    /* The recorded distance in kilometres: the waiting log first, then the sheet. */
    static func loggedKm(_ w: Workout, _ mapping: Mapping) -> Double? {
        if let p = w.pending {
            guard let raw = p.actualDistance,
                  let v = Double(raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) else { return nil }
            return p.distanceUnit == "m" ? v / 1000 : v
        }
        guard let v = w.results["actualDistance"]?.number else { return nil }
        return mapping.units.distance == "m" ? v / 1000 : v
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
