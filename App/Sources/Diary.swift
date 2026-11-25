import Foundation
import SwiftUI
import WorkoutCore

/*
 * What he tells the app and the plan has no column for: how he felt each
 * morning, and how hard a workout was that lives in Apple Health and not in
 * the plan. Kept in one small file on each device and, since 2.1, shared with
 * his other devices through iCloud (DiaryDoc: the newest answer per day
 * wins) — the plan itself is not touched by any of it.
 *
 * It also keeps the last list of workouts Health handed over, so the Load
 * card can draw at once and Health is asked only for what is new.
 */
@MainActor
final class Diary: ObservableObject {
    static let shared = Diary()

    @Published private(set) var feel = FeelLog()
    /* How hard a Health workout was, 1 to 10, by the workout's own id. */
    @Published private(set) var answers: [String: Double] = [:]
    /* The workouts Health held when it was last asked (eight weeks back). */
    @Published private(set) var found: [Load.Found] = []
    /* When each answer was given ("feel:<day>", "answer:<id>"), so the newest wins between devices. */
    private var stamps: [String: Date] = [:]

    /* A change here: iCloud is met a moment later. */
    var onChange: (() -> Void)?

    private struct Saved: Codable {
        var feel = FeelLog()
        var answers: [String: Double] = [:]
        var found: [Load.Found] = []
        var stamps: [String: Date] = [:]

        init(feel: FeelLog, answers: [String: Double], found: [Load.Found], stamps: [String: Date]) {
            self.feel = feel; self.answers = answers; self.found = found; self.stamps = stamps
        }

        /* A field that is missing is an older file, and gets its default — never "unreadable, start empty". */
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            feel = try c.decodeIfPresent(FeelLog.self, forKey: .feel) ?? FeelLog()
            answers = try c.decodeIfPresent([String: Double].self, forKey: .answers) ?? [:]
            found = (try? c.decodeIfPresent([Load.Found].self, forKey: .found)) ?? []
            stamps = (try? c.decodeIfPresent([String: Date].self, forKey: .stamps)) ?? [:]
        }
    }

    /* How many weeks the Load card draws, this one included. */
    static let weeks = 8

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diary.json")
    }

    init() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["AMSWS_RESET"] != nil { try? FileManager.default.removeItem(at: fileURL) }
        #endif
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            feel = saved.feel
            answers = saved.answers
            found = saved.found
            stamps = saved.stamps
        }
        #if DEBUG
        // AMSWS_FEEL=4 answers this morning's question for a picture; "week"
        // fills a fortnight of mornings so the Mornings bars have something to draw.
        if let raw = env["AMSWS_FEEL"] {
            let today = env["AMSWS_TODAY"] ?? PlanView.todayKey()
            if raw == "week" {
                let pattern = [3, 4, 4, 2, 3, 5, 4, 3, 0, 4, 2, 3, 4]
                for (i, n) in pattern.enumerated() {
                    if let f = Feel(rawValue: n) { feel.set(f, on: PlanView.addDays(today, i - pattern.count)) }
                }
            } else if let n = Int(raw), let f = Feel(rawValue: n) {
                feel.set(f, on: today)
            }
        }
        #endif
    }

    private func save() {
        let saved = Saved(feel: feel, answers: answers, found: found, stamps: stamps)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: fileURL, options: .atomic) }
    }

    /* One tap: this morning's answer. A second tap the same day replaces it. */
    func setFeel(_ value: Feel, on day: String) {
        var doc = self.doc
        doc.setFeel(value.rawValue, on: day)
        feel.set(value, on: day)
        stamps = doc.stamps
        save()
        onChange?()
    }

    /* How hard a workout from Health was. */
    func setAnswer(_ score: Int, for id: String) {
        guard (1...10).contains(score) else { return }
        var doc = self.doc
        doc.setAnswer(Double(score), for: id)
        answers[id] = Double(score)
        stamps = doc.stamps
        save()
        onChange?()
    }

    // MARK: iCloud (2.1)

    /* The answers as they travel. */
    var doc: DiaryDoc { DiaryDoc(feel: feel.days, answers: answers, stamps: stamps) }

    /* The answers joined with the other devices', put in place here. */
    func takeFromCloud(_ joined: DiaryDoc) {
        feel = FeelLog(days: joined.feel)
        answers = joined.answers
        stamps = joined.stamps
        save()
    }

    /*
     * The Mac has no Apple Health, and an iPad's may hold nothing: the workouts
     * the Load card draws then come from the iPhone. An iPad whose own Health
     * answers keeps its own.
     */
    func foundFromIPhone(_ shared: [Load.Found]) {
        guard !Device.isPhone, Device.isMac || !HealthImport.shared.inUse || found.isEmpty, shared != found else { return }
        found = shared
        save()
    }

    /* Ask Health for the weeks the Load card draws. What it last said is kept if it says nothing now. */
    func readHealth(today: String) async {
        guard HealthImport.shared.inUse else { return }
        let from = Stats.recentWeekStarts(Self.weeks, today: today).first ?? today
        guard let fresh = await HealthImport.shared.found(from: from, to: today) else { return }
        // An iPad's own Health with nothing in it does not wipe what the iPhone shared.
        if !Device.isPhone, fresh.isEmpty { return }
        if fresh != found {
            found = fresh
            save()
        }
    }
}
