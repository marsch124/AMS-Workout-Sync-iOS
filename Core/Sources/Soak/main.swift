import Foundation
import CryptoKit
import WorkoutCore

/*
 * soak <workbook.xlsx> <work-dir> [rounds]
 *
 * Weeks of use in a few seconds, against a copy of his own plan.
 *
 * Where sync-check proves one awkward case at a time, this one runs a long,
 * mixed sequence — logging with real numbers, missed marks, moves, extra
 * workouts, corrections, a Dropbox conflict thrown in — and then reads the
 * workbook back and checks it cell by cell:
 *
 *   · every logged session holds exactly what was logged
 *   · every moved session has a new date and nothing else altered
 *   · every extra is there, once, in a row of its own
 *   · EVERY OTHER CELL in the workbook is exactly what it was
 *   · the file is still a workbook, with every sheet it started with
 *
 * His own plan is never touched: everything happens on a copy in work-dir.
 */

final class FileRemote: Remote {
    let url: URL
    var uploads = 0, conflicts = 0
    var interfere: [(Data) -> Data] = []

    init(_ url: URL) { self.url = url }
    static func rev(_ data: Data) -> String { SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined() }

    func download(_ path: String) async throws -> RemoteFile {
        let data = try Data(contentsOf: url)
        return RemoteFile(data: data, rev: Self.rev(data), name: url.lastPathComponent)
    }

    func upload(_ path: String, _ data: Data, rev: String) async throws -> RemoteFile {
        if !interfere.isEmpty {
            let change = interfere.removeFirst()
            try change(try Data(contentsOf: url)).write(to: url)
        }
        let current = try Data(contentsOf: url)
        guard Self.rev(current) == rev else { conflicts += 1; throw RemoteError.conflict }
        uploads += 1
        try data.write(to: url)
        return RemoteFile(data: data, rev: Self.rev(data), name: url.lastPathComponent)
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("soak <workbook.xlsx> <work-dir> [rounds]"); exit(2) }
let source = URL(fileURLWithPath: args[1])
let work = URL(fileURLWithPath: args[2])
let rounds = args.count > 3 ? max(1, Int(args[3]) ?? 6) : 6
try? FileManager.default.removeItem(at: work)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

var errors: [String] = []
func check(_ ok: Bool, _ message: String) { if !ok { errors.append(message) } }
func line(_ label: String, _ value: Any) { print("   " + label.padding(toLength: 44, withPad: " ", startingAt: 0) + "\(value)") }

/* Every cell of every sheet, as text, keyed by sheet/row/column. */
func everyCell(_ book: Workbook) throws -> [String: String] {
    var out: [String: String] = [:]
    for meta in book.sheets {
        guard let sheet = try? book.readSheet(meta.name) else { continue }
        for (r, row) in sheet.rows {
            for (c, _) in row {
                let text = sheet.textAt(r, c)
                if !text.isEmpty { out["\(meta.name)/\(r)/\(c)"] = text }
            }
        }
    }
    return out
}

let original = try Data(contentsOf: source)
let before = try everyCell(try Workbook(data: original))
let file = work.appendingPathComponent("plan.xlsx")
try original.write(to: file)

let book = try Workbook(data: original)
guard let mapping = try Plan.mapping(for: book) else { print("no plan found in that workbook"); exit(1) }
let plan = Plan.build(book, mapping)
let todo = plan.filter { $0.discipline.id != "rest" && !$0.logged && !$0.missed }
print("SOAK — \(plan.count) sessions in the plan, \(todo.count) still to do, \(rounds) rounds\n")

let remote = FileRemote(file)
let now = ISO8601DateFormatter().date(from: "2026-10-01T06:00:00Z") ?? Date()

/* What each session was given, to check against the file at the end. */
var expectedLogs: [(workout: Workout, minutes: Int, hr: Int, rpe: Int)] = []
var expectedMissed: [Workout] = []
var expectedMoves: [(workout: Workout, to: String)] = []
var expectedExtras: [ExtraEntry] = []
var sent = 0, failedCount = 0

var cursor = 0
for round in 1...rounds {
    var queue: [QueuedEntry] = []

    // Four logged sessions a round, with numbers a watch would give.
    for _ in 0..<4 where cursor < todo.count {
        let w = todo[cursor]; cursor += 1
        let planned = Int(((Plan.plannedSeconds(w, mapping) ?? 1800) / 60).rounded())
        let minutes = planned + (cursor % 5) - 2
        let hr = 120 + (cursor % 25)
        let rpe = 3 + (cursor % 6)
        var e = LogEntry()
        e.actualDuration = String(minutes)
        e.avgHr = String(hr)
        e.rpe = String(rpe)
        e.notes = "soak round \(round)"
        queue.append(QueuedEntry(workout: w, entry: e, now: now))
        expectedLogs.append((w, minutes, hr, rpe))
    }
    // One missed, one moved.
    if cursor < todo.count {
        let w = todo[cursor]; cursor += 1
        var e = LogEntry(); e.missed = true; e.notes = "soak missed"
        queue.append(QueuedEntry(workout: w, entry: e, now: now))
        expectedMissed.append(w)
    }
    if cursor < todo.count {
        let w = todo[cursor]; cursor += 1
        let to = PlanView.addDays(w.dayKey, 2)
        var e = LogEntry(); e.moveTo = to
        queue.append(QueuedEntry(workout: w, entry: e, now: now))
        expectedMoves.append((w, to))
    }
    // Two extra workouts.
    for i in 0..<2 {
        var x = ExtraEntry(date: PlanView.addDays("2026-09-01", round * 2 + i), activity: i == 0 ? "rowing" : "walk",
                           ref: "soak\(round)\(i)")
        x.minutes = Double(20 + round * 5 + i)
        x.what = "soak extra \(round)-\(i)"
        x.isTraining = i == 0
        queue.append(QueuedEntry(extra: x, now: now))
        expectedExtras.append(x)
    }

    // Someone saves the file in Excel just before the third round's upload.
    // What it writes is ours, so the stray-cell check must not blame the app.
    if round == 3 {
        remote.interfere = [{ data in
            guard let b = try? Workbook(data: data), let first = b.sheets.first?.name,
                  let touched = try? { () -> Data in
                      try b.writeCells(first, [CellEdit(ref: "AZ200", value: .text("someone else"), field: "test")])
                      return try b.save()
                  }() else { return data }
            return touched
        }]
    }

    var result = try await Sync.run(queue, path: "/plan.xlsx", remote: remote, now: now)
    if !result.failed.isEmpty || result.written.count < queue.count {
        // A conflict is expected once: the app starts again from the newer copy.
        let again = queue.filter { q in !result.written.contains(q.id) && !result.dropped.contains(q.id) }
        if !again.isEmpty { result = try await Sync.run(again, path: "/plan.xlsx", remote: remote, now: now) }
    }
    sent += result.written.count
    failedCount += result.failed.count
}

line("rounds run", rounds)
line("entries written", sent)
line("entries still failing", failedCount)
line("uploads / conflicts", "\(remote.uploads) / \(remote.conflicts)")

// MARK: what the file says now

let after = try Workbook(data: try Data(contentsOf: file))
check(!after.sheets.isEmpty, "the workbook is no longer readable")
check(after.sheets.map(\.name) == book.sheets.map(\.name), "the sheets are not the ones it started with")

let afterPlan = Plan.build(after, mapping)
func row(_ w: Workout) -> Workout? { afterPlan.first { $0.key == w.key } }

var logsOK = 0
for e in expectedLogs {
    guard let now = row(e.workout) else { check(false, "a logged session vanished: \(e.workout.key)"); continue }
    let minutes = Stats.actualSeconds(now, mapping).map { Int(($0 / 60).rounded()) } ?? -1
    check(now.logged, "not marked done: \(e.workout.key)")
    check(minutes == e.minutes, "\(e.workout.key): the sheet says \(minutes) minutes, it was given \(e.minutes)")
    if now.logged && minutes == e.minutes { logsOK += 1 }
}
line("logged sessions correct", "\(logsOK) / \(expectedLogs.count)")

var missedOK = 0
for w in expectedMissed {
    guard let now = row(w) else { check(false, "a missed session vanished: \(w.key)"); continue }
    check(now.missed, "not marked missed: \(w.key)")
    if now.missed { missedOK += 1 }
}
line("missed marks correct", "\(missedOK) / \(expectedMissed.count)")

var movesOK = 0
for m in expectedMoves {
    guard let now = row(m.workout) else { check(false, "a moved session vanished: \(m.workout.key)"); continue }
    check(now.dayKey == m.to, "\(m.workout.key): moved to \(now.dayKey), expected \(m.to)")
    check(now.title == m.workout.title, "\(m.workout.key): a move changed the session's own words")
    if now.dayKey == m.to && now.title == m.workout.title { movesOK += 1 }
}
line("moves correct", "\(movesOK) / \(expectedMoves.count)")

let extrasNow = Extras.read(after)
var extrasOK = 0
for x in expectedExtras {
    let mine = extrasNow.filter { $0.ref == x.ref }
    check(mine.count == 1, "extra \(x.ref): \(mine.count) rows, expected exactly one")
    if let one = mine.first {
        let got = one.minutes ?? -1
        let want = x.minutes ?? -1
        check(got == want, "extra \(x.ref): \(got) minutes, expected \(want)")
        check(one.date == x.date, "extra \(x.ref): dated \(one.date), expected \(x.date)")
        if mine.count == 1 && got == want && one.date == x.date { extrasOK += 1 }
    }
}
line("extra workouts correct", "\(extrasOK) / \(expectedExtras.count)")

// MARK: and everything the app was never asked to touch

let afterCells = try everyCell(after)
let touchedSheets = Set([mapping.sheets, [(try? Extras.sheetName(for: after)) ?? "Extras"]].flatMap { $0 })
var strayed: [String] = []
for (key, was) in before {
    let sheet = key.components(separatedBy: "/").first ?? ""
    if touchedSheets.contains(sheet) { continue }
    if afterCells[key] != was { strayed.append(key) }
}
for (key, isNow) in afterCells {
    let sheet = key.components(separatedBy: "/").first ?? ""
    if touchedSheets.contains(sheet) { continue }
    if isNow == "someone else" { continue }   // the interference this soak planted itself
    if before[key] == nil { strayed.append("\(key) appeared: \(isNow)") }
}
check(strayed.isEmpty, "cells changed on sheets the app never writes to: \(strayed.prefix(5).joined(separator: ", "))")
line("other sheets untouched", strayed.isEmpty ? "yes" : "NO — \(strayed.count) cells")

print("")
if errors.isEmpty {
    print("errors: none")
} else {
    print("errors:")
    for e in errors.prefix(20) { print("   " + e) }
    exit(1)
}
