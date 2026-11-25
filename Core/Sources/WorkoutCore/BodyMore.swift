import Foundation

/*
 * Round 28's Body pieces, pure and without the network: the Body Battery
 * week, the night's charge, the one calm line, weekly averages for the
 * longer views, the days kept per day, and the two new tiles' numbers.
 * Shown only: nothing here reaches the plan, and sleep never leads to a
 * suggestion.
 */

// MARK: - The days kept on the phone, per day

/*
 * Every day's value per instrument, kept day by day so a longer view only
 * asks Garmin for what is missing. Numbers only; a day without a reading is
 * simply not there (never 0).
 */
public struct BodyHistory: Codable, Equatable {
    public var sleep: [String: Double] = [:]
    public var hrv: [String: Double] = [:]
    public var resting: [String: Double] = [:]
    public var stress: [String: Double] = [:]
    public var steps: [String: Double] = [:]
    public var intensity: [String: Double] = [:]
    /* When each longer view ("4w", "12w") was last read, for the half-hour rule. */
    public var tried: [String: Date] = [:]

    public init() {}

    public func values(_ i: BodyPage.Instrument) -> [String: Double] {
        switch i {
        case .sleep: return sleep
        case .hrv: return hrv
        case .resting: return resting
        case .stress: return stress
        case .steps: return steps
        case .intensity: return intensity
        }
    }

    private static func put(_ days: [BodyDay.DayValue]?, into d: inout [String: Double]) {
        for x in days ?? [] { if let v = x.value, v.isFinite { d[x.day] = v } }
    }

    /* The seven days a read brings are kept too. */
    public mutating func absorb(_ b: BodyDay) {
        Self.put(b.sleep?.nights, into: &sleep)
        Self.put(b.hrv?.days, into: &hrv)
        Self.put(b.resting?.days, into: &resting)
        Self.put(b.stress?.days, into: &stress)
        Self.put(b.steps?.days, into: &steps)
        Self.put(b.intensity?.days, into: &intensity)
    }

    /* A longer read's days; the newer answer wins. */
    public mutating func merge(_ other: BodyHistory) {
        sleep.merge(other.sleep) { _, new in new }
        hrv.merge(other.hrv) { _, new in new }
        resting.merge(other.resting) { _, new in new }
        stress.merge(other.stress) { _, new in new }
        steps.merge(other.steps) { _, new in new }
        intensity.merge(other.intensity) { _, new in new }
    }

    /* Nothing older than `day` is kept. */
    public mutating func prune(before day: String) {
        sleep = sleep.filter { $0.key >= day }
        hrv = hrv.filter { $0.key >= day }
        resting = resting.filter { $0.key >= day }
        stress = stress.filter { $0.key >= day }
        steps = steps.filter { $0.key >= day }
        intensity = intensity.filter { $0.key >= day }
    }

    /* The first day of a span's oldest week still missing a reading, so a read asks only from there (never later than that Monday). */
    public func readFrom(_ span: BodyPage.Span, today: String) -> String {
        guard let weeks = span.weeks else { return GarminMorning.addDays(today, -6) }
        let start = BodyPage.weekStart(of: GarminMorning.addDays(BodyPage.weekStart(of: today), -7 * (weeks - 1)))
        let all = [sleep, hrv, resting, stress]
        var d = start
        while d < today {
            // A day every one of the four is missing is read again; a day with any reading is held.
            if all.allSatisfy({ $0[d] == nil }) { return d }
            d = GarminMorning.addDays(d, 1)
        }
        return today
    }
}

// MARK: - Garmin's answers for the new pieces

extension GarminBody {

    /* /usersummary-service/v2/dailysummaries: steps and intensity minutes by day (the Board reads the same fields). */
    public struct ActivityDays: Equatable {
        public var steps: [String: Double] = [:]
        /* Moderate + 2 x vigorous, as Garmin counts intensity minutes. */
        public var intensity: [String: Double] = [:]
        public var moderate: [String: Double] = [:]
        public var vigorous: [String: Double] = [:]
        public var weeklyGoal: Double?
        public var stepGoal: Double?
        public init() {}
    }

    private static func num(_ any: Any?) -> Double? {
        guard let n = GarminMorning.number(any), n.isFinite else { return nil }
        return n
    }

    public static func activityDays(_ json: Any?) -> ActivityDays {
        var out = ActivityDays()
        let items = GarminMorning.list(json, inside: ["data"]).sorted { (GarminMorning.text($0["calendarDate"]) ?? "") < (GarminMorning.text($1["calendarDate"]) ?? "") }
        for item in items {
            guard let d = GarminMorning.text(item["calendarDate"]) else { continue }
            let steps = (item["movement"] as? [String: Any])?["steps"] as? [String: Any]
            let walked = num(steps?["value"]) ?? 0
            // A day with no steps at all is a day without the watch: left out.
            if walked > 0 { out.steps[d] = walked }
            if let g = num(steps?["goal"]), g > 0 { out.stepGoal = g }
            if let im = item["intensityMinutes"] as? [String: Any] {
                let m = max(0, num(im["moderate"]) ?? 0), v = max(0, num(im["vigorous"]) ?? 0)
                if walked > 0 || m > 0 || v > 0 {
                    out.moderate[d] = m; out.vigorous[d] = v; out.intensity[d] = m + 2 * v
                }
                if let g = num(im["goal"]), g > 0 { out.weeklyGoal = g }
            }
        }
        return out
    }

    public static func steps(_ a: ActivityDays, day: String) -> BodyDay.Steps? {
        let line = series(a.steps, endingOn: day)
        guard line.contains(where: { $0.value != nil }) else { return nil }
        return BodyDay.Steps(today: a.steps[day], goal: a.stepGoal, days: line)
    }

    public static func intensity(_ a: ActivityDays, day: String) -> BodyDay.Intensity? {
        let line = series(a.intensity, endingOn: day)
        guard line.contains(where: { $0.value != nil }) else { return nil }
        let monday = BodyPage.weekStart(of: day)
        let week = a.intensity.filter { $0.key >= monday && $0.key <= day }
        let total: Double? = week.isEmpty ? nil : week.values.reduce(0, +)
        func sum(_ d: [String: Double]) -> Double { d.filter { $0.key >= monday && $0.key <= day }.values.reduce(0, +) }
        return BodyDay.Intensity(weekTotal: total, goal: a.weeklyGoal, moderate: sum(a.moderate), vigorous: sum(a.vigorous), days: line)
    }

    /*
     * The Body Battery week. The daily report asked for seven days (start =
     * 6 days ago, end = today) answers a list of days; each reading is filed
     * under the calendar day of its own time, whichever entry it came in.
     * Today's curve is the one already read for today. A day without
     * readings stays in the list, empty.
     */
    public static func batteryWeek(_ json: Any?, day: String, todayPoints: [BodyDay.Point],
                                   calendar: Calendar = GarminMorning.calendar()) -> [BodyDay.BatteryDay] {
        var byDay: [String: [BodyDay.Point]] = [:]
        var seen = Set<TimeInterval>()
        for entry in GarminMorning.list(json, inside: ["data"]) {
            for item in (entry["bodyBatteryValuesArray"] as? [Any]) ?? [] {
                guard let pair = item as? [Any], pair.count >= 2, let ms = num(pair[0]), let v = num(pair[1]), v >= 0, v <= 100 else { continue }
                let t = Date(timeIntervalSince1970: ms / 1000)
                guard seen.insert(t.timeIntervalSince1970).inserted else { continue }
                byDay[GarminMorning.dayKey(t, calendar: calendar), default: []].append(.init(time: t, value: v))
            }
        }
        if !todayPoints.isEmpty { byDay[day] = todayPoints }
        return (0..<7).map { i in
            let d = GarminMorning.addDays(day, i - 6, calendar: calendar)
            let pts = (byDay[d] ?? []).sorted { $0.time < $1.time }
            return BodyDay.BatteryDay(day: d, points: thin(pts, to: 48), high: pts.map(\.value).max(), low: pts.map(\.value).min())
        }
    }

    /* At most `n` readings, evenly spread, the last one always kept. */
    public static func thin(_ pts: [BodyDay.Point], to n: Int) -> [BodyDay.Point] {
        guard pts.count > n, n > 1 else { return pts }
        let step = Double(pts.count - 1) / Double(n - 1)
        return (0..<n).map { pts[Int((Double($0) * step).rounded())] }
    }

    /* Whether a held week still holds for `day` (its days are exactly the seven ending today). */
    public static func weekIsHeld(_ week: [BodyDay.BatteryDay]?, day: String) -> Bool {
        guard let week, week.count == 7, week.last?.day == day, week.first?.day == GarminMorning.addDays(day, -6) else { return false }
        // Only the six days before today count; today comes from today's own read.
        return week.dropLast().contains { !$0.points.isEmpty }
    }
}

// MARK: - The page's small sums

extension BodyPage {

    /* The page's span: seven days (as before), four weeks or twelve weeks. */
    public enum Span: String, CaseIterable, Identifiable, Sendable {
        case week = "7", weeks4 = "4w", weeks12 = "12w"
        public var id: String { rawValue }
        public var title: String {
            switch self { case .week: return "7 days"; case .weeks4: return "4 weeks"; case .weeks12: return "12 weeks" }
        }
        /* The number of weekly bars; nil for the seven daily ones. */
        public var weeks: Int? {
            switch self { case .week: return nil; case .weeks4: return 4; case .weeks12: return 12 }
        }
    }

    /* The Monday of the week `day` is in. */
    public static func weekStart(of day: String, calendar: Calendar = GarminMorning.calendar()) -> String {
        guard let d = GarminMorning.date(day, calendar: calendar) else { return day }
        let sinceMonday = (calendar.component(.weekday, from: d) + 5) % 7
        return GarminMorning.addDays(day, -sinceMonday, calendar: calendar)
    }

    /*
     * Weekly averages, oldest first, the last being the week `day` is in.
     * A week counts only its days with a reading (never a missing day as 0);
     * a week with none has no value. Each entry is named by its Monday.
     */
    public static func weekly(_ values: [String: Double], weeks: Int, endingOn day: String) -> [BodyDay.DayValue] {
        let last = weekStart(of: day)
        return (0..<max(0, weeks)).map { i in
            let monday = GarminMorning.addDays(last, 7 * (i - (weeks - 1)))
            let end = GarminMorning.addDays(monday, 6)
            let v = values.filter { $0.key >= monday && $0.key <= min(end, day) && $0.value.isFinite }.map(\.value)
            return BodyDay.DayValue(day: monday, value: v.isEmpty ? nil : v.reduce(0, +) / Double(v.count))
        }
    }

    /* The average of every day with a reading inside the span's weeks. */
    public static func spanAverage(_ values: [String: Double], weeks: Int, endingOn day: String) -> Double? {
        let from = GarminMorning.addDays(weekStart(of: day), -7 * (weeks - 1))
        let v = values.filter { $0.key >= from && $0.key <= day && $0.value.isFinite }.map(\.value)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    /* 8400 as "8,400"; always a comma, whatever the phone's language. */
    public static func grouped(_ v: Double) -> String {
        guard v.isFinite else { return "–" }
        let n = Int(v.rounded())
        let digits = String(abs(n))
        var out = ""
        for (i, c) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    // MARK: Night's charge

    /*
     * "Charged +44 overnight": the rise from the night's lowest reading (after
     * 18:00 the evening before, or since midnight when yesterday's evening is
     * not there) to the morning's highest before 11:00 after that low. Nil
     * when it cannot be worked out, or when there is no rise.
     */
    public static func charge(yesterday: [BodyDay.Point]?, today: [BodyDay.Point], day: String,
                              calendar: Calendar = GarminMorning.calendar()) -> Int? {
        guard let d = GarminMorning.date(day, calendar: calendar) else { return nil }
        let midnight = calendar.startOfDay(for: d)
        let evening = midnight.addingTimeInterval(-6 * 3600)
        let morning = today.filter { $0.value.isFinite && $0.time >= midnight && $0.time < midnight.addingTimeInterval(11 * 3600) }
        let night = (yesterday ?? []).filter { $0.value.isFinite && $0.time >= evening && $0.time < midnight }
        let window = (night + morning).sorted { $0.time < $1.time }
        guard let low = window.min(by: { $0.value < $1.value }) else { return nil }
        guard let high = morning.filter({ $0.time >= low.time }).map(\.value).max() else { return nil }
        let rise = high - low.value
        return rise >= 1 ? Int(rise.rounded()) : nil
    }

    public static func chargeLine(_ rise: Int?) -> String? { rise.map { "Charged +\($0) overnight" } }

    // MARK: The one calm line

    public struct Calm: Equatable {
        public var hrv: Double?; public var hrvLow: Int?; public var hrvHigh: Int?
        public var resting: Double?; public var restingNormal: Double?
        public var wake: Double?; public var wakeNormal: Double?
        public init(hrv: Double? = nil, hrvLow: Int? = nil, hrvHigh: Int? = nil, resting: Double? = nil,
                    restingNormal: Double? = nil, wake: Double? = nil, wakeNormal: Double? = nil) {
            self.hrv = hrv; self.hrvLow = hrvLow; self.hrvHigh = hrvHigh
            self.resting = resting; self.restingNormal = restingNormal; self.wake = wake; self.wakeNormal = wakeNormal
        }
    }

    /* The rule the morning line uses: inside his normal unless 4 % (at least 1) away from it. */
    public static func within(_ value: Double, normal: Double) -> Bool {
        abs(value - normal) < max(1, normal * 0.04)
    }

    /*
     * Where three numbers sit against his own normals, and nothing more: no
     * colour, no advice, no good or bad. Only the ones that have a normal are
     * counted; none, no line.
     */
    public static func calmLine(_ c: Calm) -> String? {
        var total = 0, inside = 0
        var outside: [String] = []
        if let v = c.hrv, v.isFinite, let lo = c.hrvLow, let hi = c.hrvHigh {
            total += 1
            if v < Double(lo) { outside.append("HRV below it") } else if v > Double(hi) { outside.append("HRV above it") } else { inside += 1 }
        }
        if let v = c.resting, v.isFinite, let n = c.restingNormal, n > 0 {
            total += 1
            if within(v, normal: n) { inside += 1 } else { outside.append("resting pulse " + (v < n ? "below it" : "above it")) }
        }
        if let v = c.wake, v.isFinite, let n = c.wakeNormal, n > 0 {
            total += 1
            if within(v, normal: n) { inside += 1 } else { outside.append("Body Battery on waking " + (v < n ? "below it" : "above it")) }
        }
        guard total > 0 else { return nil }
        return "\(inside) of \(total) in your normal range" + (outside.isEmpty ? "" : " · " + outside.joined(separator: ", "))
    }

    /* A line under a tile's days in numbers, where the numbers need a word. */
    public static func peekNote(_ i: Instrument, span: Span) -> String? {
        var parts: [String] = []
        if span != .week { parts.append("Each row is one week's average of the days with a reading, named by its Monday.") }
        if i == .intensity { parts.append("A vigorous minute counts twice, as Garmin counts it.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: The week card

    /* The figure under a day's curve: whole points, or nothing. */
    public static func weekFigures(_ d: BodyDay.BatteryDay) -> (high: String, low: String)? {
        guard let h = d.high, let l = d.low else { return nil }
        return (whole(h), whole(l))
    }
}
