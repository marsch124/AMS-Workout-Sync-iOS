import Foundation

/*
 * 2.19 Routes: one map with every outdoor route from Garmin. Pure part: which
 * Garmin type words are outdoor and to which sport they belong, how a long
 * track is thinned for drawing, the month's day keys, and the region around
 * several tracks. Nothing here reads the network or a file.
 */
public enum Routes31 {
    public static let maxPoints = 400

    /* The four sports of the map, in the order of the chips. */
    public static let sports = ["run", "bike", "swim", "hike"]

    /*
     * "run", "bike", "swim" or "hike" for an outdoor activity with GPS; nil for
     * indoor, treadmill, trainer, pool, strength and anything unknown.
     */
    public static func sport(ofGarmin typeKey: String) -> String? {
        let t = typeKey.lowercased()
        for word in ["indoor", "treadmill", "virtual", "trainer", "pool", "lap_swimming", "strength", "yoga", "cardio"] where t.contains(word) { return nil }
        if t.contains("swim") { return t.contains("open_water") ? "swim" : nil }
        if t.contains("hik") || t.contains("walk") { return "hike" }
        if t.contains("run") { return "run" }
        if t.contains("cycl") || t.contains("bik") || t.contains("ride") { return "bike" }
        return nil
    }

    /* At most `limit` points, evenly spread, the first and the last always kept. */
    public static func thin(_ track: [GarminCoordinate], limit: Int = maxPoints) -> [GarminCoordinate] {
        guard limit >= 2, track.count > limit else { return track }
        let last = track.count - 1
        return (0..<limit).map { track[Int((Double($0) * Double(last) / Double(limit - 1)).rounded())] }
    }

    // MARK: months, as "2026-11"

    public static func monthKey(ofDay day: String) -> String { String(day.prefix(7)) }

    public static func firstDay(_ month: String) -> String { month + "-01" }

    public static func lastDay(_ month: String) -> String {
        let p = month.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return month + "-28" }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return month + "-" + String(format: "%02d", days[(m - 1) % 12])
    }

    public static func shift(_ month: String, by n: Int) -> String {
        let p = month.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return month }
        let index = y * 12 + (m - 1) + n
        return String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }

    public static func monthTitle(_ month: String) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let p = month.split(separator: "-")
        guard p.count == 2, let m = Int(p[1]), (1...12).contains(m) else { return month }
        return names[m - 1] + " " + String(p[0])
    }

    // MARK: the region around several tracks

    public struct Region: Equatable {
        public var minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
        public var centreLat: Double { (minLat + maxLat) / 2 }
        public var centreLon: Double { (minLon + maxLon) / 2 }
    }

    public static func region(of tracks: [[GarminCoordinate]]) -> Region? {
        let all = tracks.flatMap { $0 }
        guard let f = all.first else { return nil }
        var r = Region(minLat: f.lat, maxLat: f.lat, minLon: f.lon, maxLon: f.lon)
        for c in all {
            r.minLat = min(r.minLat, c.lat); r.maxLat = max(r.maxLat, c.lat)
            r.minLon = min(r.minLon, c.lon); r.maxLon = max(r.maxLon, c.lon)
        }
        return r
    }
}
