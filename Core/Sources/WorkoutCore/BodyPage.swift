import Foundation

/*
 * The Body page's words and small sums, kept apart from the screen so a data
 * test can read them. Shown only: nothing here reaches the plan.
 */
public enum BodyPage {
    /* The four tiles, in the order they stand. */
    public enum Instrument: String, CaseIterable, Identifiable, Sendable {
        case sleep, hrv, resting, stress
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .sleep: return "Sleep"
            case .hrv: return "HRV"
            case .resting: return "Resting pulse"
            case .stress: return "Stress"
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

    public static func tile(_ i: Instrument, _ b: BodyDay) -> Tile {
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
        }
    }

    /* One value as a tile's seven days write it. */
    public static func value(_ i: Instrument, _ v: Double) -> String {
        switch i {
        case .sleep: return sleep(v)
        case .hrv: return "\(whole(v)) ms"
        case .resting: return "\(whole(v)) beats"
        case .stress: return "\(whole(v)) average"
        }
    }

    /* The seven days in numbers, newest first. */
    public static func rows(_ i: Instrument, _ b: BodyDay) -> [Row] {
        tile(i, b).days.reversed().map { d in
            Row(day: d.day, value: d.value.flatMap { $0.isFinite ? value(i, $0) : nil })
        }
    }

    /*
     * How tall each day's bar stands, 0.15…1 of the room; nil where there is no
     * reading. Measured from a little under the lowest day, so a pulse of 47
     * and one of 52 do not stand as two equal bars.
     */
    public static func bars(_ days: [BodyDay.DayValue]) -> [Double?] {
        let v = days.compactMap(\.value).filter { $0.isFinite && $0 >= 0 }
        guard let hi = v.max(), let lo = v.min(), hi > 0 else { return days.map { _ in nil } }
        let floor = lo * 0.6
        return days.map { d in
            guard let x = d.value, x.isFinite, x >= 0 else { return nil }
            guard hi > floor else { return 1 }
            return min(1, max(0.15, (x - floor) / (hi - floor)))
        }
    }
}
