import Foundation

/*
 * Sunrise and sunset worked out from a day and a place (the NOAA method:
 * accurate to about a minute away from the poles). Pure: no clock, no network.
 * In polar day or polar night there is no sunrise or sunset, so it gives none.
 */
public enum Daylight {

    public struct Times: Equatable {
        public let sunrise: Date
        public let sunset: Date
    }

    /* A day key ("2026-12-02") and a place: the two moments, or nil when the sun does not rise or set that day. */
    public static func times(day: String, latitude: Double, longitude: Double) -> Times? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnight = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        // Julian day of 12:00 UTC that day.
        let noonJD = midnight.timeIntervalSince1970 / 86400 + 2440587.5 + 0.5

        // Minutes after 00:00 UTC; the second pass uses the sun's place at the first answer.
        func minutes(rising: Bool, at jd: Double) -> Double? {
            let s = sun(julianDay: jd)
            let lat = latitude * .pi / 180
            let cosH = cos(90.833 * .pi / 180) / (cos(lat) * cos(s.declination)) - tan(lat) * tan(s.declination)
            guard cosH >= -1, cosH <= 1 else { return nil }
            let hourAngle = acos(cosH) * 180 / .pi
            return 720 - 4 * (longitude + (rising ? hourAngle : -hourAngle)) - s.equationOfTime
        }
        guard let r0 = minutes(rising: true, at: noonJD), let s0 = minutes(rising: false, at: noonJD),
              let r1 = minutes(rising: true, at: noonJD - 0.5 + r0 / 1440),
              let s1 = minutes(rising: false, at: noonJD - 0.5 + s0 / 1440) else { return nil }
        return Times(sunrise: midnight.addingTimeInterval(r1 * 60), sunset: midnight.addingTimeInterval(s1 * 60))
    }

    /* The sun's declination (radians) and the equation of time (minutes) at a Julian day. */
    private static func sun(julianDay jd: Double) -> (declination: Double, equationOfTime: Double) {
        let t = (jd - 2451545.0) / 36525
        let rad = Double.pi / 180
        let l0 = (280.46646 + t * (36000.76983 + 0.0003032 * t)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m * rad) * (0.019993 - 0.000101 * t) + sin(3 * m * rad) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(omega * rad)
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(omega * rad)
        let declination = asin(sin(eps * rad) * sin(lambda * rad))
        let y = pow(tan(eps * rad / 2), 2)
        let eqTime = 4 / rad * (y * sin(2 * l0 * rad) - 2 * e * sin(m * rad)
            + 4 * e * y * sin(m * rad) * cos(2 * l0 * rad) - 0.5 * y * y * sin(4 * l0 * rad)
            - 1.25 * e * e * sin(2 * m * rad))
        return (declination, eqTime)
    }
}
