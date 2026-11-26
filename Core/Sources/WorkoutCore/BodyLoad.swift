import Foundation

/*
 * 2.9 lane "load": the Training load and Fitness cards. Garmin gives each
 * workout its own training load (activityTrainingLoad); like the Garmin
 * Board, the app adds them up: the last 7 days against the 4-week weekly
 * average. The word is the Board's own reading, not Garmin's. Shown only.
 */
public struct LoadWorkout: Codable, Equatable {
    public var day: String
    public var load: Double
    public var vo2max: Double?
    public init(day: String, load: Double, vo2max: Double? = nil) { self.day = day; self.load = load; self.vo2max = vo2max }
}

public struct FitnessAgeNumbers: Codable, Equatable {
    public var fitnessAge: Double
    public var realAge: Int?
    public init(fitnessAge: Double, realAge: Int?) { self.fitnessAge = fitnessAge; self.realAge = realAge }
}

/* What the reader keeps in garmin-load.json (numbers only). */
public struct GarminLoadFile: Codable, Equatable {
    public var lastTried: Date?
    public var readAt: Date?
    public var day: String?
    public var workouts: [LoadWorkout] = []
    public var fitness: FitnessAgeNumbers?
    public init() {}
}

public enum BodyLoad {
    public struct Summary: Equatable {
        public var acute: Double          // the last 7 days' load
        public var chronic: Double        // the weekly average of the last 28 days
        public var ratio: Double?
        public var word: String?
        public var weeks: [Double]        // 12 blocks of 7 days, oldest first, the last ending today
    }

    public static func summary(_ workouts: [LoadWorkout], today: String) -> Summary {
        func sum(_ from: String) -> Double { workouts.filter { $0.day >= from && $0.day <= today }.map(\.load).reduce(0, +) }
        let acute = sum(GarminMorning.addDays(today, -6))
        let chronic = sum(GarminMorning.addDays(today, -27)) / 4
        let ratio = chronic > 0 ? (acute / chronic * 100).rounded() / 100 : nil
        var weeks: [Double] = []
        for k in stride(from: 11, through: 0, by: -1) {
            let to = GarminMorning.addDays(today, -7 * k), from = GarminMorning.addDays(to, -6)
            weeks.append(workouts.filter { $0.day >= from && $0.day <= to }.map(\.load).reduce(0, +))
        }
        return Summary(acute: acute.rounded(), chronic: chronic.rounded(), ratio: ratio, word: ratio.map(word), weeks: weeks)
    }

    /* The Board's own words: under 0.8, up to 1.0, up to 1.3, above. */
    public static func word(_ ratio: Double) -> String {
        ratio < 0.8 ? "Recovery" : ratio <= 1.0 ? "Maintaining" : ratio <= 1.3 ? "Productive" : "Overreaching"
    }

    /* Only what the Board itself flags as its warning. */
    public static func isDanger(_ ratio: Double?) -> Bool { (ratio ?? 0) > 1.3 }

    /* Where the ratio sits on a calm scale 0 ... 2 (0...1). */
    public static func scalePosition(_ ratio: Double) -> Double { min(max(ratio / 2, 0), 1) }
    /* The steady stretch 0.8 ... 1.3 on that scale. */
    public static let steady: ClosedRange<Double> = 0.4...0.65

    public static func ratioLine(_ s: Summary) -> String {
        guard let r = s.ratio else { return "4-week average \(BodyPage.grouped(s.chronic))" }
        return "4-week average \(BodyPage.grouped(s.chronic)) · ratio " + String(format: "%.2f", r)
    }

    public static func meaning(_ ratio: Double?) -> [String] {
        var out = ["The ratio sets the last 7 days against your usual week of the past 4 weeks. Around 0.8 to 1.3 is a steady week."]
        guard let r = ratio else { return out + ["There are not enough workouts with a load to compare yet."] }
        if r < 0.8 { out.append("This week is lighter than your usual.") }
        else if r <= 1.3 { out.append("This week is close to your usual.") }
        else { out.append("This week is well above your usual: load is building fast.") }
        out.append("The words are the Garmin Board's own reading, not Garmin's.")
        return out
    }

    /* "Real age 58 · 6 years younger" in calm words. */
    public static func ageLine(_ n: FitnessAgeNumbers) -> String? {
        guard let real = n.realAge else { return nil }
        let diff = real - Int(n.fitnessAge.rounded())
        if diff == 0 { return "Real age \(real) · the same" }
        let years = abs(diff) == 1 ? "1 year" : "\(abs(diff)) years"
        return "Real age \(real) · \(years) " + (diff > 0 ? "younger" : "older")
    }

    // MARK: Garmin's answers

    public static func workouts(_ json: Any?) -> [LoadWorkout] {
        guard let list = json as? [[String: Any]] else { return [] }
        return list.compactMap { a in
            guard let start = a["startTimeLocal"] as? String, start.count >= 10 else { return nil }
            let load = (a["activityTrainingLoad"] as? Double) ?? 0
            let vo2 = a["vO2MaxValue"] as? Double
            return LoadWorkout(day: String(start.prefix(10)), load: load, vo2max: vo2 != nil && vo2! > 0 ? vo2 : nil)
        }
    }

    public static func fitnessAge(_ json: Any?) -> FitnessAgeNumbers? {
        guard let o = json as? [String: Any], let f = o["fitnessAge"] as? Double, f > 0 else { return nil }
        return FitnessAgeNumbers(fitnessAge: f, realAge: (o["chronologicalAge"] as? Double).map { Int($0) })
    }

    /* The newest workout that estimated VO2 max. */
    public static func latestVo2(_ workouts: [LoadWorkout]) -> Double? {
        workouts.filter { $0.vo2max != nil }.max { $0.day < $1.day }?.vo2max
    }
}
