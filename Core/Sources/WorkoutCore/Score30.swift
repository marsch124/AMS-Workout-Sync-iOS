import Foundation

/*
 * 2.18 lane "score": the two rules of "Session score" and "Fitter at the same pulse". Pure; shown only.
 * Nothing here reaches the plan, and nothing here judges the person: a word says how the watch's zones
 * sat against what the plan asked, and a pace is a pace.
 */

// MARK: - Session score

public enum SessionScore {
    public enum Word: String, Codable, Equatable {
        case onTarget, aBitHard, tooHard
        public var text: String {
            switch self {
            case .onTarget: return "On target"
            case .aBitHard: return "A bit hard"
            case .tooHard: return "Too hard"
            }
        }
    }

    /* Up to 15 % of the time above the planned zone is on target; up to 35 % a bit hard; more is too hard. */
    public static let onTargetUpTo = 0.15
    public static let aBitHardUpTo = 0.35
    /* A session with less than 5 minutes in zones is not scored. */
    public static let minSeconds = 300.0

    public struct Result: Equatable {
        public let word: Word
        public let zone: Int
        public let inZoneMinutes: Int
        public let totalMinutes: Int
        public let mostlyBelow: Bool
        public let aboveShare: Double

        /* "38 of 45 min in zone 2", and where most of it was below the zone, the honest tail. */
        public var line: String {
            let base = "\(inZoneMinutes) of \(totalMinutes) min in zone \(zone)"
            return mostlyBelow ? base + " · most of it below zone \(zone)" : base
        }
    }

    /* The one zone a session's intensity names ("Z2", "Z2 + strides"). A range ("Z4–Z5"), RPE or nothing: nil. */
    public static func plannedZone(intensity: String) -> Int? {
        let zs = Zones.zones(in: intensity)
        return zs.count == 1 ? zs[0] : nil
    }

    /* Only these sports are scored; strength, mobility, rest, brick and other are not. */
    public static func isScored(sport: String) -> Bool { ["run", "bike", "swim"].contains(sport) }

    public static func score(zoneSeconds: [Double], plannedZone zone: Int) -> Result? {
        guard zoneSeconds.count == 5, (1...5).contains(zone) else { return nil }
        let secs = zoneSeconds.map { max(0, $0) }
        let total = secs.reduce(0, +)
        guard total >= minSeconds else { return nil }
        let inZone = secs[zone - 1]
        let above = secs[zone...].reduce(0, +)
        let below = secs[..<(zone - 1)].reduce(0, +)
        let share = above / total
        let word: Word = share <= onTargetUpTo ? .onTarget : (share <= aBitHardUpTo ? .aBitHard : .tooHard)
        return Result(word: word, zone: zone, inZoneMinutes: Int((inZone / 60).rounded()), totalMinutes: Int((total / 60).rounded()),
                      mostlyBelow: below > total / 2, aboveShare: share)
    }

    /* "On target: 9 of 11 sessions this week" — of the sessions that have a score. Nil when none has. */
    public static func weekLine(_ words: [Word]) -> String? {
        guard !words.isEmpty else { return nil }
        let on = words.filter { $0 == .onTarget }.count
        return "On target: \(on) of \(words.count) session\(words.count == 1 ? "" : "s") this week"
    }
}

// MARK: - Fitter at the same pulse

public struct SteadyWorkout: Codable, Equatable {
    /* "run" or "bike". */
    public var sport: String
    public var day: String
    public var seconds: Double
    public var avgHr: Double
    public var speedMps: Double
    public var powerW: Double?
    public init(sport: String, day: String, seconds: Double, avgHr: Double, speedMps: Double, powerW: Double? = nil) {
        self.sport = sport; self.day = day; self.seconds = seconds; self.avgHr = avgHr; self.speedMps = speedMps; self.powerW = powerW
    }
}

public struct SamePulseMonth: Equatable {
    public let month: String          // "2026-09"
    public let count: Int
    public let speedMps: Double?      // monthly median; nil when fewer than 2 steady workouts
    public let powerW: Double?        // median of those that have power, when at least 2 do
    public var enough: Bool { speedMps != nil }
}

public enum SamePulse {
    public static let minSeconds = 20.0 * 60
    public static let minWorkouts = 2

    /* Garmin's activity list, read for the numbers this rule needs; anything missing leaves the activity out. */
    public static func parse(_ json: Any?) -> [SteadyWorkout] {
        GarminMorning.list(json, inside: ["activities", "activityList"]).compactMap { a in
            let type: String = {
                if let t = a["activityType"] as? [String: Any], let k = t["typeKey"] as? String { return k }
                return (a["activityType"] as? String) ?? ""
            }()
            guard let family = GarminActivity.family(ofGarmin: type), family == "run" || family == "bike",
                  let local = (a["startTimeLocal"] as? String).map({ String($0.prefix(10)) }), local.count == 10,
                  let secs = GarminMorning.number(a["duration"]), let hr = GarminMorning.number(a["averageHR"]), hr > 0,
                  let speed = GarminMorning.number(a["averageSpeed"]), speed > 0 else { return nil }
            let power = (GarminMorning.number(a["avgPower"]) ?? GarminMorning.number(a["averagePower"])).flatMap { $0 > 0 ? $0 : nil }
            return SteadyWorkout(sport: family, day: local, seconds: secs, avgHr: hr, speedMps: speed, powerW: power)
        }
    }

    /* How many activities one page of Garmin's list held. */
    public static func pageCount(_ json: Any?) -> Int { GarminMorning.list(json, inside: ["activities", "activityList"]).count }

    /* The pulse band of zone 2 from the zones in use: the heart table's Z2 row ("130–145"), else his threshold pulse × 81–89 %. */
    public static func zone2Band(_ zones: Zones?) -> ClosedRange<Double>? {
        guard let zones else { return nil }
        if let table = zones.tables.first(where: { $0.kind == .heart }),
           let row = table.rows(forZones: [2]).first(where: { !$0.value.isEmpty }) {
            let nums = numbers(in: row.value)
            if nums.count >= 2, nums[0] < nums[1] { return nums[0]...nums[1] }
        }
        if let lthr = zones.lthr { return (lthr * 0.81).rounded()...(lthr * 0.89).rounded() }
        return nil
    }

    static func numbers(in text: String) -> [Double] {
        var out: [Double] = [], cur = ""
        for ch in text + " " {
            if ch.isNumber { cur.append(ch) } else { if let n = Double(cur) { out.append(n) }; cur = "" }
        }
        return out
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /* "2026-09" … the month of `today`, from the start of the season (1 Sep). */
    public static func months(today: String) -> [String] {
        guard today.count >= 7, let y = Int(today.prefix(4)), let m = Int(today.dropFirst(5).prefix(2)) else { return [] }
        var year = m >= 9 ? y : y - 1, month = 9
        var out: [String] = []
        while year < y || (year == y && month <= m) {
            out.append(String(format: "%04d-%02d", year, month))
            month += 1
            if month == 13 { month = 1; year += 1 }
        }
        return out
    }

    /* One sport, month by month: steady = at least 20 minutes, average pulse inside the band. */
    public static func byMonth(_ list: [SteadyWorkout], sport: String, band: ClosedRange<Double>, today: String) -> [SamePulseMonth] {
        let steady = list.filter { $0.sport == sport && $0.seconds >= minSeconds && band.contains($0.avgHr) }
        return months(today: today).map { m in
            let of = steady.filter { $0.day.hasPrefix(m) }
            guard of.count >= minWorkouts, let speed = median(of.map(\.speedMps)) else {
                return SamePulseMonth(month: m, count: of.count, speedMps: nil, powerW: nil)
            }
            let powers = of.compactMap(\.powerW)
            return SamePulseMonth(month: m, count: of.count, speedMps: speed, powerW: powers.count >= minWorkouts ? median(powers) : nil)
        }
    }

    // MARK: words

    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    public static func shortMonth(_ month: String) -> String {
        guard let m = Int(month.suffix(2)), (1...12).contains(m) else { return month }
        return monthNames[m - 1]
    }

    /* "5:41 /km" from metres a second. */
    public static func paceText(_ mps: Double) -> String {
        guard mps > 0 else { return "—" }
        let per = 1000 / mps
        var m = Int(per / 60), s = Int((per - Double(m) * 60).rounded())
        if s == 60 { m += 1; s = 0 }
        return "\(m):" + String(format: "%02d", s) + " /km"
    }

    public static func speedText(_ mps: Double) -> String { jsNumberString((mps * 36).rounded() / 10) + " km/h" }

    /* The calm line: first and last month that have a figure. Slower is said just as plainly. */
    public static func line(sport: String, months: [SamePulseMonth]) -> String? {
        let name = sport == "run" ? "Run" : "Ride"
        func text(_ v: Double) -> String { sport == "run" ? paceText(v) : speedText(v) }
        let have = months.filter { $0.speedMps != nil }
        guard let first = have.first, let last = have.last, let a = first.speedMps, let b = last.speedMps else { return nil }
        if first.month == last.month { return "\(name): \(text(a)) in \(shortMonth(first.month)) at the same pulse" }
        return "\(name): \(text(a)) in \(shortMonth(first.month)) → \(text(b)) in \(shortMonth(last.month)) at the same pulse"
    }
}
