import Foundation
import SwiftUI
import WorkoutCore

/*
 * What he tells the app and the plan has no column for: how he felt each
 * morning, and how hard a workout was that lives in Apple Health and not in
 * the plan. Kept on this phone, in one small file, and written nowhere else
 * — the workbook is not touched by any of it.
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

    private struct Saved: Codable {
        var feel = FeelLog()
        var answers: [String: Double] = [:]
        var found: [Load.Found] = []
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
        let saved = Saved(feel: feel, answers: answers, found: found)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: fileURL, options: .atomic) }
    }

    /* One tap: this morning's answer. A second tap the same day replaces it. */
    func setFeel(_ value: Feel, on day: String) {
        feel.set(value, on: day)
        save()
    }

    /* How hard a workout from Health was. */
    func setAnswer(_ score: Int, for id: String) {
        guard (1...10).contains(score) else { return }
        answers[id] = Double(score)
        save()
    }

    /* Ask Health for the weeks the Load card draws. What it last said is kept if it says nothing now. */
    func readHealth(today: String) async {
        guard HealthImport.shared.inUse else { return }
        let from = Stats.recentWeekStarts(Self.weeks, today: today).first ?? today
        guard let fresh = await HealthImport.shared.found(from: from, to: today) else { return }
        if fresh != found {
            found = fresh
            save()
        }
    }
}
