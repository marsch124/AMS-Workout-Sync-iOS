import Foundation

/*
 * What the weather line on Today says, and for which sessions it appears.
 * Pure: the hours arrive as plain numbers (from any forecast), the words leave.
 * Units are metric: degrees Celsius, metres per second.
 */

public enum OutdoorSession {
    private static let indoorWords = ["indoor", "turbo", "trainer", "zwift", "rollen", "treadmill", "laufband", "spinning", "gym"]
    private static let openWaterWords = ["open water", "open-water", "openwater", "freiwasser", "sea swim", "lake"]
    private static let walkWords = ["hike", "hiking", "walk", "wandern"]

    /* Run, bike, brick, race, open-water swim, hike; never a pool swim, strength, mobility or rest; never an indoor one. */
    public static func isOutdoor(disciplineId: String, text: String) -> Bool {
        let t = text.lowercased()
        if indoorWords.contains(where: t.contains) { return false }
        switch disciplineId {
        case "run", "bike", "brick", "race": return true
        case "swim": return openWaterWords.contains(where: t.contains)
        case "strength", "mobility", "rest": return false
        default: return walkWords.contains(where: t.contains)
        }
    }

    /* A start time written in the plan ("17:30", "7.15 am" is not read): the hour and minute, else nil. */
    public static func startTime(in cells: [String: String]) -> (hour: Int, minute: Int)? {
        let keys = ["time", "start", "start time", "uhrzeit", "when", "time of day"]
        for (k, v) in cells where keys.contains(k.lowercased().trimmingCharacters(in: .whitespaces)) {
            let p = v.trimmingCharacters(in: .whitespaces).split(separator: ":")
            if p.count >= 2, let h = Int(p[0]), let m = Int(p[1].prefix(2)), (0..<24).contains(h), (0..<60).contains(m) { return (h, m) }
        }
        return nil
    }
}

public struct WeatherHour: Equatable, Codable {
    public let hour: Int
    public let tempC: Double
    public let feelsC: Double
    public let windMs: Double
    public let rainPercent: Double
    public init(hour: Int, tempC: Double, feelsC: Double, windMs: Double, rainPercent: Double) {
        self.hour = hour; self.tempC = tempC; self.feelsC = feelsC; self.windMs = windMs; self.rainPercent = rainPercent
    }
}

public enum WeatherLine {
    public static func windWord(_ ms: Double) -> String { ms < 3.4 ? "calm" : (ms < 8 ? "breezy" : "windy") }

    /*
     * "11° · feels 7° · breezy 5 m/s · rain likely 14–16", for the hours
     * from…to (both included). Feels-like only when it differs by 3° or more.
     * Nil when the forecast has no hour in that window.
     */
    public static func text(_ hours: [WeatherHour], from: Int, to: Int) -> String? {
        let h = hours.filter { $0.hour >= from && $0.hour <= max(from, to) }
        guard !h.isEmpty else { return nil }
        let n = Double(h.count)
        let temp = h.map(\.tempC).reduce(0, +) / n
        let feels = h.map(\.feelsC).reduce(0, +) / n
        let wind = h.map(\.windMs).reduce(0, +) / n
        var parts = ["\(Int(temp.rounded()))°"]
        if abs(feels - temp) >= 3 { parts.append("feels \(Int(feels.rounded()))°") }
        parts.append("\(windWord(wind)) \(Int(wind.rounded())) m/s")
        let wet = h.filter { $0.rainPercent >= 40 }.map(\.hour)
        if let a = wet.min(), let b = wet.max() { parts.append(a == b ? "rain likely \(a)" : "rain likely \(a)–\(b)") }
        else { parts.append("dry") }
        return parts.joined(separator: " · ")
    }
}
