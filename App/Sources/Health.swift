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

    var inUse: Bool { status == .asked && enabled }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for id in [HKQuantityTypeIdentifier.heartRate, .distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        return types
    }

    init() {
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

        let samples: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        var out: [HealthWorkout] = []
        for w in samples {
            let hr = await averageHeartRate(from: w.startDate, to: w.endDate)
            let metres = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
                ?? w.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity()?.doubleValue(for: .meter())
            out.append(HealthWorkout(id: w.uuid, sport: Self.sport(of: w.workoutActivityType), typeName: Self.name(of: w.workoutActivityType),
                                     start: w.startDate, seconds: w.duration, metres: metres, avgHr: hr, source: w.sourceRevision.source.name))
        }
        return out
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
                          metres: 2_900, avgHr: 92, source: "Garmin Connect")
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
            let km = metres / 1000
            if seconds > 0 {
                switch disciplineId {
                case "bike", "brick":
                    v["avgPace"] = jsNumberString((km / (seconds / 3600) * 10).rounded() / 10)
                case "swim":
                    let per100 = seconds / (metres / 100)
                    v["avgPace"] = clock(per100)
                default:
                    v["avgPace"] = clock(seconds / km)
                }
            }
        }
        if let avgHr { v["avgHr"] = String(Int(avgHr.rounded())) }
        return v
    }

    private func clock(_ s: Double) -> String {
        let total = Int(s.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    var summary: String {
        var parts = [formatDuration(seconds)]
        if let metres, metres > 0 { parts.append(metres >= 1000 ? jsNumberString((metres / 100).rounded() / 10) + " km" : "\(Int(metres)) m") }
        if let avgHr { parts.append("\(Int(avgHr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }
}
