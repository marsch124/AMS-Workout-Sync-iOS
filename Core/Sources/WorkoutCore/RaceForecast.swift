import Foundation

/*
 * Round 30, pick 10 (race-plan lane): the race-day forecast. Pure rules.
 * "Likely", never "will". Each part of the day is worked out from what he has
 * done and what the course is like, and shown as a RANGE that is wide months
 * out and narrows week by week.
 *
 *   swim   his swim threshold pace (CSS) plus a race margin, over the swim distance
 *   bike   his recent steady rides (Garmin: average speed at zone 2–3 pulse),
 *          slowed for the course's climbing and for July's heat
 *   run    his recent steady runs the same way, plus a fade for running off the bike
 *   T1/T2  the course table's typical change-over times
 *
 * The range: half-width of a part = (2.5 % + 9.5 % × min(1, days to race ÷ 300))
 * of its time, × 0.6 for the swim (a test gives it), × 1.1 for the run;
 * 3 % more when fewer than 3 steady sessions stand behind a part. The change-overs
 * get ±20 % and never less than ±20 s. Low rounds down, high rounds up.
 */

/* One finished session, as far as the forecast needs it (read from Garmin's list). */
public struct RaceEffort: Codable, Equatable, Sendable {
    public var family: String      // "bike" or "run" (swim is worked from the test)
    public var typeKey: String
    public var seconds: Double
    public var metres: Double
    public var avgHr: Double
    public var avgPowerW: Double?
    public init(family: String, typeKey: String = "", seconds: Double, metres: Double, avgHr: Double, avgPowerW: Double? = nil) {
        self.family = family; self.typeKey = typeKey; self.seconds = seconds; self.metres = metres; self.avgHr = avgHr; self.avgPowerW = avgPowerW
    }

    /* Garmin's list of activities, read for bike and run sessions with pulse and length. */
    public static func read(_ json: Any?) -> [RaceEffort] {
        GarminMorning.list(json, inside: ["activities", "activityList"]).compactMap { a in
            let type: String = {
                if let t = a["activityType"] as? [String: Any], let k = t["typeKey"] as? String { return k }
                return (a["activityType"] as? String) ?? ""
            }()
            guard let family = GarminActivity.family(ofGarmin: type), family == "bike" || family == "run",
                  let secs = GarminMorning.number(a["duration"]), secs > 0,
                  let m = GarminMorning.number(a["distance"]), m > 0,
                  let hr = GarminMorning.number(a["averageHR"]), hr > 0 else { return nil }
            let p = GarminMorning.number(a["avgPower"]).flatMap { $0 > 0 ? $0 : nil }
            return RaceEffort(family: family, typeKey: type, seconds: secs, metres: m, avgHr: hr, avgPowerW: p)
        }
    }
}

public struct ForecastBasis: Codable, Equatable, Sendable {
    /* Seconds per 100 m from his latest test. */
    public var css: Double?
    public var lthr: Double?
    public var efforts: [RaceEffort]
    public init(css: Double?, lthr: Double?, efforts: [RaceEffort]) { self.css = css; self.lthr = lthr; self.efforts = efforts }
}

public struct LegRange: Codable, Equatable, Sendable {
    public var low: Int, mid: Int, high: Int
    public init(low: Int, mid: Int, high: Int) { self.low = low; self.mid = mid; self.high = high }
}

public struct RaceForecast: Codable, Equatable, Sendable {
    public var legs: [String: LegRange]
    public var total: LegRange?
    public var days: Int
    /* The Monday of the week it was worked out. */
    public var workedOut: String
    public func leg(_ l: RaceLeg) -> LegRange? { legs[l.rawValue] }
    /* The parts that could not be worked out yet, for the grey line. */
    public var missing: [RaceLeg] { RaceLeg.allCases.filter { legs[$0.rawValue] == nil } }
}

public enum RaceForecastRules {
    public static let swimMarginPer100: Double = 4        // seconds per 100 m over CSS at race effort
    public static let runFade = 0.04                      // running off the bike
    public static let bikeClimbPerMetrePerKm = 0.003      // 0.3 % slower per metre climbed per km
    public static let runClimbPerMetrePerKm = 0.004
    public static let bikeHeatPerDegree = 0.004           // above 20 °C
    public static let runHeatPerDegree = 0.005            // above 15 °C
    public static let hrBand: ClosedRange<Double> = 0.81...0.95   // zone 2–3, as a share of LTHR
    public static let minSteady = 3

    /* Steady sessions: pulse in zone 2–3, long enough, not indoors (a trainer's speed says nothing about the road). */
    public static func steady(_ efforts: [RaceEffort], family: String, lthr: Double) -> [RaceEffort] {
        efforts.filter { e in
            guard e.family == family, e.metres > 0, e.seconds >= (family == "bike" ? 3600 : 1800) else { return false }
            if family == "bike", e.typeKey.lowercased().contains("indoor") || e.typeKey.lowercased().contains("virtual") { return false }
            return hrBand.contains(e.avgHr / lthr)
        }
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    public static func medianSpeed(_ efforts: [RaceEffort]) -> Double? { median(efforts.map { $0.metres / $0.seconds }) }
    public static func medianPower(_ efforts: [RaceEffort]) -> Double? { median(efforts.compactMap(\.avgPowerW)) }

    /* How wide the range is, as a share of the time, for days to go. */
    public static func halfWidth(days: Int, leg: RaceLeg, thin: Bool) -> Double {
        let far = min(1.0, max(0.0, Double(days) / 300))
        var w = 0.025 + 0.095 * far
        if leg == .swim { w *= 0.6 }
        if leg == .run { w *= 1.1 }
        return w + (thin ? 0.03 : 0)
    }

    static func range(_ mid: Double, half: Double, step: Int) -> LegRange {
        let m = Int(mid.rounded())
        let lo = Int((mid * (1 - half) / Double(step)).rounded(.down)) * step
        let hi = Int((mid * (1 + half) / Double(step)).rounded(.up)) * step
        return LegRange(low: lo, mid: m, high: hi)
    }

    public static func make(_ basis: ForecastBasis, course: RaceCourse, days: Int, today: String) -> RaceForecast {
        var legs: [String: LegRange] = [:]
        let d = max(0, days)

        if let css = basis.css, css > 30, css < 300 {
            let secs = (css + swimMarginPer100) * Double(course.swimMetres) / 100
            legs["swim"] = range(secs, half: halfWidth(days: d, leg: .swim, thin: false), step: 60)
        }
        func change(_ leg: RaceLeg, _ s: Int) {
            let half = max(0.2, 20.0 / Double(s))
            legs[leg.rawValue] = range(Double(s), half: half, step: 30)
        }
        change(.t1, course.t1); change(.t2, course.t2)

        if let lthr = basis.lthr, lthr > 60 {
            let rides = steady(basis.efforts, family: "bike", lthr: lthr)
            if let v = medianSpeed(rides), v > 0 {
                let climb = course.bikeKm > 0 ? course.bikeClimbM / course.bikeKm : 0
                let heat = max(0, course.julyTempC - 20) * bikeHeatPerDegree
                let secs = course.bikeKm * 1000 / v * (1 + climb * bikeClimbPerMetrePerKm) * (1 + heat)
                legs["bike"] = range(secs, half: halfWidth(days: d, leg: .bike, thin: rides.count < minSteady), step: 60)
            }
            let runs = steady(basis.efforts, family: "run", lthr: lthr)
            if let v = medianSpeed(runs), v > 0 {
                let climb = course.runKm > 0 ? course.runClimbM / course.runKm : 0
                let heat = max(0, course.julyTempC - 15) * runHeatPerDegree
                let secs = course.runKm * 1000 / v * (1 + runFade) * (1 + climb * runClimbPerMetrePerKm) * (1 + heat)
                legs["run"] = range(secs, half: halfWidth(days: d, leg: .run, thin: runs.count < minSteady), step: 60)
            }
        }

        var total: LegRange?
        if legs.count == RaceLeg.allCases.count {
            let lo = legs.values.reduce(0) { $0 + $1.low }, mid = legs.values.reduce(0) { $0 + $1.mid }, hi = legs.values.reduce(0) { $0 + $1.high }
            total = LegRange(low: lo / 300 * 300, mid: mid, high: (hi + 299) / 300 * 300)
        }
        return RaceForecast(legs: legs, total: total, days: d, workedOut: PlanView.weekStart(today))
    }

    /* "5h 30m – 5h 55m" */
    public static func words(_ r: LegRange, changeOver: Bool = false) -> String {
        if changeOver { return RacePacing.words(r.low, changeOver: true) + " \u{2013} " + RacePacing.words(r.high, changeOver: true) }
        return formatDuration(Double(r.low)) + " \u{2013} " + formatDuration(Double(r.high))
    }
}

// MARK: - one snapshot a week

public enum ForecastShelf {
    public static let prefix = "raceplan/forecast/"
    public static let ageGroupKey = "raceplan/agegroup"

    /* "2026-49": the year and week of the Monday it was worked out (ISO weeks). */
    public static func weekKey(_ day: String) -> String {
        guard let d = parseDayKey(PlanView.weekStart(day)) else { return "0000-00" }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let y = cal.component(.yearForWeekOfYear, from: d), w = cal.component(.weekOfYear, from: d)
        return String(y) + "-" + String(format: "%02d", w)
    }
    public static func key(_ day: String) -> String { prefix + weekKey(day) }
}

public struct ForecastTrendRow: Equatable, Sendable {
    public let workedOut: String
    public let mid: Int
    /* 0…1 within the rows shown, never below 0.15 so every bar can be seen. */
    public let fraction: Double
}

public enum ForecastTrend {
    /* The middle of the total, oldest first, the last `limit` weeks. */
    public static func rows(_ snaps: [RaceForecast], limit: Int = 12) -> [ForecastTrendRow] {
        let kept = snaps.filter { $0.total != nil }.sorted { $0.workedOut < $1.workedOut }.suffix(limit)
        let mids = kept.compactMap { $0.total?.mid }
        guard let lo = mids.min(), let hi = mids.max() else { return [] }
        return kept.map { f in
            let m = f.total!.mid
            let frac = hi == lo ? 0.6 : 0.15 + 0.85 * Double(m - lo) / Double(hi - lo)
            return ForecastTrendRow(workedOut: f.workedOut, mid: m, fraction: frac)
        }
    }
}
