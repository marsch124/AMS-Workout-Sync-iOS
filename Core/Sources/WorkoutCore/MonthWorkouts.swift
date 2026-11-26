import Foundation

/*
 * 2.9: every Garmin workout of one month, the plan's and the ones outside it
 * (walks, hikes, extra rides). Pure part: the app hands in what Garmin's
 * list of activities answered; nothing here reaches the plan.
 */
public struct MonthWorkout: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /* Garmin's own sport key: "running", "walking", "breathwork" … */
    public var type: String
    /* The day he lived it ("2026-11-25") and the clock time of the start ("18:12"), both as his own local stamp. */
    public var day: String
    public var time: String
    public var start: Date
    public var seconds: Double
    public var metres: Double?
    public var avgHr: Double?

    public init(id: String, name: String, type: String, day: String, time: String, start: Date,
                seconds: Double, metres: Double? = nil, avgHr: Double? = nil) {
        self.id = id; self.name = name; self.type = type; self.day = day; self.time = time
        self.start = start; self.seconds = seconds; self.metres = metres; self.avgHr = avgHr
    }
}

public enum MonthWorkouts {
    private typealias M = GarminMorning

    /* Garmin's list of activities, read forgivingly: a missing field is nothing, never a crash. */
    public static func parse(_ json: Any?) -> [MonthWorkout] {
        M.list(json, inside: ["data", "activities", "activityList"]).compactMap { a in
            guard let start = M.parseGMT(a["startTimeGMT"] as? String) else { return nil }
            let local = a["startTimeLocal"] as? String
            let day = local.flatMap { $0.count >= 10 ? String($0.prefix(10)) : nil } ?? M.dayKey(start)
            let time: String = {
                if let l = local, l.count >= 16 {
                    let t = Array(l)[11..<16]
                    return String(t)
                }
                let c = M.calendar().dateComponents([.hour, .minute], from: start)
                return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }()
            let id: String = (M.number(a["activityId"]).map { String(Int64($0)) }) ?? String(Int(start.timeIntervalSince1970))
            let type: String = {
                if let t = a["activityType"] as? [String: Any], let k = t["typeKey"] as? String { return k }
                return (a["activityType"] as? String) ?? "other"
            }()
            func positive(_ v: Any?) -> Double? { M.number(v).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
            return MonthWorkout(id: id, name: (a["activityName"] as? String) ?? "", type: type, day: day, time: time,
                                start: start, seconds: positive(a["duration"]) ?? 0,
                                metres: positive(a["distance"]), avgHr: positive(a["averageHR"]))
        }
    }

    /* The first day of the month that holds `day`. */
    public static func firstDay(of day: String) -> String { String(day.prefix(7)) + "-01" }

    /* Only the workouts of the month that holds `day`, newest first. */
    public static func ofMonth(_ list: [MonthWorkout], day: String) -> [MonthWorkout] {
        let month = String(day.prefix(7))
        return list.filter { $0.day.hasPrefix(month) }.sorted { $0.start > $1.start }
    }

    /* Count, total time and total distance of a list. */
    public static func totals(_ list: [MonthWorkout]) -> (count: Int, seconds: Double, metres: Double) {
        (list.count, list.reduce(0) { $0 + $1.seconds }, list.reduce(0) { $0 + ($1.metres ?? 0) })
    }

    /* "41h 43m · 321.8 km"; the time alone when no workout has a distance. */
    public static func totalsLine(_ list: [MonthWorkout]) -> String {
        let t = totals(list)
        let time = formatDuration((t.seconds / 60).rounded() * 60)
        return t.metres > 0 ? time + " · " + kilometres(t.metres) : time
    }

    /* "12.4 km", one decimal. */
    public static func kilometres(_ metres: Double) -> String {
        String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), metres / 1000)
    }

    /* Every workout of one day, earliest first. */
    public static func ofDay(_ list: [MonthWorkout], day: String) -> [MonthWorkout] {
        list.filter { $0.day == day }.sorted { $0.start < $1.start }
    }

    /* The workout as the Body Battery curve holds one, so a tap opens it the same way. */
    public static func asBodyWorkout(_ w: MonthWorkout) -> BodyDay.Workout {
        BodyDay.Workout(id: w.id, name: w.name, type: w.type, start: w.start,
                        end: w.start.addingTimeInterval(w.seconds), drain: nil)
    }

    /* The sport id the app has a colour for; nil (a grey tag) for walks, hikes, breathing and the rest. */
    public static func colourSport(_ type: String) -> String? {
        let t = type.lowercased()
        if t.contains("swim") { return "swim" }
        if t.contains("cycl") || t.contains("bik") || t.contains("ride") { return "bike" }
        if t.contains("run") { return "run" }
        if t.contains("strength") { return "strength" }
        if t.contains("row") { return "rowing" }
        return nil
    }

    /* "Wed 25 · 18:12" */
    public static func whenText(_ w: MonthWorkout) -> String {
        guard let d = M.date(w.day) else { return w.time }
        let c = M.calendar()
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let wd = names[(c.component(.weekday, from: d) - 1) % 7]
        return "\(wd) \(c.component(.day, from: d)) · \(w.time)"
    }

    /* "NOVEMBER" from "2026-11-25". */
    public static func monthName(_ day: String) -> String {
        let names = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
        let p = day.split(separator: "-")
        guard p.count >= 2, let m = Int(p[1]), (1...12).contains(m) else { return "" }
        return names[m - 1]
    }
}
