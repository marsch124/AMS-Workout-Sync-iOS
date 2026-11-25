import Foundation

/*
 * The "Body" page's numbers from Garmin: Body Battery through the day, last
 * night's sleep, HRV, resting pulse and stress, each with the last seven
 * days. Shown only: nothing here changes the plan.
 *
 * Like GarminMorning, this is the pure part — no network, no key. The app
 * asks Garmin and hands the answers (already read as JSON) to these
 * functions. Everything forgives: a missing piece becomes nil or an empty
 * list, a night or day without data is nil (never 0), and nothing is ever
 * NaN or infinite.
 */
public struct BodyDay: Codable, Equatable {

    /* One reading of the Body Battery curve. */
    public struct Point: Codable, Equatable {
        public var time: Date
        public var value: Double   // 0...100
        public init(time: Date, value: Double) { self.time = time; self.value = value }
    }

    /* A workout shown on the curve, and the points it cost. */
    public struct Workout: Codable, Equatable {
        public var id: String
        public var name: String
        /* Garmin's sport key, e.g. "running", "lap_swimming". */
        public var type: String
        public var start: Date
        public var end: Date
        /* How many points the workout cost; nil when Garmin gives nothing to work it out from. */
        public var drain: Double?
        public init(id: String, name: String, type: String, start: Date, end: Date, drain: Double?) {
            self.id = id; self.name = name; self.type = type; self.start = start; self.end = end; self.drain = drain
        }
    }

    /* Today's curve from midnight to now. */
    public struct Battery: Codable, Equatable {
        public var points: [Point]
        public var workouts: [Workout]
        public var now: Double? { points.last?.value }
        public var highest: Double? { points.map(\.value).max() }
        public var lowest: Double? { points.map(\.value).min() }
        public init(points: [Point], workouts: [Workout] = []) { self.points = points; self.workouts = workouts }
    }

    /* One day's value on a seven-day line; nil when that day has none. */
    public struct DayValue: Codable, Equatable {
        public var day: String
        public var value: Double?
        public init(day: String, value: Double?) { self.day = day; self.value = value }
    }

    public struct Sleep: Codable, Equatable {
        /* Last night, in hours. */
        public var lastNight: Double?
        /* The last seven nights, oldest first, the last one being last night. */
        public var nights: [DayValue]
        public init(lastNight: Double?, nights: [DayValue]) { self.lastNight = lastNight; self.nights = nights }
    }

    public struct HRV: Codable, Equatable {
        public var lastNight: Double?
        /* Garmin's balanced range; both nil until Garmin has learned one. */
        public var rangeLow: Int?
        public var rangeHigh: Int?
        /* True when there is a number but Garmin gives no range yet. */
        public var stillLearning: Bool
        public var days: [DayValue]
        public init(lastNight: Double?, rangeLow: Int? = nil, rangeHigh: Int? = nil, stillLearning: Bool = false, days: [DayValue] = []) {
            self.lastNight = lastNight; self.rangeLow = rangeLow; self.rangeHigh = rangeHigh
            self.stillLearning = stillLearning; self.days = days
        }
    }

    public struct Resting: Codable, Equatable {
        public var today: Double?
        /* His own normal; nil until enough days are there. */
        public var normal: Double?
        public var days: [DayValue]
        public init(today: Double?, normal: Double? = nil, days: [DayValue] = []) {
            self.today = today; self.normal = normal; self.days = days
        }
    }

    public struct Stress: Codable, Equatable {
        public var average: Double?
        public var highest: Double?
        /* Daily averages for the last seven days, oldest first. */
        public var days: [DayValue]
        public init(average: Double?, highest: Double?, days: [DayValue] = []) {
            self.average = average; self.highest = highest; self.days = days
        }
    }

    /* The calendar day these numbers belong to, "2026-11-25". */
    public var day: String
    public var readAt: Date
    public var battery: Battery?
    public var sleep: Sleep?
    public var hrv: HRV?
    public var resting: Resting?
    public var stress: Stress?

    public init(day: String, readAt: Date, battery: Battery? = nil, sleep: Sleep? = nil, hrv: HRV? = nil,
                resting: Resting? = nil, stress: Stress? = nil) {
        self.day = day; self.readAt = readAt; self.battery = battery; self.sleep = sleep
        self.hrv = hrv; self.resting = resting; self.stress = stress
    }

    public var isEmpty: Bool {
        battery == nil && sleep == nil && hrv == nil && resting == nil && stress == nil
    }
}

/* What the app keeps on the phone for the Body page: numbers only. */
public struct GarminBodyFile: Codable, Equatable {
    public var body: BodyDay?
    public var lastTried: Date?
    public init(body: BodyDay? = nil, lastTried: Date? = nil) { self.body = body; self.lastTried = lastTried }
}

public enum GarminBody {

    public static let shownDays = 7
    /* How far back the pulse's own normal looks (the same fortnight as the morning's). */
    public static let history = GarminMorning.fortnight

    private typealias M = GarminMorning

    // MARK: - Small readers

    private static func finite(_ x: Double?) -> Double? {
        guard let x, x.isFinite else { return nil }
        return x
    }

    private static func positive(_ any: Any?) -> Double? {
        guard let n = finite(M.number(any)), n > 0 else { return nil }
        return n
    }

    /* The last seven days ending at `end`, oldest first; a day Garmin has nothing for is nil. */
    public static func series(_ values: [String: Double], endingOn end: String, days: Int = shownDays) -> [BodyDay.DayValue] {
        (0..<days).map { i in
            let d = M.addDays(end, i - (days - 1))
            return BodyDay.DayValue(day: d, value: finite(values[d]))
        }
    }

    // MARK: - Body Battery

    /*
     * /wellness-service/wellness/bodyBattery/reports/daily (startDate = endDate = today):
     * a list of days, each with `bodyBatteryValuesArray` [[ms, value], ...] and
     * `bodyBatteryActivityEvent` [{eventType, eventStartTimeGmt, durationInMilliseconds, bodyBatteryImpact}].
     * `activities` is /activitylist-service/activities/search/activities for the same day.
     */
    public static func battery(_ json: Any?, activities: Any?, day: String, now: Date,
                               calendar: Calendar = GarminMorning.calendar()) -> BodyDay.Battery? {
        let entries = M.list(json, inside: ["data"])
        let entry = entries.first { M.text($0["date"]) == day || M.text($0["calendarDate"]) == day } ?? entries.first
        guard let entry else { return nil }
        guard let midnight = M.date(day, calendar: calendar).map({ calendar.startOfDay(for: $0) }) else { return nil }
        let raw = (entry["bodyBatteryValuesArray"] as? [Any]) ?? []
        var points: [BodyDay.Point] = []
        for item in raw {
            guard let pair = item as? [Any], pair.count >= 2, let ms = finite(M.number(pair[0])),
                  let v = finite(M.number(pair[1])), v >= 0, v <= 100 else { continue }
            let t = Date(timeIntervalSince1970: ms / 1000)
            if t >= midnight && t <= now.addingTimeInterval(5 * 60) { points.append(.init(time: t, value: v)) }
        }
        points.sort { $0.time < $1.time }
        guard !points.isEmpty else { return nil }

        struct Event { var start: Date; var impact: Double }
        let events: [Event] = ((entry["bodyBatteryActivityEvent"] as? [[String: Any]]) ?? []).compactMap { e in
            guard M.text(e["eventType"]) == "ACTIVITY", let start = M.parseGMT(M.text(e["eventStartTimeGmt"])),
                  let impact = finite(M.number(e["bodyBatteryImpact"])) else { return nil }
            return Event(start: start, impact: impact)
        }

        var workouts: [BodyDay.Workout] = []
        for a in M.list(activities, inside: ["data", "activities"]) {
            guard let start = M.parseGMT(M.text(a["startTimeGMT"])) else { continue }
            // Today's own workouts only: by the local start day when Garmin gives it.
            if let local = M.text(a["startTimeLocal"]), local.count >= 10, String(local.prefix(10)) != day { continue }
            let seconds = positive(a["duration"]) ?? 0
            let end = start.addingTimeInterval(seconds)
            let id = (finite(M.number(a["activityId"])).map { String(Int64($0)) }) ?? M.text(a["activityId"]) ?? String(Int(start.timeIntervalSince1970))
            let typeObj = a["activityType"] as? [String: Any]
            let type = M.text(a["activityType"]) ?? M.text(typeObj?["typeKey"]) ?? "other"
            workouts.append(.init(id: id, name: M.text(a["activityName"]) ?? "", type: type, start: start, end: end,
                                  drain: drain(start: start, end: end, events: events.map { ($0.start, $0.impact) }, points: points)))
        }
        workouts.sort { $0.start < $1.start }
        return BodyDay.Battery(points: points, workouts: workouts)
    }

    /*
     * What a workout cost, the Board's rule: Garmin's own ACTIVITY event
     * starting within 10 minutes of the workout's start gives its impact
     * (negative = cost, so the drain is its opposite); without one, the
     * reading at or before the start minus the reading at or after the end.
     */
    public static func drain(start: Date, end: Date, events: [(start: Date, impact: Double)],
                             points: [BodyDay.Point]) -> Double? {
        if let ev = events.first(where: { abs($0.start.timeIntervalSince(start)) <= 10 * 60 }) {
            return finite(-ev.impact)
        }
        guard let before = points.last(where: { $0.time <= start }),
              let after = points.first(where: { $0.time >= end }) else { return nil }
        return finite(before.value - after.value)
    }

    // MARK: - Series from the ranges

    /* dailySleepSummariesByDate: hours by day, through the morning's own reader. */
    public static func sleepDays(_ json: Any?) -> [String: Double] { M.sleepDays(json) }

    /* hrv/daily/{from}/{to}: the overnight average by day. */
    public static func hrvDays(_ json: Any?) -> [String: Double] { M.hrvDays(json) }

    /* v2/dailysummaries: resting pulse, average and highest stress by day. */
    public static func summaryDays(_ json: Any?) -> (resting: [String: Double], stressAverage: [String: Double], stressHighest: [String: Double]) {
        var rest: [String: Double] = [:], avg: [String: Double] = [:], high: [String: Double] = [:]
        for item in M.list(json, inside: ["data"]) {
            guard let d = M.text(item["calendarDate"]) else { continue }
            if let r = positive((item["heartRate"] as? [String: Any])?["restingValue"]) { rest[d] = r }
            let st = item["stress"] as? [String: Any]
            if let a = M.stressLevel(st?["avgLevel"]), let a = finite(a) { avg[d] = a }
            if let h = positive(st?["maxLevel"]) { high[d] = h }
        }
        return (rest, avg, high)
    }

    // MARK: - Putting it together

    /*
     * `day` is today's calendar date. Sleep and HRV belong to the night that
     * ended `nightDay` (today, or yesterday in the small hours).
     */
    public static func build(day: String, nightDay: String, readAt: Date, battery: BodyDay.Battery?,
                             sleepDays: [String: Double], hrv: GarminMorning.HRVNight, hrvDays: [String: Double],
                             summaries: (resting: [String: Double], stressAverage: [String: Double], stressHighest: [String: Double])) -> BodyDay {
        var sleep: BodyDay.Sleep?
        let nights = series(sleepDays, endingOn: nightDay)
        if nights.contains(where: { $0.value != nil }) {
            sleep = BodyDay.Sleep(lastNight: nights.last?.value, nights: nights)
        }

        var hrvOut: BodyDay.HRV?
        // The single-night answer wins; the range fills in when it is missing.
        let night = ((hrv.day == nil || hrv.day == nightDay) ? finite(hrv.lastNight) : nil).flatMap { $0 > 0 ? $0 : nil } ?? hrvDays[nightDay]
        var hrvSeries = hrvDays
        if let night { hrvSeries[nightDay] = night }
        let hrvLine = series(hrvSeries, endingOn: nightDay)
        if night != nil || hrvLine.contains(where: { $0.value != nil }) {
            let low = hrv.rangeLow, high = hrv.rangeHigh
            let hasRange = low != nil && high != nil
            hrvOut = BodyDay.HRV(lastNight: night, rangeLow: hasRange ? low : nil, rangeHigh: hasRange ? high : nil,
                                 stillLearning: night != nil && !hasRange, days: hrvLine)
        }

        var resting: BodyDay.Resting?
        let restLine = series(summaries.resting, endingOn: day)
        if restLine.contains(where: { $0.value != nil }) {
            resting = BodyDay.Resting(today: summaries.resting[day], normal: M.normal(of: summaries.resting, before: day).normal, days: restLine)
        }

        var stress: BodyDay.Stress?
        let stressLine = series(summaries.stressAverage, endingOn: day)
        if stressLine.contains(where: { $0.value != nil }) || summaries.stressHighest[day] != nil {
            stress = BodyDay.Stress(average: summaries.stressAverage[day], highest: summaries.stressHighest[day], days: stressLine)
        }
        return BodyDay(day: day, readAt: readAt, battery: battery, sleep: sleep, hrv: hrvOut, resting: resting, stress: stress)
    }
}
