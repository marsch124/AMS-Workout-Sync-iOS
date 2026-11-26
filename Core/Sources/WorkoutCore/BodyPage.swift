import Foundation

/*
 * The Body page's words and small sums, kept apart from the screen so a data
 * test can read them. Shown only: nothing here reaches the plan.
 */
public enum BodyPage {
    /* The six tiles, in the order they stand (steps and intensity minutes came in 2.8). */
    public enum Instrument: String, CaseIterable, Identifiable, Sendable {
        case sleep, hrv, resting, stress, steps, intensity
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .sleep: return "Sleep"
            case .hrv: return "HRV"
            case .resting: return "Resting pulse"
            case .stress: return "Stress"
            case .steps: return "Steps"
            case .intensity: return "Intensity minutes"
            }
        }
    }

    /* One tile as it is written: the figure right beside its unit, one grey line, seven days. */
    public struct Tile: Equatable {
        public var instrument: Instrument
        public var figure: String
        public var unit: String
        public var note: String
        public var days: [BodyDay.DayValue]
        /* His normal as a band behind the bars, in the bars' own units (HRV and resting pulse only). */
        public var band: ClosedRange<Double>? = nil
    }

    /* One row of a tile's seven days in numbers. A day without a reading has no value. */
    public struct Row: Equatable {
        public var day: String
        public var value: String?
    }

    public static func whole(_ v: Double) -> String { v.isFinite ? "\(Int(v.rounded()))" : "–" }

    /* Hours of sleep as every other length of time in the app: "6h 10m". */
    public static func sleep(_ hours: Double) -> String {
        guard hours.isFinite, hours >= 0 else { return "–" }
        return formatDuration((hours * 60).rounded() * 60)
    }

    /* A workout's short word above the curve: Garmin's own names are too long for it. */
    public static func shortName(type: String, name: String) -> String {
        let t = type.lowercased()
        if t.contains("swim") { return "Swim" }
        if t.contains("run") { return "Run" }
        if t.contains("cycl") || t.contains("bik") || t.contains("ride") { return "Ride" }
        if t.contains("strength") { return "Strength" }
        if t.contains("hik") { return "Hike" }
        if t.contains("walk") { return "Walk" }
        if t.contains("yoga") { return "Yoga" }
        if t.contains("row") { return "Row" }
        if t.contains("breath") { return "Breathing" }
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Workout" : first
    }

    /* "Run −18"; the name alone when Garmin gives no cost. */
    public static func label(_ w: BodyDay.Workout) -> String {
        let n = shortName(type: w.type, name: w.name)
        guard let d = w.drain, d.isFinite, d.rounded() > 0 else { return n }
        return "\(n) −\(whole(d))"
    }

    /* "2 workouts took 27": only the workouts whose cost is known are counted. */
    public static func workoutsLine(_ b: BodyDay.Battery) -> String? {
        let costs = b.workouts.compactMap(\.drain).filter { $0.isFinite && $0.rounded() > 0 }
        guard !costs.isEmpty else { return nil }
        return "\(costs.count) workout\(costs.count == 1 ? "" : "s") took \(whole(costs.reduce(0, +)))"
    }

    /* The average of the days that have a reading; a day without one is left out, never counted as 0. */
    public static func average(_ days: [BodyDay.DayValue]) -> Double? {
        let v = days.compactMap(\.value).filter(\.isFinite)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    /*
     * One tile for the chosen span. The seven-day span is the tile as it
     * always was; four and twelve weeks swap the bars for weekly averages
     * of the days held (the figure stays today's or last night's) and the
     * grey line for the span's average.
     */
    public static func tile(_ i: Instrument, _ b: BodyDay, span: Span = .week, history: BodyHistory = BodyHistory()) -> Tile {
        var t = sevenDayTile(i, b)
        switch i {
        case .hrv:
            if let lo = b.hrv?.rangeLow, let hi = b.hrv?.rangeHigh, lo <= hi { t.band = Double(lo)...Double(hi) }
        case .resting:
            if let n = b.resting?.normal, n > 0 { t.band = (n * 0.96)...(n * 1.04) }
        default: break
        }
        guard let weeks = span.weeks else { return t }
        var h = history
        h.absorb(b)
        let values = h.values(i)
        t.days = weekly(values, weeks: weeks, endingOn: b.day)
        t.note = spanAverage(values, weeks: weeks, endingOn: b.day).map { "\(weeks)-week average \(plain(i, $0))" } ?? "no \(weeks) weeks yet"
        return t
    }

    /* A value written alone (no unit word that would repeat): "6h 50m", "61 ms", "8,400". */
    public static func plain(_ i: Instrument, _ v: Double) -> String {
        switch i {
        case .sleep: return sleep(v)
        case .hrv: return "\(whole(v)) ms"
        case .resting: return "\(whole(v)) beats"
        case .stress: return whole(v)
        case .steps: return grouped(v)
        case .intensity: return "\(whole(v)) a day"
        }
    }

    static func sevenDayTile(_ i: Instrument, _ b: BodyDay) -> Tile {
        switch i {
        case .sleep:
            let s = b.sleep
            return Tile(instrument: i, figure: s?.lastNight.map(sleep) ?? "–", unit: "",
                        note: average(s?.nights ?? []).map { "7-night average \(sleep($0))" } ?? "no nights yet",
                        days: s?.nights ?? [])
        case .hrv:
            let h = b.hrv
            var note = ""
            if let lo = h?.rangeLow, let hi = h?.rangeHigh { note = "your normal \(lo)–\(hi)" }
            else if h?.stillLearning == true || h?.lastNight != nil { note = "still learning your normal" }
            return Tile(instrument: i, figure: h?.lastNight.map(whole) ?? "–", unit: h?.lastNight == nil ? "" : "ms",
                        note: note, days: h?.days ?? [])
        case .resting:
            let r = b.resting
            return Tile(instrument: i, figure: r?.today.map(whole) ?? "–", unit: r?.today == nil ? "" : "beats",
                        note: r?.normal.map { "your normal \(whole($0))" } ?? "", days: r?.days ?? [])
        case .stress:
            let s = b.stress
            return Tile(instrument: i, figure: s?.average.map(whole) ?? "–", unit: s?.average == nil ? "" : "average",
                        note: s?.highest.map { "highest today \(whole($0))" } ?? "", days: s?.days ?? [])
        case .steps:
            let s = b.steps
            return Tile(instrument: i, figure: s?.today.map(grouped) ?? "–", unit: s?.today == nil ? "" : "steps",
                        note: average(s?.days ?? []).map { "7-day average \(grouped($0))" } ?? "", days: s?.days ?? [])
        case .intensity:
            let n = b.intensity
            let hasGoal = (n?.goal ?? 0) > 0
            let unit = n?.weekTotal == nil ? "" : (hasGoal ? "of \(whole(n?.goal ?? 0))" : "this week")
            let note = n?.weekTotal == nil ? "" : "moderate \(whole(n?.moderate ?? 0)) · vigorous \(whole(n?.vigorous ?? 0))"
            return Tile(instrument: i, figure: n?.weekTotal.map(whole) ?? "–", unit: unit, note: note, days: n?.days ?? [])
        }
    }

    /* One value as a tile's seven days write it. */
    public static func value(_ i: Instrument, _ v: Double) -> String {
        switch i {
        case .sleep: return sleep(v)
        case .hrv: return "\(whole(v)) ms"
        case .resting: return "\(whole(v)) beats"
        case .stress: return "\(whole(v)) average"
        case .steps: return "\(grouped(v)) steps"
        case .intensity: return "\(whole(v)) min"
        }
    }

    /* The seven days in numbers, newest first. */
    public static func rows(_ i: Instrument, _ b: BodyDay, span: Span = .week, history: BodyHistory = BodyHistory()) -> [Row] {
        tile(i, b, span: span, history: history).days.reversed().map { d in
            // A week's row is its average; the days' rows are the day's own number.
            Row(day: d.day, value: d.value.flatMap { $0.isFinite ? (span == .week ? value(i, $0) : plain(i, $0)) : nil })
        }
    }

    /*
     * How tall each day's bar stands, 0.15…1 of the room; nil where there is no
     * reading. Measured from a little under the lowest day, so a pulse of 47
     * and one of 52 do not stand as two equal bars.
     */
    public static func bars(_ days: [BodyDay.DayValue]) -> [Double?] { bars(days, band: nil).heights }

    /*
     * The same, with his normal as a band behind the bars: the scale takes the
     * band in, so each bar reads against it. The band comes back as its low
     * and high as fractions of the room (0…1), nil when there is none or no
     * bar to stand against it.
     */
    public static func bars(_ days: [BodyDay.DayValue], band: ClosedRange<Double>?) -> (heights: [Double?], band: ClosedRange<Double>?) {
        let v = days.compactMap(\.value).filter { $0.isFinite && $0 >= 0 }
        guard let vhi = v.max(), let vlo = v.min() else { return (days.map { _ in nil }, nil) }
        let b = band.flatMap { $0.lowerBound.isFinite && $0.upperBound.isFinite && $0.lowerBound >= 0 ? $0 : nil }
        let hi = max(vhi, b?.upperBound ?? vhi), lo = min(vlo, b?.lowerBound ?? vlo)
        let heights: [Double?]
        guard hi > 0 else {
            // Only zeros (a quiet week of intensity minutes): a short bar each, not a dash.
            return (days.map { d in (d.value.map { $0.isFinite && $0 >= 0 } ?? false) ? 0.15 : nil }, nil)
        }
        let floor = lo * 0.6
        func f(_ x: Double) -> Double { hi > floor ? min(1, max(0, (x - floor) / (hi - floor))) : 1 }
        heights = days.map { d in
            guard let x = d.value, x.isFinite, x >= 0 else { return nil }
            guard hi > floor else { return 1 }
            return min(1, max(0.15, (x - floor) / (hi - floor)))
        }
        return (heights, b.map { f($0.lowerBound)...f($0.upperBound) })
    }
}
