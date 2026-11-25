/*
 * book-check <workbook.xlsx> [today yyyy-mm-dd]
 *
 * The move into the app, rehearsed on a copy: the workbook is taken in, the
 * plan is counted on both sides, and a spread of logging is written both into
 * Excel and into the book and compared. "differences: none" is the answer
 * wanted. Run it on a COPY; it writes nothing anywhere.
 */
import Foundation
import WorkoutCore

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first, let data = FileManager.default.contents(atPath: path) else {
    print("usage: book-check <workbook.xlsx> [today]"); exit(2)
}
let today = args.count > 1 ? args[1] : PlanView.todayKey()

do {
    let taken = try PlanImport.read(data, fileName: (path as NSString).lastPathComponent, today: today)
    print("today \(today)")
    for line in taken.proof.lines {
        print("  \(line.label.padding(toLength: 26, withPad: " ", startingAt: 0)) Excel \(line.before.padding(toLength: 7, withPad: " ", startingAt: 0)) app \(line.after.padding(toLength: 7, withPad: " ", startingAt: 0)) \(line.same ? "same" : "DIFFERENT")")
    }
    for m in taken.proof.after.months {
        print("  \(m.label): \(m.sessions) sessions, \(m.done) done, \(m.missed) missed, \(m.plannedMinutes) planned min, \(m.recordedMinutes) recorded min")
    }
    print("  weeks \(taken.book.weeks.count), easy \(taken.book.weeks.filter(\.isEasy).map { String($0.number) }.joined(separator: " ")), test \(taken.book.weeks.filter(\.isTest).map { String($0.number) }.joined(separator: " "))")
    print("  key sessions \(taken.book.sessions.filter(\.isKey).count), book size \(try taken.book.encoded().count) bytes")
    print("  odd values \(taken.oddities.count):")
    for o in taken.oddities { print("    [\(o.kind)] \(o.place) \(o.words)") }
    print("  import proof: \(taken.proof.matches ? "matches" : "DOES NOT MATCH") (\(taken.proof.compared) sessions compared, \(taken.proof.differences.count) differences)")

    let outcome = try BookOracle.run(data, today: today)
    print("logging both ways: \(outcome.entries) entries")
    print("differences: \(outcome.differences.isEmpty ? "none" : String(outcome.differences.count))")
    for d in outcome.differences.prefix(40) { print("  " + d) }
    exit(outcome.differences.isEmpty && taken.proof.matches ? 0 : 1)
} catch {
    print("failed: \(error.localizedDescription)"); exit(1)
}
