import SwiftUI
import WorkoutCore

/*
 * Round 30 (race-plan lane): three additions to the Race page, each its own
 * colour (the race's red stays the page's own): the race-day forecast (indigo),
 * where he would gain most (orange), and a page of course pacing. Never "you
 * will": the words say "likely". Nothing here reaches the plan.
 *
 * Signs added: the colour of a course section tells its kind and always stands
 * beside its word (Flat blue, Rolling indigo, Climb orange, Downhill purple,
 * Turns amber). No other new sign.
 */
enum RaceplanHue {
    static let forecast = BodyHue.sleep                  // indigo
    static let gap = BodyHue.gym                         // orange
    static func kind(_ k: CourseKind) -> BodyHue {
        switch k {
        case .flat: return BodyHue.intensity             // blue
        case .rolling: return BodyHue.sleep              // indigo
        case .climb: return BodyHue.gym                  // orange
        case .descent: return BodyHue.weight             // purple
        case .turns: return BodyHue.stress               // amber
        }
    }
}

/* What the cards and the page work from, in one place. */
@MainActor
struct RaceplanInputs {
    let course: RaceCourse
    let basis: ForecastBasis
    let ftp: Double?
    let days: Int

    init(store: Store, race: RaceInfo, reader: RaceplanReader) {
        days = Stats.daysBetween(store.today, race.day)
        if RaceplanReader.fake {
            course = RaceplanReader.inventedCourse; basis = RaceplanReader.inventedBasis(); ftp = RaceplanReader.inventedFtp
        } else {
            let now = ZoneMaths.current(store.tests)
            course = RaceCourse.forRace(title: race.title)
            basis = ForecastBasis(css: now.css, lthr: now.lthr ?? store.zones?.lthr, efforts: reader.efforts)
            ftp = now.ftp
        }
    }
}

struct RaceplanSection: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var reader = RaceplanReader.shared
    let race: RaceInfo

    @State private var pacing: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_RACEPLAN_OPEN"] == "pacing"
        #else
        return false
        #endif
    }()
    @State private var pickingAge: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_RACEPLAN_OPEN"] == "agegroup"
        #else
        return false
        #endif
    }()

    private var inputs: RaceplanInputs { RaceplanInputs(store: store, race: race, reader: reader) }

    /* This week's snapshot when there is one (the numbers change once a week), else worked out now. */
    private func forecast(_ i: RaceplanInputs) -> RaceForecast {
        if !RaceplanReader.fake, let kept = shelf.value(RaceForecast.self, for: ForecastShelf.key(store.today)) { return kept }
        return RaceForecastRules.make(i.basis, course: i.course, days: i.days, today: store.today)
    }

    private func snapshots(_ f: RaceForecast) -> [RaceForecast] {
        if RaceplanReader.fake { return Self.invented(f) }
        var all = shelf.keys(prefix: ForecastShelf.prefix).compactMap { shelf.value(RaceForecast.self, for: $0) }
        if !all.contains(where: { $0.workedOut == f.workedOut }) { all.append(f) }
        return all
    }

    /* Six invented weeks: the middle came down a little each week. */
    private static func invented(_ now: RaceForecast) -> [RaceForecast] {
        guard let t = now.total else { return [] }
        return (0..<6).map { n in
            var f = now
            f.workedOut = PlanView.addDays(now.workedOut, -7 * (5 - n))
            let mid = t.mid + (5 - n) * 240 - (n % 2) * 120
            f.total = LegRange(low: mid - 900, mid: mid, high: mid + 900)
            return f
        }
    }

    private var bracket: (AgeBracket, typed: Bool)? {
        if RaceplanReader.fake { return (AgeBracket(lo: 45, hi: 49), false) }
        if let c = shelf.value(AgeGroupChoice.self, for: ForecastShelf.ageGroupKey), let b = AgeBracket.from(label: c.label) { return (b, true) }
        return reader.garminBracket.map { ($0, false) }
    }

    var body: some View {
        let i = inputs
        let f = forecast(i)
        VStack(alignment: .leading, spacing: 10) {
            forecastCard(f, i)
            gapCard(f, i)
            NavigationLink { CoursePacingPage(race: race) } label: {
                Text("Course pacing").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .background(Capsule().fill(Theme.plan))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("race-pacing-open")
            Text("Your bike and run, section by section, with a pulse and power for each.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
        .task { await reader.readIfDue(today: store.today, raceDay: race.day) }
        .task(id: f.total?.mid) { keep(f) }
        .navigationDestination(isPresented: $pacing) { CoursePacingPage(race: race) }
        .sheet(isPresented: $pickingAge) { RaceAgeGroupEdit() }
    }

    /* One snapshot a week on the shelf, once every part could be worked out. */
    private func keep(_ f: RaceForecast) {
        guard !RaceplanReader.fake, f.total != nil, !shelf.has(ForecastShelf.key(store.today)) else { return }
        shelf.set(f, for: ForecastShelf.key(store.today))
    }

    // MARK: pick 10 · race-day forecast

    private func forecastCard(_ f: RaceForecast, _ i: RaceplanInputs) -> some View {
        let hue = RaceplanHue.forecast
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RACE-DAY FORECAST").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                if let t = f.total {
                    Text(RaceForecastRules.words(t)).font(.title.weight(.bold)).foregroundStyle(.white)
                        .accessibilityIdentifier("race-forecast-total")
                    Text("Your likely finish time, from your fitness, the course and July weather.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.9))
                } else {
                    Text("Not enough yet").font(.title2.weight(.bold)).foregroundStyle(.white)
                        .accessibilityIdentifier("race-forecast-total")
                    Text(missingWords(f, i)).font(.footnote).foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hue.accent.deepHead))
            .environment(\.colorScheme, .dark)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(RaceLeg.allCases, id: \.self) { leg in legTile(leg, f, hue) }
            }
            let trend = ForecastTrend.rows(snapshots(f))
            if trend.count > 1 { trendRow(trend, hue) }
            Text("Narrows as the race gets closer \u{00B7} worked out \(Dates.short(f.workedOut))")
                .font(.caption).foregroundStyle(Theme.secondary)
                .accessibilityIdentifier("race-forecast-note")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-forecast")
    }

    private func missingWords(_ f: RaceForecast, _ i: RaceplanInputs) -> String {
        var needs: [String] = []
        if f.leg(.swim) == nil { needs.append("a swim test") }
        if f.leg(.bike) == nil { needs.append("a few steady rides from Garmin") }
        if f.leg(.run) == nil { needs.append("a few steady runs from Garmin") }
        return "Needs " + needs.joined(separator: ", ") + " to work out a likely time."
    }

    private func legTile(_ leg: RaceLeg, _ f: RaceForecast, _ hue: BodyHue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(leg.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(hue.accent)
            if let r = f.leg(leg) {
                Text(RaceForecastRules.words(r, changeOver: leg.isChangeOver)).font(.headline).foregroundStyle(Theme.text)
                Text("likely").font(.caption).foregroundStyle(Theme.secondary)
            } else {
                Text("Not yet").font(.subheadline).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-forecast-" + leg.rawValue)
    }

    private func trendRow(_ rows: [ForecastTrendRow], _ hue: BodyHue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THE MIDDLE, WEEK BY WEEK").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(hue.accent)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(rows, id: \.workedOut) { r in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3).fill(hue.accent).frame(height: 36 * r.fraction)
                        Text(formatDuration(Double(r.mid))).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 56, alignment: .bottom)
            Text("Oldest on the left. A taller bar is a longer likely time.").font(.caption2).foregroundStyle(Theme.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-forecast-trend")
    }

    // MARK: pick 19 · where you lose most time

    private func gapCard(_ f: RaceForecast, _ i: RaceplanInputs) -> some View {
        let hue = RaceplanHue.gap
        let comparison = bracket.flatMap { RaceComparison.make(f, course: i.course, bracket: $0.0) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("WHERE YOU WOULD GAIN MOST").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(hue.accent)
            if let c = comparison {
                ForEach(c.gaps, id: \.leg) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.line(g)).font(.subheadline.weight(c.biggest == g.leg ? .bold : .regular)).foregroundStyle(Theme.text)
                        gapBar(g, c, hue)
                        Text(c.topLine(g)).font(.caption).foregroundStyle(Theme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("race-gap-" + g.leg.rawValue)
                }
                Text("Your likely time for each part against past finishers of this course in your age group.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            } else if bracket == nil {
                Text("Choose your age group to see how your likely times sit against past finishers.")
                    .font(.subheadline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("race-gap-needs-age")
            } else if f.total == nil {
                Text("This appears once your likely time is worked out for every part.")
                    .font(.subheadline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("race-gap-needs-forecast")
            } else {
                Text("No past results for this course and age group yet.")
                    .font(.subheadline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("race-gap-none")
            }
            HStack(spacing: 8) {
                if let b = bracket {
                    Text("Age group \(b.0.label)").font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("race-agegroup")
                    Text(b.typed ? "chosen by you" : "from Garmin").font(.caption).foregroundStyle(Theme.secondary)
                }
                Button { pickingAge = true } label: {
                    Text(bracket == nil ? "Choose age group" : "Change").font(.caption.weight(.semibold)).foregroundStyle(hue.accent)
                        .padding(.horizontal, 10).frame(minHeight: 28)
                        .background(Capsule().stroke(hue.accent.opacity(0.6), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("race-agegroup-change")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-gap")
        .id("race-gap-card")
    }

    /* A slim bar: how far behind the middle, against the biggest gap; nothing when level or ahead. */
    private func gapBar(_ g: LegGap, _ c: RaceComparison, _ hue: BodyHue) -> some View {
        let biggest = Double(max(60, c.gaps.map(\.behindMiddle).max() ?? 60))
        let frac = max(0, min(1, Double(g.behindMiddle) / biggest))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(hue.accent.opacity(0.18))
                Capsule().fill(hue.accent).frame(width: geo.size.width * frac)
            }
        }
        .frame(height: 6)
    }
}

/* Age group: Cancel and Save, Escape is Cancel. "From Garmin" clears his own pick. */
struct RaceAgeGroupEdit: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var pick = ""

    private static let fromGarmin = "From Garmin"

    var body: some View {
        NavigationStack {
            Form {
                Picker("Age group", selection: $pick) {
                    Text(Self.fromGarmin).tag(Self.fromGarmin)
                    ForEach(AgeBracket.all, id: \.label) { Text($0.label).tag($0.label) }
                }
                .accessibilityIdentifier("race-agegroup-picker")
                Text("Past results are cut into five-year age groups. Garmin gives your age; pick one here if it does not fit.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            .navigationTitle("Age group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("race-agegroup-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if pick == Self.fromGarmin { shelf.remove(for: ForecastShelf.ageGroupKey) }
                        else { shelf.set(AgeGroupChoice(label: pick), for: ForecastShelf.ageGroupKey) }
                        dismiss()
                    }
                    .accessibilityIdentifier("race-agegroup-save")
                }
            }
        }
        .onAppear { pick = shelf.value(AgeGroupChoice.self, for: ForecastShelf.ageGroupKey)?.label ?? Self.fromGarmin }
    }
}

// MARK: - pick 11 · course pacing

struct CoursePacingPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var reader = RaceplanReader.shared
    let race: RaceInfo

    var body: some View {
        let i = RaceplanInputs(store: store, race: race, reader: reader)
        let lthr = i.basis.lthr
        let runPower = RaceForecastRules.steady(i.basis.efforts, family: "run", lthr: lthr ?? 0).isEmpty ? nil
            : RaceForecastRules.medianPower(RaceForecastRules.steady(i.basis.efforts, family: "run", lthr: lthr ?? 0))
        let bike = RaceSectionRules.bike(i.course, lthr: lthr, ftp: i.ftp)
        let run = RaceSectionRules.run(i.course, lthr: lthr, runPowerW: runPower)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Course pacing").font(.largeTitle.weight(.bold)).foregroundStyle(RaceLook.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(i.course.name)
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                if lthr == nil {
                    Text("Your pulse targets appear once a test gives your threshold pulse.")
                        .font(.subheadline).foregroundStyle(Theme.text).accessibilityIdentifier("race-pacing-needs-test")
                }
                part("BIKE", total: i.course.bikeKm, unit: "km", targets: bike, hue: BodyHue.intensity, id: "bike", powerWord: "power")
                part("RUN", total: i.course.runKm, unit: "km", targets: run, hue: BodyHue.resting, id: "run", powerWord: "foot-pod power")
                if runPower == nil {
                    Text("Run power appears once your steady runs carry foot-pod power.").font(.caption).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("race-pacing-no-runpower")
                }
                legend(i.course)
                if i.course.sectionsApproximate {
                    Text("Sections are approximate.").font(.caption).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("race-pacing-approximate")
                }
                Text("Targets come from your latest test and your steady sessions, so they move when those do. Easier on climbs, steady on the flat.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12).padding(.bottom, 16).padding(.top, 6)
            .frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .background(RaceLook.ground.ignoresSafeArea())
        .navigationTitle("Course pacing")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-pacing-page")
    }

    private func part(_ name: String, total: Double, unit: String, targets: [PacingTarget], hue: BodyHue, id: String, powerWord: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                    Text("\(formatKm(total)) \(unit)").font(.title2.weight(.bold)).foregroundStyle(.white)
                }
                // The whole course in one bar: each section as long as its km, in its own colour.
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(targets) { t in
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.92))
                                .overlay(RoundedRectangle(cornerRadius: 3).fill(RaceplanHue.kind(t.section.kind).accent.opacity(0.85)))
                                .frame(width: max(3, (geo.size.width - 2 * CGFloat(targets.count - 1)) * t.section.lengthKm / max(1, total)))
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hue.accent.deepHead))
            .environment(\.colorScheme, .dark)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8, alignment: .top)], spacing: 8) {
                ForEach(Array(targets.enumerated()), id: \.element.id) { n, t in row(t, total: total, powerWord: powerWord, id: "\(id)-\(n)") }
            }
        }
    }

    private func row(_ t: PacingTarget, total: Double, powerWord: String, id: String) -> some View {
        let h = RaceplanHue.kind(t.section.kind)
        let s = t.section
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(formatKm(s.fromKm))\u{2013}\(formatKm(s.toKm)) km").font(.headline).foregroundStyle(Theme.text)
                Text(s.kind.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(h.accent)
            }
            if !s.note.isEmpty { Text(s.note).font(.caption).foregroundStyle(Theme.secondary) }
            Text(t.effort).font(.footnote).foregroundStyle(Theme.text)
            HStack(spacing: 14) {
                if let lo = t.pulseLow, let hi = t.pulseHigh {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(lo)\u{2013}\(hi)").font(.body.weight(.bold)).foregroundStyle(Theme.text)
                        Text("bpm").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                if let lo = t.powerLow, let hi = t.powerHigh {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(hi <= lo ? "up to \(hi)" : "\(lo)\u{2013}\(hi)").font(.body.weight(.bold)).foregroundStyle(Theme.text)
                        Text("W").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
            // A slim bar as long as the section's km, of the whole course.
            GeometryReader { geo in
                Capsule().fill(h.accent).frame(width: max(6, geo.size.width * s.lengthKm / max(1, total)))
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(h.tile))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-pacing-" + id)
    }

    private func legend(_ c: RaceCourse) -> some View {
        let kinds = Array(Set((c.bike + c.run).map(\.kind))).sorted { $0.rawValue < $1.rawValue }
        return HStack(spacing: 10) {
            ForEach(kinds, id: \.rawValue) { k in
                HStack(spacing: 4) {
                    Circle().fill(RaceplanHue.kind(k).accent).frame(width: 8, height: 8)
                    Text(k.word).font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-pacing-legend")
    }

    private func formatKm(_ km: Double) -> String { km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km) }
}
