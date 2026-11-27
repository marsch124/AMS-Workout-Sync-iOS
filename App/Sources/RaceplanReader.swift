import Foundation
import SwiftUI
import WorkoutCore

/*
 * Round 30 (race-plan lane): what the forecast and the age-group card read from
 * Garmin's Personal API, kept as numbers only (never the key):
 *   /activitylist-service/activities/search/activities  the last 8 weeks' list:
 *       activityType.typeKey, duration, distance, averageHR, avgPower
 *   /fitnessage-service/fitnessage/v2/{day}  chronologicalAge, turned into an age
 *       group at once; the age itself is never kept or shown.
 * At most one read in 12 hours. No key, no answer or an unknown shape leaves the
 * cards saying what is missing. Nothing here reaches the plan.
 */
extension GarminClient {
    func raceEfforts(from: String, to: String) async throws -> [RaceEffort] {
        let answer = try await tolerant("/activitylist-service/activities/search/activities",
                                        ["startDate": from, "endDate": to, "limit": "99", "start": "0"])
        return RaceEffort.read(answer)
    }

    func chronologicalAge(day: String) async throws -> Int? {
        let answer = try await tolerant("/fitnessage-service/fitnessage/v2/" + day)
        guard let dict = answer as? [String: Any], let n = dict["chronologicalAge"] as? NSNumber else { return nil }
        let v = n.intValue
        return (10...110).contains(v) ? v : nil
    }
}

@MainActor
final class RaceplanReader: ObservableObject {
    static let shared = RaceplanReader()

    @Published private(set) var efforts: [RaceEffort] = []
    @Published private(set) var garminBracket: AgeBracket?
    @Published private(set) var reading = false

    private static let effortsKey = "raceplan.efforts.v1"
    private static let bracketKey = "raceplan.garminBracket.v1"
    private static let triedKey = "raceplan.lastTried.v1"

    /* Pictures and screen tests: invented numbers, no key, no network. */
    static var fake: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_RACEPLAN_FAKE"] != nil
        #else
        return false
        #endif
    }

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.effortsKey), let e = try? JSONDecoder().decode([RaceEffort].self, from: data) { efforts = e }
        if let l = d.string(forKey: Self.bracketKey) { garminBracket = AgeBracket.from(label: l) }
    }

    func readIfDue(today: String, raceDay: String) async {
        if Self.fake { return }
        guard GarminKey.isSaved else { return }
        let d = UserDefaults.standard
        if let last = d.object(forKey: Self.triedKey) as? Date, Date().timeIntervalSince(last) < 12 * 3600 { return }
        reading = true
        defer { reading = false }
        do {
            let list = try await GarminClient.shared.raceEfforts(from: PlanView.addDays(today, -56), to: today)
            efforts = list
            if let data = try? JSONEncoder().encode(list) { d.set(data, forKey: Self.effortsKey) }
            if let age = try await GarminClient.shared.chronologicalAge(day: today) {
                let y = { (k: String) in Int(k.prefix(4)) ?? 0 }
                let b = AgeBracket.atRace(ageNow: age, thisYear: y(today), raceYear: y(raceDay))
                garminBracket = b
                d.set(b?.label, forKey: Self.bracketKey)
            }
            d.set(Date(), forKey: Self.triedKey)
        } catch {
            // Offline or refused: keep what was read before and try again next time.
        }
    }

    func forget() {
        efforts = []; garminBracket = nil
        for k in [Self.effortsKey, Self.bracketKey, Self.triedKey] { UserDefaults.standard.removeObject(forKey: k) }
    }

    // MARK: invented, for pictures

    /* A hilly invented course with invented past results, so every card has something to show. */
    static var inventedCourse: RaceCourse {
        var c = RaceCourse.flatDefault
        c.name = "Invented hilly course"; c.bikeClimbM = 700; c.runClimbM = 120; c.julyTempC = 22
        c.bike = [CourseSection(0, 18, .flat, "Out along the lake"), CourseSection(18, 30, .climb, "The long hill"),
                  CourseSection(30, 52, .rolling, "Open plateau"), CourseSection(52, 60, .descent, "Fast way down"),
                  CourseSection(60, 78, .turns, "Through the town"), CourseSection(78, 90, .flat, "Back to the lake")]
        c.run = [CourseSection(0, 7, .flat, "Lap 1"), CourseSection(7, 14, .climb, "Lap 2"), CourseSection(14, 21.1, .flat, "Lap 3")]
        c.ageGroups = [CourseAgeGroup(bracket: "45\u{2013}49", middle: LegTimes(swim: 2220, t1: 270, bike: 11400, t2: 150, run: 7500),
                                      topThird: LegTimes(swim: 1980, t1: 220, bike: 10500, t2: 110, run: 6900))]
        c.isPlaceholder = false
        return c
    }

    static func inventedBasis() -> ForecastBasis {
        let rides = (0..<6).map { i in RaceEffort(family: "bike", typeKey: "road_biking", seconds: 7200, metres: 7200 * (7.0 + Double(i % 3) * 0.1), avgHr: 140) }
        let runs = (0..<6).map { i in RaceEffort(family: "run", typeKey: "running", seconds: 3600, metres: 3600 * (2.9 + Double(i % 3) * 0.05), avgHr: 146, avgPowerW: 215) }
        return ForecastBasis(css: 108, lthr: 164, efforts: rides + runs)
    }
    static let inventedFtp = 210.0
}
