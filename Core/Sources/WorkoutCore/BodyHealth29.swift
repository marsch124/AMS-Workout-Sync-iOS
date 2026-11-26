import Foundation

/*
 * 2.9, the Body page's Health part: sleep debt, weight, energy and water, read from what Garmin answers.
 * Shown only: nothing here advises, judges or reaches the plan.
 */
public enum BodyHealth {
    /* His need when Garmin gives none for a night: the Board's usual eight hours. */
    public static let fallbackNeedMinutes = 480.0

    // MARK: Sleep debt

    public struct Night: Codable, Equatable {
        public var day: String
        /* Minutes slept in the night plus naps; nil = the watch recorded nothing (a dash, never a zero). */
        public var sleptMinutes: Double?
        public var needMinutes: Double
        public var garminNeed: Bool
        public init(day: String, sleptMinutes: Double?, needMinutes: Double, garminNeed: Bool = true) {
            self.day = day; self.sleptMinutes = sleptMinutes; self.needMinutes = needMinutes; self.garminNeed = garminNeed
        }
    }

    /* dailySleepSummariesByDate: a list; each entry has calendarDate or sleepNeed.calendarDate, sleepTimeSeconds, napTimeSeconds, sleepNeed.actual|baseline (minutes). The last seven days ending `day`, oldest first. */
    public static func nights(_ json: Any?, endingOn day: String) -> [Night] {
        var list: [[String: Any]] = []
        if let a = json as? [[String: Any]] { list = a }
        else if let o = json as? [String: Any], let a = o["data"] as? [[String: Any]] { list = a }
        var byDay: [String: [String: Any]] = [:]
        for e in list {
            let need = e["sleepNeed"] as? [String: Any]
            if let d = (e["calendarDate"] as? String) ?? (need?["calendarDate"] as? String) { byDay[d] = e }
        }
        return (0..<7).map { i in
            let d = GarminMorning.addDays(day, i - 6)
            let e = byDay[d]
            let need = e?["sleepNeed"] as? [String: Any]
            let garmin = pos(need?["actual"]) ?? pos(need?["baseline"])
            let slept = pos(e?["sleepTimeSeconds"]).map { $0 / 60 }
            let nap = pos(e?["napTimeSeconds"]).map { $0 / 60 } ?? 0
            return Night(day: d, sleptMinutes: slept.map { $0 + nap }, needMinutes: garmin ?? fallbackNeedMinutes, garminNeed: garmin != nil)
        }
    }

    /* Short (negative) or over (positive), in minutes, across the nights the watch recorded; nil when it recorded none. */
    public static func balance(_ nights: [Night]) -> Double? {
        let counted = nights.filter { $0.sleptMinutes != nil }
        guard !counted.isEmpty else { return nil }
        return counted.reduce(0) { $0 + ($1.sleptMinutes! - $1.needMinutes) }
    }

    /* "−6h 40m" short, "+1h 05m" over, "0m" exactly level. */
    public static func balanceFigure(_ minutes: Double) -> String {
        let r = minutes.rounded()
        if r == 0 { return "0m" }
        return (r < 0 ? "\u{2212}" : "+") + formatDuration(abs(r) * 60)
    }

    public static func missingNights(_ nights: [Night]) -> Int { nights.filter { $0.sleptMinutes == nil }.count }

    /* "Need about 8h a night · 3 nights without the watch". */
    public static func sleepLine(_ nights: [Night]) -> String {
        let needs = nights.map(\.needMinutes)
        let avg = needs.isEmpty ? fallbackNeedMinutes : needs.reduce(0, +) / Double(needs.count)
        var s = "Need about " + formatDuration(avg.rounded() * 60) + " a night"
        let m = missingNights(nights)
        if m > 0 { s += " \u{00B7} \(m) night\(m == 1 ? "" : "s") without the watch" }
        return s
    }

    // MARK: Weight

    public struct Weighing: Codable, Equatable {
        public var day: String
        public var kg: Double
        public init(day: String, kg: Double) { self.day = day; self.kg = kg }
    }

    public struct WeightTrend: Codable, Equatable {
        public var points: [Weighing] = []
        public var goalKg: Double?
        public init(points: [Weighing] = [], goalKg: Double? = nil) { self.points = points; self.goalKg = goalKg }
    }

    private static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    /* /weight-service/weight/range/{from}/{to}?includeAll=true: dailyWeightSummaries[{summaryDate, latestWeight.weight in grams}]; with none, previousDateWeight{calendarDate, weight}. */
    public static func weightTrend(range: Any?, goal: Any?) -> WeightTrend {
        let o = range as? [String: Any]
        var pts: [Weighing] = []
        for s in (o?["dailyWeightSummaries"] as? [[String: Any]]) ?? [] {
            if let d = s["summaryDate"] as? String, let g = pos((s["latestWeight"] as? [String: Any])?["weight"]) {
                pts.append(Weighing(day: d, kg: round1(g / 1000)))
            }
        }
        if pts.isEmpty, let p = o?["previousDateWeight"] as? [String: Any], let d = p["calendarDate"] as? String, let g = pos(p["weight"]) {
            pts = [Weighing(day: d, kg: round1(g / 1000))]
        }
        pts.sort { $0.day < $1.day }
        var goalKg: Double?
        let goals = ((goal as? [String: Any])?["userGoals"] as? [[String: Any]]) ?? []
        let g = goals.filter { ($0["userGoalType"] as? String) == "WEIGHT_GRAMS" && pos($0["goalValue"]) != nil }
            .sorted { (($0["startDate"] as? String) ?? "") > (($1["startDate"] as? String) ?? "") }.first
        if let v = pos(g?["goalValue"]) { goalKg = round1(v / 1000) }
        return WeightTrend(points: pts, goalKg: goalKg)
    }

    /* The change from the first to the last weigh-in inside the 90 days; nil with fewer than two. */
    public static func weightChange(_ points: [Weighing]) -> Double? {
        guard points.count >= 2, let a = points.first, let b = points.last else { return nil }
        return round1(b.kg - a.kg)
    }

    public static func kg(_ v: Double) -> String { String(format: "%.1f", v) }
    public static func signedKg(_ v: Double) -> String { (v < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(v)) }

    /* "Weighed Mon 2 Mar · +0.6 kg in 90 days"; `dayWords` is the last weigh-in's day already written. */
    public static func weightLine(dayWords: String, change: Double?, goalKg: Double?) -> String {
        var s = "Weighed " + dayWords
        if let c = change { s += " \u{00B7} " + (abs(c) < 0.05 ? "no change" : signedKg(c) + " kg") + " in 90 days" }
        if let g = goalKg { s += " \u{00B7} goal " + kg(g) + " kg" }
        return s
    }

    public static let noWeighIns = "No weigh-ins in 90 days. Weigh in with a Garmin scale or log it in Garmin Connect."

    // MARK: Energy and water (one day of /usersummary-service/v2/dailysummaries)

    public struct Energy: Codable, Equatable {
        public var total: Double, active: Double, resting: Double
        public init(total: Double, active: Double, resting: Double) { self.total = total; self.active = active; self.resting = resting }
    }

    public struct Water: Codable, Equatable {
        public var ml: Double
        public var goalMl: Double?
        public init(ml: Double, goalMl: Double?) { self.ml = ml; self.goalMl = goalMl }
    }

    public struct DayFacts: Codable, Equatable {
        public var energy: Energy?
        public var water: Water?
        public init(energy: Energy? = nil, water: Water? = nil) { self.energy = energy; self.water = water }
    }

    public static func dayFacts(_ json: Any?, day: String) -> DayFacts {
        var list: [[String: Any]] = []
        if let a = json as? [[String: Any]] { list = a }
        else if let o = json as? [String: Any], let a = o["data"] as? [[String: Any]] { list = a }
        guard let e = list.first(where: { ($0["calendarDate"] as? String) == day }) else { return DayFacts() }
        var facts = DayFacts()
        if let c = e["calories"] as? [String: Any], let t = pos(c["burnedTotal"]) {
            facts.energy = Energy(total: t, active: pos(c["burnedActive"]) ?? 0, resting: pos(c["burnedResting"]) ?? max(0, t - (pos(c["burnedActive"]) ?? 0)))
        }
        if let h = e["hydration"] as? [String: Any] {
            // Garmin writes 0 when nothing is logged: that is "nothing", not a number.
            facts.water = Water(ml: pos(h["consumedInMl"]) ?? 0, goalMl: pos(h["goalInMl"]))
        }
        return facts
    }

    public static func energyLine(_ e: Energy) -> String {
        "Active \(BodyPage.grouped(e.active)) \u{00B7} resting \(BodyPage.grouped(e.resting))"
    }

    /* Water as logged: nil figure when nothing is logged. */
    public static func waterFigure(_ w: Water?) -> String? {
        guard let w, w.ml > 0 else { return nil }
        return BodyPage.grouped(w.ml)
    }

    public static func waterLine(_ w: Water?) -> String {
        guard let w, w.ml > 0 else { return "No water logged today. Log it in Garmin Connect." }
        guard let g = w.goalMl else { return "Logged in Garmin Connect" }
        return "Goal \(BodyPage.grouped(g)) ml \u{00B7} \(Int((w.ml / g * 100).rounded()))%"
    }

    /* How full the slim bar is, 0...1 (never beyond the bar). */
    public static func waterFill(_ w: Water?) -> Double? {
        guard let w, w.ml > 0, let g = w.goalMl, g > 0 else { return nil }
        return min(1, w.ml / g)
    }

    private static func pos(_ any: Any?) -> Double? {
        let v: Double?
        if let d = any as? Double { v = d } else if let i = any as? Int { v = Double(i) } else if let n = any as? NSNumber { v = n.doubleValue } else { v = nil }
        guard let v, v.isFinite, v > 0 else { return nil }
        return v
    }
}
