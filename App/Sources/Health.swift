import Foundation
import HealthKit
import WorkoutCore

/*
 * What Apple Health recorded — his Garmin sends every workout there — offered
 * to the log form so a session is logged by checking numbers rather than
 * typing them.
 *
 * Read only, and it only ever fills the form: nothing goes into the workbook
 * until Save is pressed, the same rule as the spoken form. Health is asked for
 * workouts, heart rate and distance, nothing else.
 */
struct HealthWorkout: Identifiable, Equatable {
    let id: UUID
    let sport: String          // the app's discipline id, or "other"
    let typeName: String
    let start: Date
    let seconds: Double
    let metres: Double?
    let avgHr: Double?
    let source: String
}

@MainActor
final class HealthImport: ObservableObject {
    static let shared = HealthImport()

    private let store = HKHealthStore()
    @Published private(set) var status: Status = .unknown

    /*
     * Whether the app reads Health at all. iOS does not let an app give its
     * own permission back — only the Health app can — so this is the switch
     * the app can honour itself: off, and nothing is asked of Health again.
     */
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "health.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "health.enabled") }
    }

    enum Status: Equatable { case unavailable, unknown, asked, denied }

    /* What Health said when it was last asked — shown in Settings. */
    struct Probe: Equatable {
        var at: Date
        var lastWeek: Int
        var error: String?
        var asked: String
        var anyAtAll: Int
    }

    /* The last error from a day's query, if there was one. */
    @Published private(set) var lastError: String?

    var inUse: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_FAKE_HEALTH"] != nil { return true }
        #endif
        return status == .asked && enabled
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for id in [HKQuantityTypeIdentifier.heartRate, .distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        return types
    }

    init() {
        #if DEBUG
        // A test starts from nothing, whoever is built first: the Store clears
        // these too, but this object can be made before the Store is.
        if ProcessInfo.processInfo.environment["AMSWS_RESET"] != nil {
            UserDefaults.standard.removeObject(forKey: "health.asked")
            UserDefaults.standard.removeObject(forKey: "health.enabled")
            enabled = true
        }
        // A screen walk with the fake Health sees the screens he sees: asked
        // and in use. Never write that into a simulator's own preferences —
        // `simctl spawn defaults write` lands in a domain the app cannot
        // clear, and it stayed behind and reddened a test (2026-09-30).
        if ProcessInfo.processInfo.environment["AMSWS_FAKE_HEALTH"] != nil {
            status = .asked
            enabled = true
            return
        }
        #endif
        status = isAvailable ? (UserDefaults.standard.bool(forKey: "health.asked") ? .asked : .unknown) : .unavailable
    }

    /* iOS never says whether reading was granted — only that the question was put. */
    func requestAccess() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: "health.asked")
            status = .asked
        } catch {
            status = .denied
        }
    }

    static func sport(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .swimming: return "swim"
        case .cycling, .handCycling: return "bike"
        case .running, .trackAndField: return "run"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining: return "strength"
        case .rowing: return "rowing"
        case .yoga, .flexibility, .cooldown, .pilates: return "mobility"
        case .walking, .hiking: return "walk"
        default: return "other"
        }
    }

    static func name(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .swimming: return "Swim"
        case .cycling: return "Ride"
        case .running: return "Run"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .yoga: return "Yoga"
        case .rowing: return "Rowing"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .coreTraining: return "Core"
        case .crossTraining: return "Cross training"
        default: return "Workout"
        }
    }

    /* Every workout that started on that calendar day, newest first. */
    func workouts(on dayKey: String) async -> [HealthWorkout] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_FAKE_HEALTH"] != nil { return Self.fakes(dayKey) }
        #endif
        guard isAvailable, enabled, let day = parseDayKey(dayKey) else { return [] }
        // The sheet's day is a calendar date; Health's workouts are instants in local time.
        let local = Calendar.current
        let comps = utc.dateComponents([.year, .month, .day], from: day)
        guard let start = local.date(from: comps), let end = local.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let answer = await ask(predicate, limit: 50)
        lastError = answer.error
        let samples = answer.samples

        var out: [HealthWorkout] = []
        for w in samples {
            let hr = await averageHeartRate(from: w.startDate, to: w.endDate)
            let metres = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
                ?? w.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity()?.doubleValue(for: .meter())
            let sport = Self.sport(of: w.workoutActivityType)
            out.append(HealthWorkout(id: w.uuid, sport: sport, typeName: Self.name(of: w.workoutActivityType),
                                     start: w.startDate, seconds: w.duration,
                                     metres: metres, avgHr: hr, source: w.sourceRevision.source.name))
        }
        return out
    }

    /*
     * One workout query, and what Health said about it.
     *
     * The error used to be thrown away, so a refusal and an empty day looked
     * the same — and there was nothing to show him when his run was in the
     * Health app and not in ours (2026-09-30).
     */
    private func ask(_ predicate: NSPredicate?, limit: Int) async -> (samples: [HKWorkout], error: String?) {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: limit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, error in
                continuation.resume(returning: ((results as? [HKWorkout]) ?? [], error?.localizedDescription))
            }
            store.execute(query)
        }
    }

    /*
     * What Health hands over when nothing is asked of a particular day: the
     * last week, whatever iOS says about the app, and any error. Enough to
     * tell "nothing there" from "nothing allowed" without me guessing.
     */
    func probe() async -> Probe {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_FAKE_HEALTH"] != nil {
            return Probe(at: Date(), lastWeek: 3, error: nil, asked: "iOS has been asked", anyAtAll: 3)
        }
        #endif
        guard isAvailable else { return Probe(at: Date(), lastWeek: 0, error: "Health is not on this device", asked: "—", anyAtAll: 0) }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        let week = await ask(HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate), limit: 50)
        // No dates at all: if this is empty too, nothing is reaching the app.
        let ever = await ask(nil, limit: 5)
        let asked: String
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .notDetermined: asked = "iOS says this app has never asked"
        case .sharingDenied: asked = "iOS has been asked"
        case .sharingAuthorized: asked = "iOS has been asked"
        @unknown default: asked = "iOS status unknown"
        }
        return Probe(at: Date(), lastWeek: week.samples.count, error: week.error ?? ever.error,
                     asked: asked, anyAtAll: ever.samples.count)
    }

    private func averageHeartRate(from: Date, to: Date) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                let bpm = stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    #if DEBUG
    static func fakes(_ dayKey: String) -> [HealthWorkout] {
        let day = parseDayKey(dayKey) ?? Date()
        return [
            HealthWorkout(id: UUID(), sport: "bike", typeName: "Ride", start: day.addingTimeInterval(7 * 3600), seconds: 4210,
                          metres: 32_450, avgHr: 148, source: "Garmin Connect"),
            HealthWorkout(id: UUID(), sport: "walk", typeName: "Walk", start: day.addingTimeInterval(12 * 3600), seconds: 2100,
                          metres: 2_900, avgHr: 92, source: "Garmin Connect"),
            // His pool swim of 21 September: 47 minutes in all, 1,275 m, and
            // Garmin's 1:56 per 100 m — about 24.7 minutes actually swimming.
            HealthWorkout(id: UUID(), sport: "swim", typeName: "Pool swim", start: day.addingTimeInterval(6 * 3600), seconds: 2790,
                          metres: 1_275, avgHr: 100, source: "Garmin Connect")
        ]
    }
    #endif
}

extension HealthWorkout {
    /* The form's boxes, filled from this workout: minutes, distance in the box's unit, HR, and a pace the sport understands. */
    func formValues(for disciplineId: String) -> [String: String] {
        var v: [String: String] = [:]
        v["actualDuration"] = String(Int((seconds / 60).rounded()))
        if let metres, metres > 0 {
            let unit = LogForm.distanceUnit(for: disciplineId)
            if unit == "m" {
                v["actualDistance"] = String(Int(metres.rounded()))
            } else {
                v["actualDistance"] = jsNumberString((metres / 1000 * 100).rounded() / 100)
            }
        }
        // No pace or speed. Garmin's own figure is not in Apple Health, and one
        // worked out here from the whole session is wrong for any workout with
        // rest in it — a 1:56 swim came out as 3:39 (2026-09-21). He types it
        // from Garmin Connect: "There is nothing for you to calculate."
        if let avgHr { v["avgHr"] = String(Int(avgHr.rounded())) }
        return v
    }

    var summary: String {
        var parts = [formatDuration(seconds)]
        if let metres, metres > 0 { parts.append(metres >= 1000 ? jsNumberString((metres / 100).rounded() / 10) + " km" : "\(Int(metres)) m") }
        if let avgHr { parts.append("\(Int(avgHr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }
}
