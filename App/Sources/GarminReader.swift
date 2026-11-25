import Foundation
import SwiftUI
import WorkoutCore

/*
 * The morning's Garmin numbers, as Today and the plate show them. Reads at
 * most once in half an hour, when Today appears, and keeps the last reading
 * in Application Support (numbers only — never the key) so the line shows at
 * once on launch. Shown only: nothing here reaches the plan.
 */
@MainActor
final class GarminReader: ObservableObject {
    static let shared = GarminReader()

    @Published private(set) var numbers: MorningNumbers?
    @Published private(set) var reading = false
    @Published private(set) var problem: String?
    @Published private(set) var keySaved = GarminKey.isSaved

    private var file = GarminMorningFile()

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-morning.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(GarminMorningFile.self, from: data) {
            file = f
            numbers = f.numbers
        }
        #if DEBUG
        if GarminKey.isFake {
            let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] ?? GarminMorning.morningDay(now: Date())
            numbers = Self.invented(day: day)
        }
        #endif
    }

    /* What the screens show: only while a key is saved. */
    var shown: MorningNumbers? { keySaved ? numbers.flatMap { $0.isEmpty ? nil : $0 } : nil }

    func keyChanged() {
        keySaved = GarminKey.isSaved
        if !keySaved {
            numbers = nil
            problem = nil
            file = GarminMorningFile()
            try? FileManager.default.removeItem(at: Self.fileURL)
        }
    }

    /* Called when Today appears: at most one read in 30 minutes. */
    func readIfDue(today: String) async {
        guard keySaved, !GarminKey.isFake, GarminMorning.mayRead(lastTried: file.lastTried, now: Date()) else { return }
        await read(today: today)
    }

    /* "Read again now" ignores the half hour. */
    func read(today: String) async {
        guard keySaved, !GarminKey.isFake, !reading else { return }
        reading = true
        problem = nil
        file.lastTried = Date()
        let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] != nil ? today : GarminMorning.morningDay(now: Date())
        do {
            let fresh = try await GarminClient.shared.morning(day: day, bodyBatteryDays: file.bodyBatteryDays)
            // An empty answer (the watch has not sent its night yet) never replaces numbers already held.
            if !fresh.isEmpty || numbers == nil {
                numbers = fresh
                file.numbers = fresh
                if let wake = fresh.bodyBattery?.value { file.bodyBatteryDays[day] = wake }
                file.bodyBatteryDays = file.bodyBatteryDays.filter { $0.key >= GarminMorning.addDays(day, -20) }
            }
        } catch let f as GarminFailure {
            problem = f.words
        } catch {
            problem = GarminFailure.other.words
        }
        save()
        reading = false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    /* The Health line drops what the Garmin line shows, so one thing is never two numbers side by side. */
    func withoutDuplicates(of morning: HealthImport.Morning) -> HealthImport.Morning {
        var m = morning
        guard let g = shown else { return m }
        if g.sleepHours != nil { m.sleepHours = nil }
        if g.hrv != nil { m.hrv = nil; m.hrvNormal = nil }
        if g.resting != nil { m.restingHR = nil; m.restingHRNormal = nil }
        return m
    }

    #if DEBUG
    /* Invented, for pictures: no network and no key. */
    static func invented(day: String) -> MorningNumbers {
        MorningNumbers(day: day, readAt: Calendar.current.date(bySettingHour: 7, minute: 12, second: 0, of: Date()) ?? Date(),
                       watchSynced: Calendar.current.date(bySettingHour: 7, minute: 5, second: 0, of: Date()),
                       sleepHours: .init(value: 7 + 20.0 / 60, normal: 7.1, days: 13),
                       hrv: .init(value: 64, normal: 61, days: 13), hrvRangeLow: 52, hrvRangeHigh: 68,
                       resting: .init(value: 47, normal: 49, days: 13),
                       bodyBattery: .init(value: 71, normal: 68, days: 9),
                       stress: .init(value: 28, normal: 31, days: 13))
    }
    #endif
}
