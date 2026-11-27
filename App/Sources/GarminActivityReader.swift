import Foundation
import SwiftUI
import WorkoutCore

/*
 * A finished session as Garmin holds it (route, pulse curve, laps) and the
 * week's time in pulse zones. Reads only when a done session's page opens or
 * Progress appears, and keeps numbers only (never the key, never a picture)
 * in Application Support: one small file per Garmin activity, one for the
 * zones. Shown only: nothing here reaches the plan. No key, no answer, or a
 * shape this code does not know simply leaves the section out.
 */
@MainActor
final class GarminActivityReader: ObservableObject {
    static let shared = GarminActivityReader()

    /* By session key. */
    @Published private(set) var details: [String: GarminActivityDetail] = [:]
    @Published private(set) var zones: GarminZoneWeeks.Result?
    /* 2.20: the week's zones are being read / Garmin did not answer the last read (the card says so). */
    @Published private(set) var zonesReading = false
    @Published private(set) var zonesFailed = false

    private struct ZoneFile: Codable { var weekStart: String; var result: GarminZoneWeeks.Result; var lastTried: Date?; var failed: Bool? }
    private var zoneFile: ZoneFile?

    /* Shared with the Routes reader: one small file per Garmin activity, the same format. */
    static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("garmin-activities", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func cacheURL(activityId: Int) -> URL { folder.appendingPathComponent("\(activityId).json") }
    private static var zoneURL: URL { folder.appendingPathComponent("zones-week.json") }

    init() {
        if let data = try? Data(contentsOf: Self.zoneURL), let f = try? JSONDecoder().decode(ZoneFile.self, from: data) {
            zoneFile = f
            zonesFailed = f.failed ?? false
        }
    }

    /* What the screens show: only while a key is saved. */
    func detail(for key: String) -> GarminActivityDetail? { GarminKey.isSaved ? details[key] : nil }
    var zonesShown: GarminZoneWeeks.Result? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_ZONES_CARD"] != nil { return Self.inventedZones }
        #endif
        return GarminKey.isSaved ? zones.flatMap { $0.any ? $0 : nil } : nil
    }

    /* The key was changed or removed: nothing of the old account stays. */
    func forget() {
        details = [:]
        RoutesReader.shared.forget()
        zones = nil
        zoneFile = nil
        zonesFailed = false
        try? FileManager.default.removeItem(at: Self.folder)
    }

    // MARK: one done session

    /* Called when a done session's page opens. */
    func load(key: String, day: String, sport: String, seconds: Double?) async {
        #if DEBUG
        if GarminKey.isFake { details[key] = Self.invented(sport: sport); return }
        #endif
        guard GarminKey.isSaved else { return }
        do {
            let list = try await GarminClient.shared.activities(from: day, to: day)
            guard let found = GarminActivity.match(day: day, sport: sport, seconds: seconds, among: list) else { return }
            let file = Self.folder.appendingPathComponent("\(found.id).json")
            if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(GarminActivityDetail.self, from: data) {
                details[key] = cached
                return
            }
            let recording = try await GarminClient.shared.recording(activityId: found.id)
            let made = GarminActivityDetail(activityId: found.id, typeKey: found.typeKey, avgHr: found.avgHr, maxHr: found.maxHr, recording: recording)
            // Nothing found in it is not worth keeping: ask again next time.
            guard !recording.isEmpty || made.avgHr != nil else { return }
            details[key] = made
            if let data = try? JSONEncoder().encode(made) { try? data.write(to: file, options: .atomic) }
        } catch {
            // A shape or a failure we do not know: the section stays out.
        }
    }

    // MARK: the week's zones

    /*
     * Called when Progress appears (2.20: by the page itself — the card used to ask only once it was already
     * showing, so it never showed): at most one read in 30 minutes, 2 minutes after one Garmin did not
     * answer, at once on "Tap to try again". A new week starts from nothing.
     */
    func loadZones(today: String, force: Bool = false) async {
        let monday = PlanView.weekStart(today)
        if let f = zoneFile, f.weekStart == monday { zones = f.result }
        #if DEBUG
        if GarminKey.isFake { zones = Self.inventedZones; return }
        #endif
        let sameWeek = zoneFile?.weekStart == monday
        guard GarminKey.isSaved, !zonesReading,
              force || !sameWeek || GarminMorning.mayRead(lastTried: zoneFile?.lastTried, failed: zoneFile?.failed ?? false, now: Date()) else { return }
        zonesReading = true
        do {
            let list = try await GarminClient.shared.activities(from: GarminMorning.addDays(monday, -7), to: today)
            let result = GarminZoneWeeks.build(list, weekStart: monday)
            zones = result
            zoneFile = ZoneFile(weekStart: monday, result: result, lastTried: Date(), failed: nil)
        } catch {
            let empty = GarminZoneWeeks.Result(thisWeek: [0, 0, 0, 0, 0], lastWeek: [0, 0, 0, 0, 0])
            zoneFile = ZoneFile(weekStart: monday, result: sameWeek ? (zoneFile?.result ?? empty) : empty, lastTried: Date(), failed: true)
        }
        zonesFailed = zoneFile?.failed ?? false
        zonesReading = false
        if let data = try? JSONEncoder().encode(zoneFile) { try? data.write(to: Self.zoneURL, options: .atomic) }
    }

    // MARK: invented, for pictures

    static var inventedZones: GarminZoneWeeks.Result {
        // Decimal points on purpose: GitHub's Xcode refuses whole numbers in a list of Doubles here (25 Nov 2026).
        GarminZoneWeeks.Result(thisWeek: [14.0 * 60, 190.0 * 60, 52.0 * 60, 18.0 * 60, 4.0 * 60],
                               lastWeek: [20.0 * 60, 160.0 * 60, 61.0 * 60, 9.0 * 60, 0.0])
    }

    #if DEBUG
    /* An invented loop, an invented pulse curve and six laps; no network and no key. */
    static func invented(sport: String) -> GarminActivityDetail {
        let track = (0..<120).map { i -> GarminCoordinate in
            let a = Double(i) / 120 * 2 * .pi
            return GarminCoordinate(lat: 47.0 + 0.012 * sin(a) + 0.003 * sin(3 * a), lon: 8.0 + 0.018 * cos(a))
        }
        let pulse = (0..<150).map { i -> Int in
            let t = Double(i) / 150
            return Int(128 + 22 * sin(t * 9) * (0.4 + t) + 8 * t)
        }
        let swim = sport == "swim"
        let lapCount = Int(ProcessInfo.processInfo.environment["AMSWS_FAKE_LAPS"] ?? "") ?? (swim ? 12 : 6)
        let laps = (1...lapCount).map { n in
            GarminLap(number: n, metres: swim ? 100 : 1000, seconds: swim ? 104 + Double(n % 4) * 3 : 300 + Double(n * 4), avgHr: Double(132 + (n % 8) * 3),
                      speedMps: swim ? nil : 3.3 - Double(n % 8) * 0.01, powerW: sport == "bike" ? Double(180 + (n % 8) * 3) : nil)
        }
        return GarminActivityDetail(activityId: 0, typeKey: sport == "swim" ? "lap_swimming" : "running", avgHr: 138, maxHr: 156,
                                    recording: GarminRecording(track: sport == "swim" ? [] : track, pulse: pulse, laps: laps))
    }
    #endif
}
