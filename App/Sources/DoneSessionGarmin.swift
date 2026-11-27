import SwiftUI
import MapKit
import WorkoutCore

/*
 * What a done session's page shows from the watch: the route, the pulse
 * curve, the laps, and the card that sets this session beside the last one
 * of the same kind. Plus the Progress card with the week's time in zones.
 * Everything is shown only; no key or no answer leaves a part out, and no
 * pace is ever worked out here — a lap shows Garmin's own speed and power.
 */
struct DoneSessionGarmin: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var reader = GarminActivityReader.shared
    let workout: Workout
    let mapping: Mapping

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let d = reader.detail(for: workout.key), !d.recording.isEmpty || d.avgHr != nil {
                WatchSection(workout: workout, detail: d)
            }
            if let last = lastTime { LastTimeCard(card: last) }
        }
        .task(id: workout.key) {
            await reader.load(key: workout.key, day: workout.dayKey, sport: workout.discipline.id,
                              seconds: Stats.actualSeconds(workout, mapping))
        }
    }

    /* The most recent earlier done session of the same kind, if there is one. */
    private var lastTime: LastTimeCard.Card? {
        func entry(_ w: Workout) -> LastTime.Entry {
            LastTime.Entry(key: w.key, dayKey: w.dayKey, sport: w.discipline.id, title: w.title, row: w.row, done: w.logged && !w.missed)
        }
        let all = store.displayed
        let nowFigures = figures(workout)
        if let prev = LastTime.previous(of: entry(workout), among: all.map(entry)), let w = all.first(where: { $0.key == prev.key }) {
            let rows = LastTime.rows(now: nowFigures, last: figures(w))
            return rows.isEmpty ? nil : LastTimeCard.Card(day: w.dayKey, rows: rows)
        }
        #if DEBUG
        if GarminKey.isFake {
            var n = nowFigures
            if n.rpe == 0 { n.rpe = 6 }
            let rows = LastTime.rows(now: n, last: LastTime.Figures(minutes: n.minutes - 4, km: (n.km * 0.94 * 10).rounded() / 10,
                                                                    hr: n.hr + 3, rpe: n.rpe + 1))
            return LastTimeCard.Card(day: GarminMorning.addDays(workout.dayKey, -7), rows: rows)
        }
        #endif
        return nil
    }

    private func figures(_ w: Workout) -> LastTime.Figures {
        let a = Stats.actualsOf(w, mapping)
        return LastTime.Figures(minutes: a.minutes, km: a.km, hr: a.hr, rpe: a.rpe)
    }
}

// MARK: - from your watch

private struct WatchSection: View {
    let workout: Workout
    let detail: GarminActivityDetail
    @State private var allLaps = false

    private var colour: Color { Theme.sport(workout.discipline.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "From your watch")
            if detail.hasMap {
                RouteMap(coords: detail.recording.track.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }, colour: colour)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("watch-route")
            }
            if detail.recording.pulse.count >= 2 { pulseCard }
            if !detail.recording.laps.isEmpty { lapsCard }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-section")
    }

    private var pulseCard: some View {
        let samples = detail.recording.pulse
        let average = detail.avgHr ?? Double(samples.reduce(0, +)) / Double(samples.count)
        let highest = detail.maxHr ?? Double(samples.max() ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            PulseLine(values: samples.map(Double.init)).stroke(colour, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(height: 52)
            (Text("Average ").foregroundStyle(Theme.secondary) + Text("\(Int(average.rounded()))").bold().foregroundStyle(Theme.text)
             + Text(" · Highest ").foregroundStyle(Theme.secondary) + Text("\(Int(highest.rounded()))").bold().foregroundStyle(Theme.text)
             + Text(" beats").foregroundStyle(Theme.secondary))
                .font(.footnote.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-pulse")
    }

    private var lapsCard: some View {
        let laps = detail.recording.laps
        let shown = allLaps ? laps : Array(laps.prefix(12))
        let swim = workout.discipline.id == "swim"
        let showSpeed = !swim && laps.contains { $0.speedMps != nil }
        let showPower = laps.contains { $0.powerW != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Laps").font(.headline).foregroundStyle(Theme.text)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    head("Lap"); head("Distance"); head("Time"); head("Pulse")
                    if showSpeed { head("km/h") }
                    if showPower { head("Watts") }
                }
                ForEach(shown, id: \.number) { lap in
                    GridRow {
                        cell("\(lap.number)", bold: true)
                        cell(lap.metres.map { Self.distance($0, swim: swim) } ?? "—")
                        cell(lap.seconds.map { formatDuration($0) } ?? "—")
                        cell(lap.avgHr.map { "\(Int($0.rounded()))" } ?? "—")
                        if showSpeed { cell(lap.speedMps.map { jsNumberString(($0 * 36).rounded() / 10) } ?? "—") }
                        if showPower { cell(lap.powerW.map { "\(Int($0.rounded()))" } ?? "—") }
                    }
                }
            }
            if laps.count > 12 {
                Button(allLaps ? "Show the first 12 laps" : "Show all \(laps.count) laps") { allLaps.toggle() }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("watch-laps-all")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-laps")
    }

    private func head(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
    }

    private func cell(_ text: String, bold: Bool = false) -> some View {
        Text(text).font(.footnote.monospacedDigit().weight(bold ? .bold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
    }

    static func distance(_ metres: Double, swim: Bool) -> String {
        swim ? "\(Int(metres.rounded())) m" : String(format: "%.2f km", metres / 1000)
    }
}

/* The route as a simple line on a quiet map, not to be moved: it is a picture, not a tool. */
private struct RouteMap: View {
    let coords: [CLLocationCoordinate2D]
    let colour: Color

    var body: some View {
        Map(initialPosition: .rect(Self.rect(coords)), interactionModes: []) {
            // A white edge under the line, so a green run stays clear on a green map and a blue swim on blue water.
            MapPolyline(coordinates: coords).stroke(Color.white, lineWidth: 8)
            MapPolyline(coordinates: coords).stroke(colour, lineWidth: 4.5)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    static func rect(_ c: [CLLocationCoordinate2D]) -> MKMapRect {
        var rect = MKMapRect.null
        for p in c { rect = rect.union(MKMapRect(origin: MKMapPoint(p), size: MKMapSize(width: 0, height: 0))) }
        if rect.isNull { return MKMapRect.world }
        // Room around the line, and never a map of a single street's width.
        let w = max(rect.size.width, 400 * MKMapPointsPerMeterAtLatitude(c[0].latitude))
        let h = max(rect.size.height, 400 * MKMapPointsPerMeterAtLatitude(c[0].latitude))
        return MKMapRect(x: rect.midX - w * 0.7, y: rect.midY - h * 0.7, width: w * 1.4, height: h * 1.4)
    }
}

/* A slim line through the values, from the lowest to the highest the curve reaches. */
private struct PulseLine: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return p }
        let span = max(hi - lo, 1)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: rect.maxY - rect.height * CGFloat((v - lo) / span))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

// MARK: - last time

struct LastTimeCard: View {
    struct Card { let day: String; let rows: [LastTime.Row] }
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last time · \(Dates.short(card.day))").font(.headline).foregroundStyle(Theme.text)
            Text("This session ← last time").font(.caption).foregroundStyle(Theme.secondary)
            ForEach(card.rows, id: \.name) { row in
                HStack(spacing: 8) {
                    Text(row.name).font(.subheadline).foregroundStyle(Theme.secondary).frame(width: 104, alignment: .leading)
                    Text(row.now).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                    Text("←").font(.subheadline).foregroundStyle(Theme.secondary)
                    Text(row.last).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("last-time-card")
    }
}

// MARK: - Progress: time in zones

struct ZonesWeekCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var reader = GarminActivityReader.shared

    /*
     * 2.20: never hidden while a Garmin key is saved (he could not find it, 27 Nov 2026), and the page
     * itself asks Garmin when Progress opens — the old `.task` here sat on an empty Group and never ran.
     */
    var body: some View {
        if let z = reader.zonesShown { card(z) } else if GarminKey.isSaved { waiting }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time in zones · this week").font(.headline).foregroundStyle(Theme.text)
            if reader.zonesFailed && !reader.zonesReading {
                Button { Task { await reader.loadZones(today: store.today, force: true) } } label: {
                    Text("Garmin did not answer just now. Tap to try again.").font(.subheadline).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("zones-failed")
            } else {
                Text(reader.zones == nil || reader.zonesReading ? "Reading your zones…" : "No time in zones yet this week.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("zones-waiting")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zones-card")
    }

    private func words(_ seconds: Double) -> String { formatDuration((seconds / 60).rounded() * 60) }

    /* The plan's own zone words for this week's sessions, if it has any. */
    private var planLine: String? {
        guard let mapping = store.mapping else { return nil }
        let monday = PlanView.weekStart(store.today), next = GarminMorning.addDays(monday, 7)
        let sessions = store.displayed.filter { $0.dayKey >= monday && $0.dayKey < next && !$0.missed && $0.discipline.id != "rest" }
            .map { (intensity: $0.planned.intensity, seconds: Plan.plannedSeconds($0, mapping) ?? 3600) }
        return GarminZoneWeeks.planLine(sessions: sessions)
    }

    private func card(_ z: GarminZoneWeeks.Result) -> some View {
        let biggest = max(z.thisWeek.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Time in zones · this week").font(.headline).foregroundStyle(Theme.text)
            ForEach(0..<5, id: \.self) { i in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Z\(i + 1)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.progress)
                        Text(words(z.thisWeek[i])).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        Text("· last week \(words(z.lastWeek[i]))").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                        Spacer(minLength: 0)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.progress.opacity(0.16))
                            Capsule().fill(Theme.progress).frame(width: max(z.thisWeek[i] > 0 ? 6 : 0, geo.size.width * z.thisWeek[i] / biggest))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("zones-bar-\(i + 1)")
            }
            if let line = planLine {
                Text(line).font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("zones-plan-line")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zones-card")
    }
}
