import Foundation

/*
 * The morning's numbers from Garmin, and how they are made from Garmin's
 * answers. Shown only: nothing here ever changes the plan or leads to a
 * suggestion (his decision).
 *
 * This file is the pure part — no network, no key. The app asks Garmin and
 * hands the answers (already read as JSON) to these functions. Every field is
 * optional and every reader forgives: a missing field, a number that is a
 * string, an answer wrapped one level deeper than the description says, or
 * nothing at all gives "no number", never a crash.
 *
 * Which day is "last night": the night that ends this morning. Garmin dates a
 * night by the day you wake up, so last night belongs to today's date — except
 * in the small hours (before 04:00), when that night has not ended yet and
 * the last finished one belongs to yesterday.
 *
 * His own normal is the average of the days before the morning shown, a
 * fortnight at most, and there is none until four days are there (the same
 * rule as Apple Health's, Fortnight).
 */
public struct MorningNumbers: Codable, Equatable {

    /* One number, and his own fortnight beside it. */
    public struct Figure: Codable, Equatable {
        public var value: Double
        public var normal: Double?
        /* How many earlier days the normal stands on. */
        public var days: Int
        public init(value: Double, normal: Double? = nil, days: Int = 0) {
            self.value = value
            self.normal = normal
            self.days = days
        }
    }

    /* The morning these numbers belong to, "2026-11-25". */
    public var day: String
    /* When this app read them from Garmin. */
    public var readAt: Date
    /* When the watch last sent its numbers to Garmin, if Garmin said. */
    public var watchSynced: Date?
    public var sleepHours: Figure?
    public var hrv: Figure?
    /* Garmin's own "balanced" range for the HRV average, when it gives one. */
    public var hrvRangeLow: Int?
    public var hrvRangeHigh: Int?
    public var resting: Figure?
    public var bodyBattery: Figure?
    /* Yesterday's average stress. */
    public var stress: Figure?

    public init(day: String, readAt: Date, watchSynced: Date? = nil, sleepHours: Figure? = nil, hrv: Figure? = nil,
                hrvRangeLow: Int? = nil, hrvRangeHigh: Int? = nil, resting: Figure? = nil,
                bodyBattery: Figure? = nil, stress: Figure? = nil) {
        self.day = day
        self.readAt = readAt
        self.watchSynced = watchSynced
        self.sleepHours = sleepHours
        self.hrv = hrv
        self.hrvRangeLow = hrvRangeLow
        self.hrvRangeHigh = hrvRangeHigh
        self.resting = resting
        self.bodyBattery = bodyBattery
        self.stress = stress
    }

    public var isEmpty: Bool {
        sleepHours == nil && hrv == nil && resting == nil && bodyBattery == nil && stress == nil
    }
}

/* What the app keeps on the phone: numbers only, never the key. */
public struct GarminMorningFile: Codable, Equatable {
    public var numbers: MorningNumbers?
    /* Body Battery at waking, one value a day, to make its own normal from. */
    public var bodyBatteryDays: [String: Double]
    /* The last time a read was started, to read at most once in 30 minutes. */
    public var lastTried: Date?

    public init(numbers: MorningNumbers? = nil, bodyBatteryDays: [String: Double] = [:], lastTried: Date? = nil) {
        self.numbers = numbers
        self.bodyBatteryDays = bodyBatteryDays
        self.lastTried = lastTried
    }
}

public enum GarminMorning {

    public static let readEvery: TimeInterval = 30 * 60
    public static let fortnight = 14

    // MARK: - Days

    public static func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    public static func dayKey(_ date: Date, calendar: Calendar = GarminMorning.calendar()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public static func date(_ key: String, calendar: Calendar = GarminMorning.calendar()) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    public static func addDays(_ key: String, _ n: Int, calendar: Calendar = GarminMorning.calendar()) -> String {
        guard let d = date(key, calendar: calendar), let moved = calendar.date(byAdding: .day, value: n, to: d) else { return key }
        return dayKey(moved, calendar: calendar)
    }

    /* The morning whose night is the last one that ended: today, or before 04:00 yesterday. */
    public static func morningDay(now: Date, calendar: Calendar = GarminMorning.calendar()) -> String {
        let today = dayKey(now, calendar: calendar)
        return calendar.component(.hour, from: now) < 4 ? addDays(today, -1, calendar: calendar) : today
    }

    /* Garmin's GMT stamps come without a "Z" ("2026-11-25T06:12:00.0"): they are GMT all the same. */
    public static func parseGMT(_ text: String?) -> Date? {
        guard var s = text?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: " ", with: "T")
        if !(s.hasSuffix("Z") || s.contains("+") || s.dropFirst(10).contains("-")) { s += "Z" }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fraction.date(from: s) ?? plain.date(from: s)
    }

    /* When the access token runs out: the "exp" in the middle part of the token, if it has one. */
    public static func tokenExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = number(obj["exp"]), exp > 0 else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - Reading Garmin's answers (forgiving)

    static func number(_ any: Any?) -> Double? {
        // Round 28 safety: "NaN", "inf" or an absurd figure from the service is no number (it would crash a rounding to Int).
        func sane(_ v: Double?) -> Double? { v.flatMap { $0.isFinite && abs($0) < 1e15 ? $0 : nil } }
        if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return sane(n.doubleValue) }
        if let s = any as? String { return sane(Double(s.trimmingCharacters(in: .whitespaces))) }
        return nil
    }

    static func text(_ any: Any?) -> String? { any as? String }

    /* The object itself, or the object one level down under one of these names. */
    static func object(_ json: Any?, inside names: [String] = []) -> [String: Any]? {
        guard let dict = json as? [String: Any] else { return nil }
        for n in names { if let inner = dict[n] as? [String: Any] { return inner } }
        return dict
    }

    /* A list, bare or wrapped one level down under any key. */
    static func list(_ json: Any?, inside names: [String] = []) -> [[String: Any]] {
        if let a = json as? [[String: Any]] { return a }
        guard let dict = json as? [String: Any] else { return [] }
        for n in names { if let a = dict[n] as? [[String: Any]] { return a } }
        for v in dict.values { if let a = v as? [[String: Any]] { return a } }
        return []
    }

    /* Seconds of sleep as hours; none for a night with no sleep recorded. */
    static func hours(_ seconds: Any?) -> Double? {
        guard let s = number(seconds), s > 0 else { return nil }
        return s / 3600
    }

    /* Stress comes as -1 when the watch could not tell. */
    static func stressLevel(_ any: Any?) -> Double? {
        guard let s = number(any), s >= 0 else { return nil }
        return s
    }

    public struct SleepNight: Equatable {
        public var day: String? = nil
        public var hours: Double? = nil
    }

    /* /sleep-service/sleep/dailySleep — the night, filed under the day he woke. */
    public static func sleep(_ json: Any?) -> SleepNight {
        guard let o = object(json, inside: ["dailySleepDTO"]) else { return SleepNight(day: nil, hours: nil) }
        return SleepNight(day: text(o["calendarDate"]), hours: hours(o["sleepTimeSeconds"]))
    }

    /* /sleep-service/sleep/dailySleepSummariesByDate — hours by day. */
    public static func sleepDays(_ json: Any?) -> [String: Double] {
        var out: [String: Double] = [:]
        for item in list(json, inside: ["dailySleepDTOs", "sleepSummaries"]) {
            let o = (item["dailySleepDTO"] as? [String: Any]) ?? item
            if let d = text(o["calendarDate"]), let h = hours(o["sleepTimeSeconds"]) { out[d] = h }
        }
        return out
    }

    public struct HRVNight: Equatable {
        public var day: String? = nil
        public var lastNight: Double? = nil
        public var weeklyAverage: Double? = nil
        public var rangeLow: Int? = nil
        public var rangeHigh: Int? = nil
    }

    private static func hrvOf(_ s: [String: Any]) -> HRVNight {
        let base = s["baseline"] as? [String: Any]
        return HRVNight(day: text(s["calendarDate"]), lastNight: number(s["lastNightAvg"]), weeklyAverage: number(s["weeklyAvg"]),
                        rangeLow: number(base?["balancedLow"]).map { Int($0) }, rangeHigh: number(base?["balancedUpper"]).map { Int($0) })
    }

    /* /hrv-service/hrv/{day} — the overnight average and Garmin's balanced range. */
    public static func hrv(_ json: Any?) -> HRVNight {
        guard let o = object(json) else { return HRVNight() }
        return hrvOf((o["hrvSummary"] as? [String: Any]) ?? o)
    }

    /* /hrv-service/hrv/daily/{from}/{to} — the overnight average by day. */
    public static func hrvDays(_ json: Any?) -> [String: Double] {
        var out: [String: Double] = [:]
        for s in list(json, inside: ["hrvSummaries"]) {
            let n = hrvOf(s)
            if let d = n.day, let v = n.lastNight, v > 0 { out[d] = v }
        }
        return out
    }

    public struct DaySummary: Equatable {
        public var day: String? = nil
        public var resting: Double? = nil
        public var bodyBatteryAtWake: Double? = nil
        public var stress: Double? = nil
        public var watchSynced: Date? = nil
    }

    /* /usersummary-service/usersummary/daily — one day, flat. */
    public static func summary(_ json: Any?) -> DaySummary {
        guard let o = object(json) else { return DaySummary() }
        return DaySummary(day: text(o["calendarDate"]),
                          resting: number(o["restingHeartRate"]).flatMap { $0 > 0 ? $0 : nil },
                          bodyBatteryAtWake: number(o["bodyBatteryAtWakeTime"]).flatMap { $0 > 0 ? $0 : nil },
                          stress: stressLevel(o["averageStressLevel"]),
                          watchSynced: parseGMT(text(o["lastSyncTimestampGMT"])))
    }

    /* /usersummary-service/v2/dailysummaries — resting heart rate and average stress by day. */
    public static func summaryDays(_ json: Any?) -> (resting: [String: Double], stress: [String: Double]) {
        var rest: [String: Double] = [:], stress: [String: Double] = [:]
        for item in list(json, inside: ["data"]) {
            guard let d = text(item["calendarDate"]) else { continue }
            if let r = number((item["heartRate"] as? [String: Any])?["restingValue"]), r > 0 { rest[d] = r }
            if let s = stressLevel((item["stress"] as? [String: Any])?["avgLevel"]) { stress[d] = s }
        }
        return (rest, stress)
    }

    // MARK: - His own normal

    /* The average of the days before `day`, a fortnight at most; none until enough days are there. */
    public static func normal(of days: [String: Double], before day: String) -> (normal: Double?, days: Int) {
        let from = addDays(day, -fortnight)
        let earlier = days.filter { $0.key < day && $0.key >= from }.map(\.value)
        guard earlier.count >= Fortnight.daysNeeded else { return (nil, earlier.count) }
        return (earlier.reduce(0, +) / Double(earlier.count), earlier.count)
    }

    private static func figure(_ value: Double?, _ history: [String: Double], day: String) -> MorningNumbers.Figure? {
        guard let value else { return nil }
        let n = normal(of: history, before: day)
        return MorningNumbers.Figure(value: value, normal: n.normal, days: n.days)
    }

    /*
     * Puts the answers together. `today` are the answers about this morning,
     * the dictionaries are the fortnight before it; a number missing from
     * today's own answer is looked for in the fortnight's, under today's day.
     */
    public static func build(day: String, readAt: Date,
                             sleep: SleepNight, hrv: HRVNight, summary: DaySummary,
                             sleepDays: [String: Double], hrvDays: [String: Double],
                             restingDays: [String: Double], stressDays: [String: Double],
                             bodyBatteryDays: [String: Double]) -> MorningNumbers {
        let yesterday = addDays(day, -1)
        // A night filed under another day than this morning is not this morning's.
        let sleepToday = (sleep.day == nil || sleep.day == day) ? sleep.hours : nil
        let hrvToday = (hrv.day == nil || hrv.day == day) ? hrv.lastNight : nil
        let summaryToday = (summary.day == nil || summary.day == day) ? summary : DaySummary()
        let rest = summaryToday.resting ?? restingDays[day]
        let wake = summaryToday.bodyBatteryAtWake
        let stressYesterday = stressDays[yesterday]
        return MorningNumbers(
            day: day, readAt: readAt, watchSynced: summaryToday.watchSynced,
            sleepHours: figure(sleepToday ?? sleepDays[day], sleepDays, day: day),
            hrv: figure(hrvToday ?? hrvDays[day], hrvDays, day: day),
            hrvRangeLow: hrv.rangeLow, hrvRangeHigh: hrv.rangeHigh,
            resting: figure(rest, restingDays, day: day),
            bodyBattery: figure(wake, bodyBatteryDays, day: day),
            stress: figure(stressYesterday, stressDays, day: yesterday))
    }

    // MARK: - When

    /* Green dot: the numbers are this morning's. Grey: older. */
    public static func isFromThisMorning(_ numbers: MorningNumbers, today: String) -> Bool {
        numbers.day == today && !numbers.isEmpty
    }

    /* At most one read in half an hour. */
    public static func mayRead(lastTried: Date?, now: Date) -> Bool {
        guard let lastTried else { return true }
        return now.timeIntervalSince(lastTried) >= readEvery || now < lastTried
    }
}
