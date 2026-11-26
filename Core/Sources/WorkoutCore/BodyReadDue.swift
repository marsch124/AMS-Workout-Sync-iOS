import Foundation

extension GarminMorning {
    /*
     * 2.9: when the Body numbers are read again. After half an hour as before, and at once on the FIRST try of a new
     * day while the numbers held are from an earlier day (AMS Tria Menu found the Mac's garmin-body.json a day old).
     * Only the first try: between midnight and the watch's sync Garmin answers empty, and that must not make the app
     * ask every few minutes.
     */
    public static func bodyReadDue(lastTried: Date?, heldDay: String?, now: Date) -> Bool {
        if mayRead(lastTried: lastTried, now: now) { return true }
        let triedToday = lastTried.map { dayKey($0) == dayKey(now) } ?? false
        guard let heldDay, !triedToday else { return false }
        return heldDay != dayKey(now)
    }
}
