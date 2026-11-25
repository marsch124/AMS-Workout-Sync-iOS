import Foundation

/*
 * The book held against the workbook.
 *
 * The same entries are written twice: into a workbook by the writer that has
 * written his plan since September, and into a book made from that workbook.
 * Then both are read and compared, session by session and box by box. No
 * difference means logging in the app is what logging into Excel was.
 *
 * It lives in the library, not in a test, so it can be run on the Mac against
 * a copy of his real plan as well as against the fixture on every push.
 */
public enum BookOracle {
    public struct Outcome {
        public let entries: Int
        public let differences: [String]
    }

    /* A spread of everything the app can log, on sessions this plan really has. */
    public static func entries(for plan: [Workout], extras: [ExtraRecord], mapping: Mapping, today: String) -> [QueuedEntry] {
        var out: [QueuedEntry] = []
        let open = plan.filter { !$0.loggedInSheet && $0.discipline.id != "rest" && $0.dayKey >= today }
        let done = plan.filter { $0.loggedInSheet && !$0.missed && $0.discipline.id != "rest" }

        func entry(_ fill: (inout LogEntry) -> Void) -> LogEntry { var e = LogEntry(); fill(&e); return e }
        func add(_ w: Workout, _ e: LogEntry) { out.append(QueuedEntry(workout: w, entry: e)) }

        if open.count > 0 {
            let minutes = (Plan.plannedSeconds(open[0], mapping) ?? 1800) / 60
            add(open[0], entry { $0.actualDuration = String(Int((minutes + 0.5).rounded(.down))) })
        }
        if open.count > 1 {
            add(open[1], entry {
                $0.actualDuration = "47"; $0.actualDistance = "8,4"; $0.avgHr = "131"; $0.rpe = "6"
                $0.avgPace = "5:36"; $0.notes = "  Felt strong — ö å ä, 5 < 6 & \"fine\"  "
            })
        }
        if open.count > 2 { add(open[2], entry { $0.missed = true; $0.notes = "A cold." }) }
        if open.count > 3 { add(open[3], entry { $0.moveTo = PlanView.addDays(open[3].dayKey, 2) }) }
        if open.count > 4 { add(open[4], entry { $0.rpe = "7" }) }
        if open.count > 5 {
            add(open[5], entry { $0.moveTo = PlanView.addDays(open[5].dayKey, -1) })
            add(open[5], entry { $0.actualDuration = "1:05"; $0.avgHr = "118" })
        }
        if let last = done.last { add(last, entry { $0.avgHr = "140" }) }
        if done.count > 1 { add(done[done.count - 2], entry { $0.notes = "Adjusted afterwards."; $0.rpe = "3" }) }

        var fresh = ExtraEntry(date: today, activity: "bike", ref: "xoracle1")
        fresh.what = " Easy spin "; fresh.minutes = 35; fresh.distance = 12.5; fresh.effort = 4
        fresh.isTraining = true; fresh.notes = "Oracle."
        out.append(QueuedEntry(extra: fresh))
        // The same one again: a replay must not leave two.
        out.append(QueuedEntry(extra: fresh))

        var mended = fresh
        mended.minutes = 40; mended.notes = ""
        mended.editing = ExtraTarget(id: fresh.ref, ref: fresh.ref, date: fresh.date,
                                     label: Extras.activity(fresh.activity).label, minutes: 35,
                                     fields: [ExtraField.duration, ExtraField.notes])
        out.append(QueuedEntry(extra: mended))

        if let old = extras.last {
            var x = ExtraEntry(date: old.date, activity: old.activity, ref: old.ref.isEmpty ? "xoracle2" : old.ref)
            x.what = old.what; x.minutes = old.minutes; x.isTraining = !old.isTraining; x.effort = 6
            x.editing = ExtraTarget(id: old.id, ref: old.ref, date: old.date, label: old.label, minutes: old.minutes,
                                    fields: [ExtraField.effort, ExtraField.isTraining])
            out.append(QueuedEntry(extra: x))
        }
        return out
    }

    public static func run(_ data: Data, today: String, now: Date = Date()) throws -> Outcome {
        let taken = try PlanImport.read(data, fileName: "oracle.xlsx", today: today, now: now)
        var book = taken.book
        let workbook = try Workbook(data: data)
        guard let mapping = try Plan.mapping(for: workbook) else { throw SyncError.noLayout }
        let queue = entries(for: Plan.build(workbook, mapping), extras: Extras.read(workbook), mapping: mapping, today: today)

        var differences = taken.proof.differences
        if taken.proof.before != taken.proof.after { differences.append("the counts differ straight after the import") }

        let (bytes, result) = try Sync.apply(queue, to: data, now: now)
        for q in queue {
            let theirs = result.written.contains(q.id) ? "written" : result.dropped.contains(q.id) ? "dropped" : "failed"
            var mine = "failed"
            if let how = try? book.apply(q, now: now) { mine = how == .written ? "written" : "dropped" }
            if mine != theirs { differences.append("entry for \(q.title.isEmpty ? "an extra" : q.title): Excel \(theirs), the book \(mine)") }
        }
        guard let bytes else { return Outcome(entries: queue.count, differences: differences + ["Excel wrote nothing"]) }

        let after = try Workbook(data: bytes)
        guard let again = try Plan.mapping(for: after) else { throw SyncError.noLayout }
        differences += PlanImport.differences(Plan.build(after, again), book.sessions)
        differences += PlanImport.extraDifferences(Extras.read(after), book.extras)

        // And once more through the disk: what is stored is what counts.
        let reopened = try PlanBook.decoded(try book.encoded())
        differences += PlanImport.differences(book.sessions, reopened.sessions).map { "after saving: " + $0 }
        differences += PlanImport.extraDifferences(book.extras, reopened.extras).map { "after saving: " + $0 }
        return Outcome(entries: queue.count, differences: differences)
    }
}
