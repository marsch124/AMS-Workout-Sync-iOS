import Foundation

/*
 * 2.9 (Body page, Gym sessions): AMS Workout Companion writes its sessions into one file in
 * iCloud Drive (Documents/03 Home/02 IT/01 SW/AMS Triathlon Training/AMS Workout Companion app to Garmin/Workout Companion sessions.json); the Garmin Board reads the same file.
 * These are the Board's reading rules, kept the same: every field checked, a session needs a valid
 * day, newest first, at most 60; the compare line against the session before; the best set per machine.
 * The app only reads; it never writes the file.
 */
public struct GymEntry: Equatable, Sendable {
    public let name: String
    public let muscle: String?
    public let sets: String?
    public let setCount: Int?
    public let topKg: Double?
    public let pain: Bool
    public init(name: String, muscle: String? = nil, sets: String? = nil, setCount: Int? = nil, topKg: Double? = nil, pain: Bool = false) {
        self.name = name; self.muscle = muscle; self.sets = sets; self.setCount = setCount; self.topKg = topKg; self.pain = pain
    }
}

public struct GymSession: Equatable, Identifiable, Sendable {
    public let id: String
    public let date: String
    public let start: String?
    public let minutes: Double?
    public let gym: String?
    public let title: String?
    public let feel: String?
    public let machines: Int?
    public let sets: Int?
    public let liftedKg: Double?
    public let bests: [String]
    public let entries: [GymEntry]
    public init(id: String, date: String, start: String? = nil, minutes: Double? = nil, gym: String? = nil, title: String? = nil,
                feel: String? = nil, machines: Int? = nil, sets: Int? = nil, liftedKg: Double? = nil, bests: [String] = [], entries: [GymEntry] = []) {
        self.id = id; self.date = date; self.start = start; self.minutes = minutes; self.gym = gym; self.title = title; self.feel = feel
        self.machines = machines; self.sets = sets; self.liftedKg = liftedKg; self.bests = bests; self.entries = entries
    }
}

public enum GymSessions {
    public static let fileName = "Workout Companion sessions.json"
    static let feels = ["great", "good", "ok", "tired", "rough"]

    private static func text(_ v: Any?, _ max: Int = 400) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(max))
    }
    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite && d >= 0 ? d : nil
    }
    private static func whole(_ v: Any?) -> Int? { number(v).map { Int($0.rounded()) } }

    private static func isDay(_ s: String) -> Bool {
        let p = s.split(separator: "-", omittingEmptySubsequences: false)
        return p.count == 3 && p[0].count == 4 && p[1].count == 2 && p[2].count == 2 && p.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    /* The sessions in the file, newest first (at most 60); empty for anything wrong (not JSON, no sessions). Never throws. */
    public static func parse(_ data: Data) -> [GymSession] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = root["sessions"] as? [Any] else { return [] }
        var list: [GymSession] = []
        for item in raw {
            guard let s = item as? [String: Any], let date = text(s["date"]), isDay(date) else { continue }
            var entries: [GymEntry] = []
            for e in ((s["entries"] as? [Any]) ?? []).prefix(60) {
                guard let e = e as? [String: Any], let name = text(e["name"], 120) else { continue }
                entries.append(GymEntry(name: name, muscle: text(e["muscle"], 60), sets: text(e["sets"], 200),
                                        setCount: whole(e["setCount"]), topKg: number(e["topKg"]), pain: (e["pain"] as? Bool) == true))
            }
            let start = text(s["start"], 40)
            let feel = text(s["feel"], 20).flatMap { feels.contains($0) ? $0 : nil }
            let bests = ((s["bests"] as? [Any]) ?? []).compactMap { text($0, 120) }.prefix(40)
            list.append(GymSession(id: text(s["id"], 80) ?? "\(date)-\(start ?? "x")", date: date, start: start, minutes: number(s["minutes"]),
                                   gym: text(s["gym"], 120), title: text(s["title"], 120), feel: feel, machines: whole(s["machines"]),
                                   sets: whole(s["sets"]), liftedKg: number(s["liftedKg"]), bests: Array(bests), entries: entries))
        }
        list.sort { ($0.date + ($0.start ?? "")) > ($1.date + ($1.start ?? "")) }
        return Array(list.prefix(60))
    }

    /* "Mon 9 Mar" (English, whatever the phone's language). */
    public static func dayText(_ key: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        guard let d = parseDayKey(key) else { return key }
        return f.string(from: d)
    }

    public static func daysAgo(_ date: String, today: String) -> Int? {
        guard let a = parseDayKey(date), let b = parseDayKey(today) else { return nil }
        return max(0, Int((b.timeIntervalSince(a) / 86400).rounded()))
    }

    public static func agoText(_ days: Int) -> String {
        days == 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
    }

    public static func feelText(_ feel: String?) -> String? { feel.map { "felt \($0)" } }

    private static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(BodyPage.grouped(Double(n))) \(n == 1 ? one : many)" }

    /* 32 as "32", 32.5 as "32.5" (a plate weight keeps its half). */
    public static func kgText(_ v: Double) -> String {
        v == v.rounded() ? BodyPage.grouped(v) : String(format: "%.1f", v)
    }

    /* "Mon 9 Mar · City Gym · 55m" */
    public static func headLine(_ s: GymSession) -> String {
        [dayText(s.date), s.gym, s.minutes.map { formatDuration($0 * 60) }].compactMap { $0 }.joined(separator: " · ")
    }

    /* 2.19 (his ask: time, not kg): the card's big figure, "1h 05m"; "–" when the file has no length. */
    public static func timeFigure(_ s: GymSession) -> String {
        guard let m = s.minutes, m > 0 else { return "\u{2013}" }
        return formatDuration(m * 60)
    }

    /* 2.19: the line under the time, "Mon 9 Mar · City Gym" (the time is the big figure above it). */
    public static func dayGymLine(_ s: GymSession) -> String {
        [dayText(s.date), s.gym].compactMap { $0 }.joined(separator: " · ")
    }

    /* "4 machines · 11 sets · felt good · 3 days ago" (the day only for the latest session). */
    public static func countsLine(_ s: GymSession, today: String?) -> String {
        var parts: [String] = []
        if let m = s.machines ?? (s.entries.isEmpty ? nil : s.entries.count) { parts.append(plural(m, "machine", "machines")) }
        if let n = s.sets { parts.append(plural(n, "set", "sets")) }
        if let f = feelText(s.feel) { parts.append(f) }
        if let today, let d = daysAgo(s.date, today: today) { parts.append(agoText(d)) }
        return parts.joined(separator: " · ")
    }

    private static func signed(_ n: Double, unit: String) -> String {
        let r = Int(n.rounded())
        return (r < 0 ? "\u{2212}" : "+") + BodyPage.grouped(Double(abs(r))) + unit
    }

    /* "vs the one before: +2 sets · −17 min" — a part is left out when either session lacks it; nil without a session before. No kg since 2.19 (his ask). */
    public static func compareLine(_ latest: GymSession, _ before: GymSession?) -> String? {
        guard let before else { return nil }
        var parts: [String] = []
        if let a = latest.sets, let b = before.sets { parts.append(signed(Double(a - b), unit: " sets")) }
        if let a = latest.minutes, let b = before.minutes { parts.append(signed(a - b, unit: " min")) }
        return parts.isEmpty ? nil : "vs the one before: " + parts.joined(separator: " · ")
    }

    private static func weight(_ t: String) -> Double? { Double(t.replacingOccurrences(of: ",", with: ".")) }

    /*
     * The best set of a machine as "90 kg × 10". The file writes sets as "80 × 12, 90 × 10 kg",
     * "50 kg × 12, 10" (bare numbers go on with the same weight), "BW × 12" (body weight) or
     * "20 min · level 5" (cardio). The best set is the heaviest weight, the most reps at it.
     * Without a parsable weight: the top weight alone, else the sets as written, else the set count.
     */
    public static func bestSet(_ e: GymEntry) -> String? {
        var best: (kg: Double, reps: Int)?
        if let raw = e.sets {
            var line = raw
            if line.hasSuffix(" kg") { line.removeLast(3) }
            var lastKg: Double?
            for token in line.components(separatedBy: ", ") {
                var t = token.trimmingCharacters(in: .whitespaces)
                if t.hasSuffix(" kg") { t.removeLast(3) }
                let sides = t.components(separatedBy: " × ")
                if sides.count == 2 {
                    var left = sides[0].trimmingCharacters(in: .whitespaces)
                    if left.hasSuffix(" kg") { left.removeLast(3) }
                    guard let reps = Int(sides[1].trimmingCharacters(in: .whitespaces)) else { lastKg = nil; continue }
                    if let kg = weight(left) {
                        lastKg = kg
                        if best == nil || kg > best!.kg || (kg == best!.kg && reps > best!.reps) { best = (kg, reps) }
                    } else { lastKg = nil }
                } else if sides.count == 1, let reps = Int(t), let kg = lastKg {
                    if best == nil || kg > best!.kg || (kg == best!.kg && reps > best!.reps) { best = (kg, reps) }
                }
            }
        }
        if let best, best.kg > 0 { return "\(kgText(best.kg)) kg × \(best.reps)" }
        if let kg = e.topKg, kg > 0 { return "\(kgText(kg)) kg" }
        if let s = e.sets { return s }
        if let n = e.setCount { return plural(n, "set", "sets") }
        return nil
    }

    /* The machine's line on the card: "Leg press · best 90 kg × 10" ("best" only when a weight is known). */
    public static func machineLine(_ e: GymEntry) -> String {
        guard let b = bestSet(e) else { return e.name }
        let weighed = b.contains(" kg")
        return e.name + " · " + (weighed ? "best " : "") + b
    }

    /* The sessions on one day (a day can hold two), newest first. */
    public static func onDay(_ list: [GymSession], _ day: String) -> [GymSession] { list.filter { $0.date == day } }
}
