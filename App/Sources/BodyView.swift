import SwiftUI
import WorkoutCore

/*
 * The Body page (his idea, 25 Nov 2026: "a page like the AMS Garmin Board
 * within the app"; his picks: all four instruments, a tab of its own, the
 * full-colour look). A head card filled with Body's colour for Body Battery
 * through the day, then four tiles with their last seven days. Shown only:
 * nothing here reaches the plan, and sleep never leads to a suggestion.
 */
struct BodyView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var reader = GarminReader.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var phase
    /* A tile's seven days; for a picture it can stand open from the start (AMSWS_BODY_PEEK=sleep|hrv|resting|stress, DEBUG only). */
    @State private var peek: BodyPage.Instrument? = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["AMSWS_BODY_PEEK"] { return BodyPage.Instrument(rawValue: name) }
        #endif
        return nil
    }()

    /* A tapped workout's session opens on this page's own stack; its extra or its own facts on a plate (2.7). */
    @State private var path: [String] = []
    @State private var openExtra: ExtraSummary?
    @State private var plate: BodyDay.Workout?

    private var wide: Bool { sizeClass == .regular && UIDevice.current.userInterfaceIdiom != .phone }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 8) {
                    heading
                    if let b = reader.bodyShown {
                        BodyHero(battery: b.battery, day: b.day, tall: wide) { w in open(w, in: b) }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: wide ? 4 : 2), spacing: 8) {
                            ForEach(BodyPage.Instrument.allCases) { i in
                                BodyTile(tile: BodyPage.tile(i, b), tall: wide) { peek = i }
                            }
                        }
                        foot
                    } else if !reader.keySaved {
                        connect
                    } else {
                        empty
                    }
                }
                .padding(.horizontal, wide ? 22 : 12)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await reader.readBody(today: store.today) }
            .background(Theme.bodyGround.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // The session's page looks as it does when opened from Today; only the way back is Body's.
            .navigationDestination(for: String.self) { key in SessionView(key: key).tint(Theme.today) }
        }
        .tint(Theme.body)
        .task { await reader.readBodyIfDue(today: store.today) }
        .onChange(of: phase) { _, now in
            if now == .active { Task { await reader.readBodyIfDue(today: store.today) } }
        }
        .onChange(of: reader.keySaved) { _, saved in
            if saved { Task { await reader.readBodyIfDue(today: store.today) } }
        }
        .sheet(item: $peek) { i in
            if let b = reader.bodyShown { BodyPeek(instrument: i, day: b) }
        }
        .sheet(item: $openExtra) { x in ExtraDetailView(extra: x).environmentObject(store) }
        .sheet(item: $plate) { w in BodyWorkoutPlate(workout: w) }
        #if DEBUG
        .task {
            // For a picture: AMSWS_BODY_WORKOUT=0|1… taps that workout on the curve from the start.
            if let n = ProcessInfo.processInfo.environment["AMSWS_BODY_WORKOUT"].flatMap({ Int($0) }),
               let b = reader.bodyShown, let all = b.battery?.workouts.sorted(by: { $0.start < $1.start }), all.indices.contains(n) {
                open(all[n], in: b)
            }
        }
        #endif
    }

    /* A tap on a workout on the curve only opens a page: the session, the extra, or the workout's own facts. */
    private func open(_ w: BodyDay.Workout, in b: BodyDay) {
        let all = b.battery?.workouts ?? []
        guard let i = all.firstIndex(of: w) else { return }
        let extras = store.allExtras
        switch BodyTap.targets(for: all, day: b.day, sessions: store.displayed, extras: extras)[i] {
        case .session(let key):
            path = [key]
        case .extra(let id):
            if let x = extras.first(where: { $0.id == id }) { openExtra = x } else { plate = w }
        case .facts:
            plate = w
        }
    }

    /* Large and centred, in Body's colour; under it the day and when the numbers were read. */
    private var heading: some View {
        VStack(spacing: 1) {
            Text("Body")
                .font(.largeTitle.weight(.bold)).foregroundStyle(Theme.body)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("body-page")
            if let b = reader.bodyShown {
                Text(reader.readingBody ? "Reading from Garmin…" : "\(Dates.short(b.day)) · read \(GarminWords.time(b.readAt))")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("body-read")
            } else if reader.readingBody {
                Text("Reading from Garmin…").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6).padding(.bottom, 2)
    }

    private var foot: some View {
        Text("Tap a workout or a tile for more.\nFrom your Garmin watch · shown only, it changes no plan.")
            .font(.caption).foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityIdentifier("body-foot")
    }

    /* No key yet: say so, with the one button that helps. */
    private var connect: some View {
        VStack(spacing: 12) {
            Text("Connect your Garmin key to see your body's numbers here.")
                .font(.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            NavigationLink { GarminSettingsView() } label: {
                Text("Open Garmin settings")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bodyFill))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-connect")
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
        .padding(.top, 8)
    }

    /* A key, but nothing to show yet. */
    private var empty: some View {
        Text(reader.readingBody ? "Reading from Garmin…"
             : "No numbers from Garmin yet. Wear the watch, sync it in Garmin Connect, then pull down here.")
            .font(.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: 520)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
            .padding(.top, 8)
            .accessibilityIdentifier("body-empty")
    }
}

/* The head card: Body Battery now, the day's highest, what the workouts took, and the curve. */
struct BodyHero: View {
    let battery: BodyDay.Battery?
    let day: String
    var tall = false
    var onWorkout: (BodyDay.Workout) -> Void = { _ in }

    private var hasYesterday: Bool { (battery?.yesterday?.count ?? 0) > 1 && battery?.now != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("BODY BATTERY").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                // The second line says what it is, right on the card: a piece of the line and its word.
                if hasYesterday {
                    HStack(spacing: 5) {
                        YesterdayLine.sample.frame(width: 20, height: 8)
                        Text("yesterday").font(.caption.weight(.semibold))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("The thin line is yesterday")
                    .accessibilityIdentifier("body-yesterday")
                }
            }
            if let b = battery, let now = b.now {
                // The side figures stand right beside the big one, each next to its own words.
                HStack(alignment: .center, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(BodyPage.whole(now)).font(.largeTitle.weight(.bold))
                        Text("now").font(.subheadline.weight(.semibold))
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if let hi = b.highest { Text("Highest today \(BodyPage.whole(hi))") }
                        if let took = BodyPage.workoutsLine(b) { Text(took) }
                    }
                    .font(.footnote).opacity(0.92)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityIdentifier("body-hero")
                BatteryCurve(battery: b, day: day, onWorkout: onWorkout).frame(height: tall ? 240 : 150)
            } else {
                Text("No Body Battery readings yet today.").font(.subheadline).padding(.vertical, 10)
                    .accessibilityLabel(spoken)
                    .accessibilityIdentifier("body-hero")
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.bodyFill))
        .accessibilityElement(children: .contain)
    }

    private var spoken: String {
        guard let b = battery, let now = b.now else { return "Body Battery: no readings yet today" }
        var s = "Body Battery \(BodyPage.whole(now)) now"
        if let hi = b.highest { s += ", highest today \(BodyPage.whole(hi))" }
        if let took = BodyPage.workoutsLine(b) { s += ", \(took)" }
        for w in b.workouts { s += ", \(BodyPage.label(w))" }
        return s
    }
}

/*
 * How yesterday's line is drawn, in one place for the curve and for its
 * word's sample (his pick from three looks, 25 Nov 2026): a thin dark line,
 * a deep plum. Not pale (pale means still to do) and not dotted or dashed
 * (dotted means an extra).
 */
enum YesterdayLine {
    static let colour = Theme.bodyYesterday
    static let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
    static var sample: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 1, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
            ctx.stroke(p, with: .color(colour), style: stroke)
        }
    }
}

/*
 * Body Battery from midnight to now, white on the card's colour. Each of the
 * day's workouts is a white bar over the curve with its name and cost above
 * it; the white dot is now, and the rest of the day stays empty.
 */
struct BatteryCurve: View {
    let battery: BodyDay.Battery
    let day: String
    var onWorkout: (BodyDay.Workout) -> Void = { _ in }

    private var midnight: Date { Calendar.current.startOfDay(for: GarminMorning.date(day) ?? Date()) }
    /* The room the curve is drawn in: the workouts' words stand above `top`, the hours under `bottom`. */
    private static let left: CGFloat = 2, top: CGFloat = 32
    private static func x(_ d: Date, from midnight: Date, width: CGFloat) -> CGFloat {
        left + (width - 2 - left) * CGFloat(min(max(d.timeIntervalSince(midnight) / 86_400, 0), 1))
    }

    var body: some View {
        curve
            .accessibilityHidden(true)
            .overlay { GeometryReader { geo in taps(in: geo.size) } }
    }

    /*
     * The Canvas cannot be tapped piece by piece, so each workout has a clear
     * button laid over it: the column under its words, a finger wide at least.
     */
    private func taps(in size: CGSize) -> some View {
        let workouts = battery.workouts.sorted { $0.start < $1.start }
        let bars = workouts.map { w -> (lo: Double, hi: Double) in
            let x0 = Self.x(w.start, from: midnight, width: size.width)
            return (Double(x0), Double(max(Self.x(w.end, from: midnight, width: size.width), x0 + 3)))
        }
        let spans = BodyTap.spans(bars: bars, from: 0, to: Double(size.width))
        let height = max(44, size.height - 16)
        return ZStack {
            ForEach(Array(workouts.enumerated()), id: \.offset) { i, w in
                Button { onWorkout(w) } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: CGFloat(spans[i].hi - spans[i].lo), height: height)
                .position(x: CGFloat(spans[i].lo + spans[i].hi) / 2, y: height / 2)
                .accessibilityLabel("\(BodyPage.label(w)), started \(GarminWords.time(w.start)). Opens it.")
                .accessibilityIdentifier("body-workout-\(i)")
            }
        }
    }

    private var curve: some View {
        Canvas { ctx, size in
            let midnight = self.midnight
            let left = Self.left, right = size.width - 2, top = Self.top, bottom = size.height - 16
            func x(_ d: Date) -> CGFloat { Self.x(d, from: midnight, width: size.width) }
            func y(_ v: Double) -> CGFloat { bottom - (bottom - top) * CGFloat(min(max(v, 0), 100) / 100) }
            let white = Color.white

            for v in [0.0, 50, 100] {
                var p = Path()
                p.move(to: CGPoint(x: left, y: y(v)))
                p.addLine(to: CGPoint(x: right, y: y(v)))
                ctx.stroke(p, with: .color(white.opacity(0.22)), lineWidth: 1)
            }

            // The hours along the foot.
            for h in [0, 6, 12, 18, 24] {
                let t = ctx.resolve(Text(String(format: "%02d", h)).font(.caption2).foregroundColor(white.opacity(0.8)))
                let px = left + (right - left) * CGFloat(h) / 24
                let anchor: UnitPoint = h == 0 ? .leading : (h == 24 ? .trailing : .center)
                ctx.draw(t, at: CGPoint(x: px, y: size.height - 6), anchor: anchor)
            }

            // The workouts: a band each, its words above it; two rows so neighbours do not sit on each other.
            var rowEnds: [CGFloat] = [-.infinity, -.infinity]
            for w in battery.workouts.sorted(by: { $0.start < $1.start }) {
                let x0 = x(w.start), x1 = max(x(w.end), x0 + 3)
                // A solid white bar as long as the workout lasted, a thin line down from each end.
                // Not a lighter band: "lighter" already means still to do elsewhere in the app.
                var span = Path()
                span.move(to: CGPoint(x: x0, y: top))
                span.addLine(to: CGPoint(x: x1, y: top))
                ctx.stroke(span, with: .color(white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                for edge in [x0, x1] {
                    var down = Path()
                    down.move(to: CGPoint(x: edge, y: top))
                    down.addLine(to: CGPoint(x: edge, y: bottom))
                    ctx.stroke(down, with: .color(white.opacity(0.55)), lineWidth: 1)
                }
                let t = ctx.resolve(Text(BodyPage.label(w)).font(.caption2.weight(.bold)).foregroundColor(white))
                let width = t.measure(in: size).width
                let cx = min(max((x0 + x1) / 2, left + width / 2), right - width / 2)
                let row = (cx - width / 2 >= rowEnds[1] + 6) ? 1 : ((cx - width / 2 >= rowEnds[0] + 6) ? 0 : 1)
                ctx.draw(t, at: CGPoint(x: cx, y: row == 1 ? top - 10 : top - 23), anchor: .center)
                rowEnds[row] = cx + width / 2
            }

            // Yesterday, behind today: one thin line across the whole 24 hours, nothing filled under it.
            let before = (battery.yesterday ?? []).filter { $0.value.isFinite }.sorted { $0.time < $1.time }
            if before.count > 1, let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: midnight) {
                let span = midnight.timeIntervalSince(dayBefore)
                func xb(_ d: Date) -> CGFloat {
                    left + (right - left) * CGFloat(min(max(d.timeIntervalSince(dayBefore) / span, 0), 1))
                }
                var old = Path()
                old.move(to: CGPoint(x: xb(before[0].time), y: y(before[0].value)))
                for p in before.dropFirst() { old.addLine(to: CGPoint(x: xb(p.time), y: y(p.value))) }
                ctx.stroke(old, with: .color(YesterdayLine.colour), style: YesterdayLine.stroke)
            }

            let pts = battery.points.filter { $0.value.isFinite }.sorted { $0.time < $1.time }
            guard let first = pts.first, let last = pts.last else { return }
            var line = Path()
            line.move(to: CGPoint(x: x(first.time), y: y(first.value)))
            for p in pts.dropFirst() { line.addLine(to: CGPoint(x: x(p.time), y: y(p.value))) }
            var area = line
            area.addLine(to: CGPoint(x: x(last.time), y: bottom))
            area.addLine(to: CGPoint(x: x(first.time), y: bottom))
            area.closeSubpath()
            ctx.fill(area, with: .color(white.opacity(0.2)))
            ctx.stroke(line, with: .color(white), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            let dot = CGPoint(x: x(last.time), y: y(last.value))
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(white))
        }
    }
}

/* One tile: the name in small capitals, the figure beside its unit, one grey line, seven slim bars. */
struct BodyTile: View {
    let tile: BodyPage.Tile
    var tall = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.instrument.title.uppercased())
                    .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.body)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(tile.figure).font(.title2.weight(.bold))
                    if !tile.unit.isEmpty { Text(tile.unit).font(.footnote.weight(.semibold)) }
                }
                .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(tile.note.isEmpty ? " " : tile.note)
                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.75)
                BodyBars(days: tile.days, height: tall ? 58 : 42).padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.instrument.title) \(tile.figure) \(tile.unit). \(tile.note). Opens its 7 days in numbers.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("body-tile-" + tile.instrument.rawValue)
    }
}

/* Seven days as slim round bars with the weekday's letter under each; today is the last, its letter bold and green as today is everywhere. A day without a reading has a small dash, never a zero. */
struct BodyBars: View {
    let days: [BodyDay.DayValue]
    var height: CGFloat = 42

    var body: some View {
        let heights = BodyPage.bars(days)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let today = i == days.count - 1
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: height)
                        if let f = heights[i] {
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(Theme.body)
                                .frame(height: max(4, height * CGFloat(f)))
                        } else {
                            Text("–").font(.caption2).foregroundStyle(Theme.secondary)
                        }
                    }
                    Text(String(Dates.short(d.day).prefix(1)))
                        .font(.caption2.weight(today ? .heavy : .regular))
                        .foregroundStyle(today ? Theme.today : Theme.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/* A tile's seven days in numbers, newest first. */
struct BodyPeek: View {
    let instrument: BodyPage.Instrument
    let day: BodyDay
    @Environment(\.dismiss) private var dismiss

    private var firstWord: String { instrument == .sleep || instrument == .hrv ? "Last night" : "Today" }

    var body: some View {
        let rows = BodyPage.rows(instrument, day)
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    // The figure right beside its day, on the left.
                    HStack(spacing: 10) {
                        Text(i == 0 ? firstWord : Dates.short(row.day))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 112, alignment: .leading)
                        Text(row.value ?? "no reading")
                            .fontWeight(row.value == nil ? .regular : .semibold)
                            .foregroundStyle(row.value == nil ? Theme.secondary : Theme.text)
                        Spacer(minLength: 0)
                    }
                    .font(.body)
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("body-peek-row-\(i)")
                    if i < rows.count - 1 { Divider() }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 6)
            .background(Theme.bodyGround.ignoresSafeArea())
            .navigationTitle(instrument.title + " · last 7 days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("body-peek-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.body)
    }
}

/* A workout the app has no session and no extra for: its own facts from Garmin, and Done. */
struct BodyWorkoutPlate: View {
    let workout: BodyDay.Workout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let rows = BodyTap.facts(workout, time: GarminWords.time)
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    // The figure right beside its name, on the left.
                    HStack(spacing: 10) {
                        Text(row.name).foregroundStyle(Theme.secondary).frame(width: 112, alignment: .leading)
                        Text(row.value).fontWeight(.semibold).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                    }
                    .font(.body)
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("body-workout-row-\(i)")
                    Divider()
                }
                Text("Not in your plan and not among your extras for this day.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .padding(.top, 10)
                    .accessibilityIdentifier("body-workout-plate")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 6)
            .background(Theme.bodyGround.ignoresSafeArea())
            .navigationTitle(BodyTap.title(workout))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("body-workout-done")
                }
            }
        }
        .presentationDetents([.medium])
        .tint(Theme.body)
    }
}
