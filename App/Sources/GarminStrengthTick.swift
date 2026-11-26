import Foundation
import WorkoutCore

/*
 * 2.17: a planned strength session still to do is ticked by itself from a Garmin strength activity of
 * the same day (10 minutes or more), with the activity's minutes — on any device where his Garmin key
 * is saved. Runs when the app comes to the front and when Today appears, after the neighbours' tick
 * (Workout Companion comes first). Asks Garmin at most once in 10 minutes, and only when a strength
 * session is still to do in the last 14 days.
 *
 * Never twice: the activity's id is kept in the log itself ("garmin:<id>"), which travels through
 * iCloud, so no device uses it again. A session that ever had a log (a `log:` stamp in the book — also
 * one he cleared) is never ticked from Garmin, so clearing a tick sticks. Nothing is written to Garmin.
 */
@MainActor
enum GarminStrengthTick {
    private static let lastKey = "garmin.strengthTick.lastTried"
    private static let readEvery: TimeInterval = 10 * 60
    private static var running = false

    static func run(store: Store) async {
        guard !running, store.canLog, GarminKey.isSaved, store.book != nil else { return }
        guard !todo(store).isEmpty else { return }
        if !GarminKey.isFake, let last = UserDefaults.standard.object(forKey: lastKey) as? Date,
           Date().timeIntervalSince(last) < readEvery, Date() >= last { return }
        running = true
        defer { running = false }
        UserDefaults.standard.set(Date(), forKey: lastKey)
        let day = store.today
        let list: [GarminActivitySummary]
        if GarminKey.isFake {
            list = [GarminActivitySummary(id: 917_001, name: "Strength", typeKey: "strength_training", day: day,
                                          startGMT: Date(), seconds: 40 * 60)]
        } else {
            do { list = try await GarminClient.shared.activities(from: PlanView.addDays(day, -13), to: day) } catch { return }
        }
        // Read again after the wait: something may have been logged meanwhile.
        guard store.canLog else { return }
        let sessions = store.displayed
        let ticks = NeighbourRules.garminStrengthTicks(todo: todo(store), activities: list,
                                                       used: NeighbourRules.garminIdsUsed(sessions), today: store.today)
        for t in ticks {
            guard let w = sessions.first(where: { $0.key == t.key }) else { continue }
            let minutes = Int((t.activity.seconds / 60).rounded())
            guard minutes > 0 else { continue }
            var entry = LogEntry()
            entry.actualDuration = String(minutes)
            entry.tickedFrom = NeighbourRules.garminSource(t.activity)
            store.log(w, entry)
        }
    }

    /* Strength sessions still to do, today and the 13 days before, never logged (nor cleared) before. */
    private static func todo(_ store: Store) -> [(key: String, day: String)] {
        let day = store.today
        let oldest = PlanView.addDays(day, -13)
        let stamps = store.book?.stamps ?? [:]
        return store.displayed.filter {
            $0.discipline.id == "strength" && !$0.logged && !$0.missed && !store.isWaiting($0.key)
                && $0.dayKey <= day && $0.dayKey >= oldest && stamps["log:" + $0.key] == nil
        }.map { (key: $0.key, day: $0.dayKey) }
    }
}
