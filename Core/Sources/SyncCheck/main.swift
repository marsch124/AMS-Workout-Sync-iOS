import Foundation
import CryptoKit
import WorkoutCore

/*
 * sync-check <workbook.xlsx> <work-dir>
 *
 * The whole sync path — download, find the row, write, verify, upload with a
 * revision — run against a "Dropbox" made of a file on disk, so the parts that
 * cannot be shown by comparing writers can be shown here: a conflict, a second
 * conflict, a sheet edited behind the app's back, an entry that can no longer
 * be placed, a queue with nothing to write. Prints what it found and ends with
 * "errors: none". Also writes sync-scenarios.json + native/ for write-parity,
 * so what the sync uploaded is compared with what the web app would write.
 */

final class FileRemote: Remote {
    let url: URL
    var downloads = 0
    var uploads = 0
    /* Runs between a download and the next upload, to play someone saving the file meanwhile. */
    var interfere: [(Data) -> Data] = []

    init(_ url: URL) { self.url = url }

    static func rev(_ data: Data) -> String { SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined() }

    func download(_ path: String) async throws -> RemoteFile {
        downloads += 1
        let data = try Data(contentsOf: url)
        return RemoteFile(data: data, rev: Self.rev(data), name: url.lastPathComponent)
    }

    func upload(_ path: String, _ data: Data, rev: String) async throws -> RemoteFile {
        if !interfere.isEmpty {
            let change = interfere.removeFirst()
            try change(try Data(contentsOf: url)).write(to: url)
        }
        let current = try Data(contentsOf: url)
        guard Self.rev(current) == rev else { throw RemoteError.conflict }
        uploads += 1
        try data.write(to: url)
        return RemoteFile(data: data, rev: Self.rev(data), name: url.lastPathComponent)
    }
}

let args = CommandLine.arguments
let source = URL(fileURLWithPath: args[1])
let work = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: work)
try FileManager.default.createDirectory(at: work.appendingPathComponent("native"), withIntermediateDirectories: true)
let now = ISO8601DateFormatter().date(from: "2026-09-14T10:15:00Z")!

var errors: [String] = []
func line(_ label: String, _ value: Any) { print("   " + label.padding(toLength: 46, withPad: " ", startingAt: 0) + "\(value)") }
func check(_ ok: Bool, _ message: String) { if !ok { errors.append(message) } }

func fresh(_ name: String) throws -> URL {
    let url = work.appendingPathComponent(name + ".xlsx")
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.copyItem(at: source, to: url)
    return url
}

func planOf(_ data: Data) throws -> (plan: [Workout], mapping: Mapping, workbook: Workbook) {
    let wb = try Workbook(data: data)
    let m = try Plan.mapping(for: wb)!
    return (Plan.build(wb, m), m, wb)
}

/* Re-save a workbook with one cell edited, the way Excel on the laptop would change it. */
func edited(_ data: Data, sheet: String, _ edits: [CellEdit]) -> Data {
    let wb = try! Workbook(data: data)
    try! wb.writeCells(sheet, edits)
    return try! wb.save()
}

let base = try planOf(try Data(contentsOf: source))
let todo = base.plan.filter { $0.discipline.id != "rest" && !$0.loggedInSheet && (Plan.plannedSeconds($0, base.mapping) ?? 0) > 0 }
guard todo.count >= 6 else { print("not enough sessions"); exit(1) }

func oneTap(_ w: Workout) -> LogEntry {
    var e = LogEntry()
    e.actualDuration = String(Int((Plan.plannedSeconds(w, base.mapping)! / 60).rounded()))
    return e
}

var scenarios: [[String: Any]] = []
func scenario(_ name: String, _ file: URL, _ steps: [(Workout, LogEntry)]) {
    scenarios.append(["name": name, "file": source.path, "steps": steps.map { w, e -> [String: Any] in
        var entry: [String: Any] = [:]
        if let v = e.actualDuration { entry["actualDuration"] = v }
        if let v = e.notes { entry["notes"] = v }
        if e.missed { entry["missed"] = true }
        if let v = e.moveTo { entry["moveTo"] = v }
        if let v = e.rpe { entry["rpe"] = v }
        if e.moveTo == nil { entry["completedAt"] = "2026-09-14T10:15:00.000Z" }
        return ["key": w.key, "entry": entry]
    }])
    try? FileManager.default.copyItem(at: file, to: work.appendingPathComponent("native/\(name).xlsx"))
}

// 1 ------------------------------------------------------------------
print("A QUEUE OF FOUR, ONE SYNC")
do {
    let url = try fresh("queue-of-four")
    let remote = FileRemote(url)
    var missed = LogEntry(); missed.missed = true; missed.notes = "Sick"
    var move = LogEntry(); move.moveTo = PlanView.addDays(todo[3].dayKey, 1)
    var full = oneTap(todo[2]); full.rpe = "6"; full.notes = "Good one"
    let steps: [(Workout, LogEntry)] = [(todo[0], oneTap(todo[0])), (todo[1], missed), (todo[2], full), (todo[3], move)]
    let queue = steps.map { QueuedEntry(workout: $0.0, entry: $0.1, now: now) }
    let result = try await Sync.run(queue, path: "/test", remote: remote, now: now)
    line("written / failed / dropped", "\(result.written.count) / \(result.failed.count) / \(result.dropped.count)")
    line("downloads / uploads", "\(remote.downloads) / \(remote.uploads)")
    check(result.written.count == 4 && remote.uploads == 1, "four entries should go up in one upload")
    let after = try planOf(try Data(contentsOf: url))
    line("first session now logged", after.plan.first { $0.key == todo[0].key }!.loggedInSheet)
    line("second session now missed", after.plan.first { $0.key == todo[1].key }!.missed)
    line("fourth session moved to", after.plan.first { $0.key == todo[3].key }!.dayKey)
    check(after.plan.first { $0.key == todo[0].key }!.loggedInSheet, "one-tap did not land")
    check(after.plan.first { $0.key == todo[1].key }!.missed, "missed did not land")
    check(after.plan.first { $0.key == todo[3].key }!.dayKey == move.moveTo, "move did not land")
    scenario("sync-queue-of-four", url, steps)
}

// 2 ------------------------------------------------------------------
print("\nSOMEONE SAVES THE FILE WHILE THE SYNC IS WORKING")
do {
    let url = try fresh("conflict-once")
    let remote = FileRemote(url)
    let other = todo[5]
    remote.interfere = [{ data in
        edited(data, sheet: other.sheet, [CellEdit(ref: makeRef(base.mapping.columns["notes"]!, other.row), value: .text("typed on the laptop"), field: "notes")])
    }]
    let queue = [QueuedEntry(workout: todo[4], entry: oneTap(todo[4]), now: now)]
    let result = try await Sync.run(queue, path: "/test", remote: remote, now: now)
    let after = try planOf(try Data(contentsOf: url))
    line("downloads / uploads", "\(remote.downloads) / \(remote.uploads)")
    line("the log landed", after.plan.first { $0.key == todo[4].key }!.loggedInSheet)
    line("the laptop's note survived", after.plan.first { $0.key == other.key }!.results["notes"]?.text ?? "(gone)")
    check(remote.downloads == 2 && remote.uploads == 1 && result.written.count == 1, "a conflict should re-download once and upload once")
    check(after.plan.first { $0.key == other.key }!.results["notes"]?.text == "typed on the laptop", "the other device's change was overwritten")
}

// 3 ------------------------------------------------------------------
print("\nIT HAPPENS AGAIN ON THE RETRY")
do {
    let url = try fresh("conflict-twice")
    let remote = FileRemote(url)
    remote.interfere = [{ edited($0, sheet: todo[5].sheet, [CellEdit(ref: makeRef(base.mapping.columns["notes"]!, todo[5].row), value: .text("one"), field: "notes")]) },
                        { edited($0, sheet: todo[5].sheet, [CellEdit(ref: makeRef(base.mapping.columns["notes"]!, todo[5].row), value: .text("two"), field: "notes")]) }]
    let queue = [QueuedEntry(workout: todo[4], entry: oneTap(todo[4]), now: now)]
    var threw = false
    do { _ = try await Sync.run(queue, path: "/test", remote: remote, now: now) } catch RemoteError.conflict { threw = true }
    let after = try planOf(try Data(contentsOf: url))
    line("gave up with a conflict", threw)
    line("uploads", remote.uploads)
    line("session untouched in the file", !after.plan.first { $0.key == todo[4].key }!.loggedInSheet)
    check(threw && remote.uploads == 0, "a second conflict must stop without uploading")
    check(!after.plan.first { $0.key == todo[4].key }!.loggedInSheet, "something was written despite the conflict")
}

// 4 ------------------------------------------------------------------
print("\nTHE SESSION WAS REWORDED IN EXCEL BEFORE THE SYNC")
do {
    let url = try fresh("reworded")
    let target = todo[0]
    let titleCol = base.mapping.columns["title"]!
    try edited(try Data(contentsOf: url), sheet: target.sheet,
               [CellEdit(ref: makeRef(titleCol, target.row), value: .text(target.title + " + strides"), field: "title")]).write(to: url)
    let remote = FileRemote(url)
    let result = try await Sync.run([QueuedEntry(workout: target, entry: oneTap(target), now: now)], path: "/test", remote: remote, now: now)
    let after = try planOf(try Data(contentsOf: url))
    line("written", result.written.count)
    line("landed on the same session", after.plan.first { $0.key == target.key }!.loggedInSheet)
    check(result.written.count == 1 && after.plan.first { $0.key == target.key }!.loggedInSheet, "a reworded session should still take its log")
}

// 5 ------------------------------------------------------------------
print("\nTHE ROW BECAME A DIFFERENT SPORT")
do {
    let url = try fresh("different-sport")
    let target = todo.first { $0.discipline.id == "run" } ?? todo[0]
    let sportCol = base.mapping.columns["discipline"]!
    let otherSport = target.discipline.id == "swim" ? "Bike" : "Swim"
    try edited(try Data(contentsOf: url), sheet: target.sheet,
               [CellEdit(ref: makeRef(sportCol, target.row), value: .text(otherSport), field: "discipline")]).write(to: url)
    let before = try Data(contentsOf: url)
    let remote = FileRemote(url)
    let q = QueuedEntry(workout: target, entry: oneTap(target), now: now)
    let result = try await Sync.run([q], path: "/test", remote: remote, now: now)
    line("written / failed", "\(result.written.count) / \(result.failed.count)")
    line("reason given", result.failed[q.id]?.prefix(60) ?? "(none)")
    line("uploads", remote.uploads)
    // Every other run with this wording is weeks away in his plan, so nothing may be written.
    check(result.written.isEmpty && result.failed[q.id] != nil && remote.uploads == 0, "a log must not be written into a row that is now another sport, nor into the same test weeks later")
    check(try Data(contentsOf: url) == before, "the file changed although nothing should have been written")
}

// 6 ------------------------------------------------------------------
print("\nONE BAD ENTRY DOES NOT BLOCK THE REST")
do {
    let url = try fresh("one-bad")
    let remote = FileRemote(url)
    let ghost = QueuedEntry(workoutKey: "Nowhere!9999", sheet: todo[0].sheet, row: 9999, dayKey: "1999-01-01",
                            disciplineId: "swim", title: "A session that never existed", entry: oneTap(todo[0]), now: now)
    let good = QueuedEntry(workout: todo[1], entry: oneTap(todo[1]), now: now)
    let result = try await Sync.run([ghost, good], path: "/test", remote: remote, now: now)
    line("written / failed", "\(result.written.count) / \(result.failed.count)")
    check(result.written == [good.id] && result.failed[ghost.id] != nil && remote.uploads == 1, "the good entry should go up and the bad one be kept with a reason")
}

// 7 ------------------------------------------------------------------
print("\nNOTHING TO WRITE, NOTHING UPLOADED")
do {
    let url = try fresh("nothing")
    let remote = FileRemote(url)
    var empty = LogEntry(); empty.actualDuration = "abc"
    var q = QueuedEntry(workout: todo[0], entry: empty, now: now)
    q.entry.completedAt = now
    let result = try await Sync.run([q], path: "/test", remote: remote, now: now)
    line("written / dropped / uploads", "\(result.written.count) / \(result.dropped.count) / \(remote.uploads)")
    // "abc" still writes the done marker, so this is written, not dropped — as in the web app.
    check(remote.uploads <= 1, "at most one upload")
}

// 8 ------------------------------------------------------------------
print("\nA BROKEN WORKBOOK IS NEVER UPLOADED")
do {
    var threw = false
    do { try Sync.verify(Data("not a workbook".utf8), sessionsBefore: 10) } catch { threw = true }
    line("unreadable bytes refused", threw)
    check(threw, "verify accepted bytes that are not a workbook")
    var lost = false
    do { try Sync.verify(try Data(contentsOf: source), sessionsBefore: base.plan.count + 1) } catch SyncError.sessionsLost { lost = true }
    line("fewer sessions than before refused", lost)
    check(lost, "verify accepted a workbook with sessions missing")
}

// 9 ------------------------------------------------------------------
print("\nWHAT THE SCREEN SHOWS BEFORE THE SYNC")
do {
    let doneRun = todo[0]
    var missed = LogEntry(); missed.missed = true
    var move = LogEntry(); move.moveTo = PlanView.addDays(todo[2].dayKey, 3)
    let queue = [QueuedEntry(workout: todo[0], entry: oneTap(todo[0]), now: now),
                 QueuedEntry(workout: todo[1], entry: missed, now: now),
                 QueuedEntry(workout: todo[2], entry: move, now: now),
                 QueuedEntry(workout: todo[3], entry: oneTap(todo[3]), now: now),
                 QueuedEntry(workout: todo[3], entry: move, now: now)]
    let shown = Sync.overlay(base.plan, queue)
    let byKey = Dictionary(uniqueKeysWithValues: shown.map { ($0.key, $0) })
    line("one-tap shows as done", byKey[doneRun.key]!.logged)
    line("missed shows as missed", byKey[todo[1].key]!.missed)
    line("moved shows on", byKey[todo[2].key]!.dayKey + " (was " + todo[2].dayKey + ")")
    line("logged then moved: done and moved", "\(byKey[todo[3].key]!.logged) / \(byKey[todo[3].key]!.pendingMove ?? "-")")
    check(byKey[doneRun.key]!.logged && byKey[doneRun.key]!.pending != nil, "a queued log must show as done")
    check(byKey[todo[1].key]!.missed && byKey[todo[1].key]!.logged, "a queued missed must show as missed")
    check(byKey[todo[2].key]!.dayKey == move.moveTo && !byKey[todo[2].key]!.logged, "a queued move must show on its new day and not as done")
    check(byKey[todo[3].key]!.logged && byKey[todo[3].key]!.pendingMove == move.moveTo, "a move must not hide a queued log (web app v1.72.0)")
    check(shown.map(\.key).count == base.plan.count, "the overlay must not lose sessions")
    check(zip(shown, shown.dropFirst()).allSatisfy { $0.date <= $1.date }, "the overlay must stay in date order")
    check(base.plan.first { $0.key == todo[2].key }!.dayKey == todo[2].dayKey, "the overlay must not touch the plan itself")

    // The swap list: not done (sheet or waiting), nearest first, future first on a tie.
    let swim = shown.first { $0.discipline.id == "swim" && !$0.logged && $0.dayKey > doneRun.dayKey }!
    let offered = Sync.swapCandidates(for: swim, in: shown)
    line("swap list size / gaps", "\(offered.count) / " + offered.map { String($0.gap) }.joined(separator: " "))
    check(!offered.contains { $0.workout.logged }, "a done or waiting session must never be offered to swap")
    check(!offered.contains { $0.workout.discipline.id == "rest" }, "a rest day must never be offered to swap")
    check(!offered.contains { $0.workout.key == swim.key }, "a session must not be offered to swap with itself")
    for (a, b) in zip(offered, offered.dropFirst()) {
        check(abs(a.gap) <= abs(b.gap), "not nearest first")
        if abs(a.gap) == abs(b.gap) { check(a.gap >= b.gap, "a past session offered before an equally near future one") }
    }
}

// 10 -----------------------------------------------------------------
print("\nEXTRAS: APPENDED, NEVER DOUBLED, NEVER DROPPED")
do {
    let url = try fresh("extras")
    let remote = FileRemote(url)
    var walk = ExtraEntry(date: todo[0].dayKey, activity: "walk", ref: "xcheck001")
    walk.what = "Dog walk"; walk.minutes = 35
    var walkAgain = walk; walkAgain.ref = "xcheck002"          // a second walk, same day and length
    var yoga = ExtraEntry(date: todo[0].dayKey, activity: "yoga", ref: "xcheck003")
    yoga.minutes = 20; yoga.notes = "calm"
    let queue = [QueuedEntry(extra: walk, now: now), QueuedEntry(extra: walk, now: now),
                 QueuedEntry(extra: walkAgain, now: now), QueuedEntry(extra: yoga, now: now),
                 QueuedEntry(workout: todo[1], entry: oneTap(todo[1]), now: now)]
    let result = try await Sync.run(queue, path: "/test", remote: remote, now: now)
    let after = try Workbook(data: try Data(contentsOf: url))
    let rows = Extras.read(after)
    let before = Extras.read(try Workbook(data: try Data(contentsOf: source)))
    line("written / failed / uploads", "\(result.written.count) / \(result.failed.count) / \(remote.uploads)")
    line("extras rows before / after", "\(before.count) / \(rows.count)")
    line("refs written", rows.filter { $0.ref.hasPrefix("xcheck") }.map(\.ref).sorted().joined(separator: " "))
    check(result.written.count == 5 && result.failed.isEmpty, "every entry, the replay included, should be reported written")
    check(rows.count == before.count + 3, "three new rows expected: the replay must not double, the repeat must not be swallowed")
    check(Set(rows.map(\.ref)).contains("xcheck002"), "a genuine repeat with its own ref must be written")
    check(rows.filter { $0.ref == "xcheck001" }.count == 1, "a replayed extra must appear once")
    let aftersheet = try after.readSheet(try Extras.sheetName(for: after))
    check(Extras.alreadyRecorded(aftersheet, walk), "a written extra must be recognised on the next replay")
    // The sync re-read: sessions untouched, the one-tap landed.
    let plan = try planOf(try Data(contentsOf: url))
    check(plan.plan.count == base.plan.count, "the plan must keep every session")
    check(plan.plan.first { $0.key == todo[1].key }!.loggedInSheet, "the one-tap alongside the extras did not land")
}

// 11 -----------------------------------------------------------------
print("\nAN EXTRA CORRECTED: ITS OWN ROW, ONLY WHAT CHANGED")
do {
    let url = try fresh("extras-corrected")
    let remote = FileRemote(url)
    var walk = ExtraEntry(date: todo[0].dayKey, activity: "walk", ref: "xfix00001")
    walk.what = "Dog walk"; walk.minutes = 35; walk.distance = 3; walk.notes = "along the river"
    // One written the way his sheet carries them from before references existed.
    var yoga = ExtraEntry(date: todo[0].dayKey, activity: "yoga", ref: "")
    yoga.minutes = 20
    _ = try await Sync.run([QueuedEntry(extra: walk, now: now), QueuedEntry(extra: yoga, now: now)],
                           path: "/test", remote: remote, now: now)

    let written = Extras.read(try Workbook(data: try Data(contentsOf: url)))
    guard let walkRow = written.first(where: { $0.ref == "xfix00001" }),
          let yogaRow = written.first(where: { $0.ref.isEmpty && normalise($0.label) == "yoga"
                                               && $0.date == todo[0].dayKey && $0.minutes == 20 }) else {
        errors.append("the two extras to correct were not written"); exit(1)
    }

    // The walk: half an hour longer, and the note taken off. Nothing else named.
    var fix = ExtraEntry(date: walkRow.date, activity: "walk", ref: walkRow.ref)
    fix.what = walkRow.what; fix.minutes = 65; fix.distance = 3; fix.notes = ""
    fix.editing = ExtraTarget(id: walkRow.id, ref: walkRow.ref, date: walkRow.date, label: walkRow.label,
                              minutes: walkRow.minutes, fields: [ExtraField.duration, ExtraField.notes])
    // The yoga: a different activity and a different length, on a row with no
    // reference — found by what it said, and given one on the way past.
    var fixYoga = ExtraEntry(date: yogaRow.date, activity: "mobility", ref: "xfix00002")
    fixYoga.minutes = 25
    fixYoga.editing = ExtraTarget(id: yogaRow.id, ref: "", date: yogaRow.date, label: yogaRow.label,
                                  minutes: yogaRow.minutes, fields: [ExtraField.activity, ExtraField.duration])
    // And one naming a row that is not there: it must never fall back to adding one.
    var lost = ExtraEntry(date: walkRow.date, activity: "walk", ref: "xgone0001")
    lost.minutes = 10
    lost.editing = ExtraTarget(id: "xgone0001", ref: "xgone0001", date: "1999-01-01", label: "Walk",
                               minutes: 10, fields: [ExtraField.duration])

    let corrections = [QueuedEntry(extra: fix, now: now), QueuedEntry(extra: fix, now: now),
                       QueuedEntry(extra: fixYoga, now: now), QueuedEntry(extra: lost, now: now)]
    let result = try await Sync.run(corrections, path: "/test", remote: remote, now: now)
    let after = Extras.read(try Workbook(data: try Data(contentsOf: url)))
    let walkNow = after.first { $0.ref == "xfix00001" }
    let yogaNow = after.first { $0.ref == "xfix00002" }

    line("written / failed", "\(result.written.count) / \(result.failed.count)")
    line("rows before / after the corrections", "\(written.count) / \(after.count)")
    line("the walk: minutes / what / distance / notes",
         "\(walkNow?.minutes.map(jsNumberString) ?? "-") / \(walkNow?.what ?? "-") / \(walkNow?.distance ?? "-") / \"\(walkNow?.notes ?? "-")\"")
    line("the yoga row now reads", "\(yogaNow?.label ?? "-") \(yogaNow?.minutes.map(jsNumberString) ?? "-") ref \(yogaNow?.ref ?? "-")")
    line("the one naming a missing row", result.failed.values.first ?? "(not refused)")

    check(after.count == written.count, "a correction must change a row, never add one")
    check(walkNow?.minutes == 65, "the corrected length did not land")
    check(walkNow?.notes.isEmpty == true, "a box emptied must empty the cell")
    check(walkNow?.what == "Dog walk", "a column nobody changed must be left exactly as it was")
    check(walkNow?.distance == walkRow.distance, "a column nobody changed must be left exactly as it was")
    check(result.written.count == 3, "the replayed correction must be reported written, not failed")
    check(normalise(yogaNow?.label ?? "") == "mobility" && yogaNow?.minutes == 25,
          "a row from before references existed must still be found and corrected")
    check(yogaNow?.row == yogaRow.row, "the correction must land on the row that was already there")
    check(result.failed.count == 1, "a correction whose row is gone must be kept and reported, not appended")

    // The sessions are untouched by all of this.
    let plan = try planOf(try Data(contentsOf: url))
    check(plan.plan.count == base.plan.count, "the plan must keep every session")
}

let json = try JSONSerialization.data(withJSONObject: scenarios, options: [.prettyPrinted])
try json.write(to: work.appendingPathComponent("sync-scenarios.json"))
print("\nerrors:", errors.isEmpty ? "none" : "\n - " + errors.joined(separator: "\n - "))
exit(errors.isEmpty ? 0 : 1)
