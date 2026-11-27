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

    /* The Body page's numbers: the same half-hour rule, its own file. */
    @Published private(set) var body: BodyDay?
    @Published private(set) var readingBody = false
    /* The days kept day by day for the 4- and 12-week views (2.8). */
    @Published private(set) var history = BodyHistory()
    @Published private(set) var readingHistory = false

    private var file = GarminMorningFile()
    private var bodyFile = GarminBodyFile()

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-morning.json")
    }

    private static var bodyFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-body.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.bodyFileURL), let f = try? JSONDecoder().decode(GarminBodyFile.self, from: data) {
            bodyFile = f
            body = f.body
            history = f.history ?? BodyHistory()
        }
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(GarminMorningFile.self, from: data) {
            file = f
            numbers = f.numbers
        }
        #if DEBUG
        if GarminKey.isFake {
            let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] ?? GarminMorning.morningDay(now: Date())
            numbers = Self.invented(day: day)
            let invented = ProcessInfo.processInfo.environment["AMSWS_TODAY"] ?? GarminMorning.dayKey(Date())
            body = Self.inventedBody(day: invented)
            history = Self.inventedHistory(day: invented)
        }
        #endif
    }

    /* What the screens show: only while a key is saved. */
    var shown: MorningNumbers? { keySaved ? numbers.flatMap { $0.isEmpty ? nil : $0 } : nil }

    func keyChanged() {
        keySaved = GarminKey.isSaved
        if !keySaved {
            GarminActivityReader.shared.forget()
            SessionScoreReader.shared.forget(); SamePulseReader.shared.forget()
            numbers = nil
            problem = nil
            file = GarminMorningFile()
            try? FileManager.default.removeItem(at: Self.fileURL)
            body = nil
            history = BodyHistory()
            bodyFile = GarminBodyFile()
            try? FileManager.default.removeItem(at: Self.bodyFileURL)
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

    /* What the Body page shows: only while a key is saved. */
    var bodyShown: BodyDay? { keySaved ? body.flatMap { $0.isEmpty ? nil : $0 } : nil }

    /* Called when the Body page appears (and since 2.9 at the start and at midnight): at most one read in 30 minutes,
       unless the numbers held are from an earlier day — then at once. */
    func readBodyIfDue(today: String) async {
        guard keySaved, !GarminKey.isFake,
              GarminMorning.bodyReadDue(lastTried: bodyFile.lastTried, heldDay: body?.day, now: Date()) else { return }
        await readBody(today: today)
    }

    /* "Read again now" ignores the half hour. */
    func readBody(today: String) async {
        guard keySaved, !GarminKey.isFake, !readingBody else { return }
        readingBody = true
        problem = nil
        bodyFile.lastTried = Date()
        let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] != nil ? today : GarminMorning.dayKey(Date())
        do {
            // Yesterday's curve is read once a day: when the whole of it is held for this day, it is not asked for again.
            let held = body?.day == day ? body?.battery?.yesterday : nil
            let heldWeek = body?.day == day ? body?.batteryWeek : nil
            let fresh = try await GarminClient.shared.body(day: day, yesterday: GarminBody.yesterdayIsWhole(held, day: day) ? held : nil,
                                                           week: heldWeek)
            // An empty answer never replaces numbers already held.
            if !fresh.isEmpty || body == nil {
                body = fresh
                bodyFile.body = fresh
                // The seven days of this read are kept day by day too.
                history.absorb(fresh)
                history.prune(before: GarminMorning.addDays(day, -90))
                bodyFile.history = history
            }
        } catch let f as GarminFailure {
            problem = f.words
        } catch {
            problem = GarminFailure.other.words
        }
        if let data = try? JSONEncoder().encode(bodyFile) { try? data.write(to: Self.bodyFileURL, options: .atomic) }
        readingBody = false
    }

    /*
     * The 4- and 12-week views: read only when he picks one, at most once in
     * 30 minutes per view, and only from the first day still missing.
     */
    func readHistoryIfDue(_ span: BodyPage.Span, today: String) async {
        guard span != .week, keySaved, !GarminKey.isFake, !readingHistory,
              GarminMorning.mayRead(lastTried: history.tried[span.rawValue], now: Date()) else { return }
        readingHistory = true
        history.tried[span.rawValue] = Date()
        let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] != nil ? today : GarminMorning.dayKey(Date())
        do {
            let from = min(history.readFrom(span, today: day), day)
            let more = try await GarminClient.shared.history(from: from, to: day)
            history.merge(more)
            history.prune(before: GarminMorning.addDays(day, -90))
        } catch {
            // A failed longer read leaves what is held; the half hour still counts.
        }
        bodyFile.history = history
        if let data = try? JSONEncoder().encode(bodyFile) { try? data.write(to: Self.bodyFileURL, options: .atomic) }
        readingHistory = false
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
    /* Invented, for pictures: a believable day with two workouts, and the day before it. */
    static func inventedBody(day: String) -> BodyDay {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: GarminMorning.date(day) ?? Date())
        func at(_ h: Double) -> Date { midnight.addingTimeInterval(h * 3600) }
        // Charged in the night, a morning run, strength at noon, a slow drain after.
        let shape: [(Double, Double)] = [(0, 38), (1, 46), (2, 55), (3, 63), (4, 71), (5, 78), (6, 82), (6.5, 80), (7, 74),
                                         (7.5, 66), (8, 58), (8.5, 55), (9.5, 53), (10.5, 50), (11.5, 47), (12.5, 44), (13.5, 40)]
        let points = shape.map { BodyDay.Point(time: at($0.0), value: $0.1) }
        // The day before: a shorter night, a quiet day, an evening ride.
        let before: [(Double, Double)] = [(0, 24), (1, 31), (2, 39), (3, 47), (4, 54), (5, 60), (6, 64), (7, 66), (8, 63), (9.5, 60),
                                          (11, 57), (12.5, 54), (14, 51), (15.5, 49), (17, 47), (17.5, 43), (18, 36), (18.5, 30),
                                          (19.5, 28), (21, 27), (22, 29), (23, 33), (23.9, 37)]
        let yesterday = before.map { BodyDay.Point(time: at($0.0 - 24), value: $0.1) }
        let run = BodyDay.Workout(id: "invented-1", name: "Morning run", type: "running", start: at(6.75), end: at(7.75), drain: 17)
        let strength = BodyDay.Workout(id: "invented-2", name: "Strength", type: "strength_training", start: at(12), end: at(12.75), drain: 6)
        let sleepNights = [6.8, 7.4, 5.9, 7.2, 8.0, 6.6, 7.3]
        let hrvDays = [58, 61, 57, 63, 66, 60, 64]
        let restDays = [49, 48, 50, 47, 48, 49, 47]
        let stressDays = [32, 29, 35, 27, 30, 33, 26]
        func line(_ v: [Double?]) -> [BodyDay.DayValue] {
            v.enumerated().map { BodyDay.DayValue(day: GarminMorning.addDays(day, $0.offset - (v.count - 1)), value: $0.element) }
        }
        // The week: a charge in the night, a slow drain after; one day the watch was off.
        func week(_ off: Int, low: Double, high: Double) -> BodyDay.BatteryDay {
            let d = GarminMorning.addDays(day, off)
            if off == -3 { return BodyDay.BatteryDay(day: d) }
            let pts = stride(from: 0.0, through: 23.0, by: 1.5).map { h -> BodyDay.Point in
                let v = h < 6.5 ? low + (high - low) * (h / 6.5) : high - (high - low) * ((h - 6.5) / 17)
                return BodyDay.Point(time: at(h + Double(off) * 24), value: v)
            }
            return BodyDay.BatteryDay(day: d, points: pts, high: pts.map(\.value).max(), low: pts.map(\.value).min())
        }
        let batteryWeek = [week(-6, low: 22, high: 79), week(-5, low: 30, high: 88), week(-4, low: 18, high: 71), week(-3, low: 0, high: 0),
                           week(-2, low: 26, high: 84), week(-1, low: 24, high: 66),
                           BodyDay.BatteryDay(day: day, points: points, high: points.map(\.value).max(), low: points.map(\.value).min())]
        var activity = GarminBody.ActivityDays()
        let stepDays: [Double] = [7400, 9900, 6100, 10200, 8600, 7300, 9300]   // averages 8,400
        let vigorous: [Double] = [5, 0, 10, 5, 0, 10, 5], moderate: [Double] = [10, 0, 25, 20, 0, 15, 15]
        for k in 0..<7 {
            let d = GarminMorning.addDays(day, k - 6)
            activity.steps[d] = stepDays[k]
            // Only this week (Monday to today) has minutes, so the tile's figure and its bars agree.
            if d < BodyPage.weekStart(of: day) { continue }
            activity.moderate[d] = moderate[k]; activity.vigorous[d] = vigorous[k]
            activity.intensity[d] = moderate[k] + 2 * vigorous[k]
        }
        activity.weeklyGoal = 150; activity.stepGoal = 8000
        return BodyDay(day: day, readAt: at(13.6),
                       battery: .init(points: points, workouts: [run, strength],
                                      yesterday: ProcessInfo.processInfo.environment["AMSWS_BODY_NO_YESTERDAY"] != nil ? nil : yesterday),
                       sleep: .init(lastNight: 7.3, nights: line(sleepNights.map { Optional($0) }.enumerated().map { $0.offset == 2 ? nil : $0.element })),
                       hrv: .init(lastNight: 64, rangeLow: 52, rangeHigh: 68, stillLearning: false, days: line(hrvDays.map { Double($0) })),
                       resting: .init(today: 47, normal: 48.5, days: line(restDays.map { Double($0) })),
                       stress: .init(average: 26, highest: 71, days: line(stressDays.map { Double($0) })),
                       steps: GarminBody.steps(activity, day: day), intensity: GarminBody.intensity(activity, day: day),
                       batteryWeek: batteryWeek)
    }

    /* Invented, for pictures: twelve weeks of days (some without a reading) behind the 4- and 12-week views. */
    static func inventedHistory(day: String) -> BodyHistory {
        var h = BodyHistory()
        for k in 0..<90 {
            let d = GarminMorning.addDays(day, -k)
            if k % 9 != 4 { h.sleep[d] = 6.2 + Double((k * 37) % 15) / 10 }
            if k % 13 != 6 { h.hrv[d] = 54 + Double((k * 13) % 17) }
            h.resting[d] = 46 + Double((k * 7) % 7)
            h.stress[d] = 24 + Double((k * 11) % 14)
            h.steps[d] = 6500 + Double((k * 911) % 4500)
            h.intensity[d] = Double((k * 17) % 60)
        }
        return h
    }

    #endif
}
