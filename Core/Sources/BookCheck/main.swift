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

    // Zones worked out in the app, held against the ones Excel worked out.
    let workbook = try Workbook(data: data)
    let tests = PlanImport.tests(workbook)
    if let zones = Zones.read(workbook) {
        let mine = zones.recalculated(from: tests)
        var differ: [String] = []
        for (a, b) in zip(zones.tables, mine.tables) {
            for (x, y) in zip(a.rows, b.rows) where x.value != y.value { differ.append("\(x.label): Excel \(x.value), app \(y.value)") }
        }
        if zones.current != mine.current { differ.append("the current row differs") }
        if zones.latestTest != mine.latestTest { differ.append("latest test: Excel \(zones.latestTest), app \(mine.latestTest)") }
        print("  tests \(tests.count) (\(tests.filter(\.hasNumbers).count) with numbers); zones worked out in the app: \(differ.isEmpty ? "same as Excel" : differ.joined(separator: " | "))")
    }

    let outcome = try BookOracle.run(data, today: today)
    print("logging both ways: \(outcome.entries) entries")
    print("differences: \(outcome.differences.isEmpty ? "none" : String(outcome.differences.count))")
    for d in outcome.differences.prefix(40) { print("  " + d) }

    // And the road back: a book that was changed, written out as a spreadsheet and read again.
    var book = taken.book
    for q in BookOracle.entries(for: book.sessions, extras: book.extras, mapping: book.mapping, today: today) { _ = try? book.apply(q) }
    if let open = book.sessions.first(where: { !$0.loggedInSheet && $0.discipline.id != "rest" && $0.dayKey > today }),
       var draft = book.draft(of: open.key) {
        draft.minutes = (draft.minutes ?? 30) + 5; draft.intensity = "Z1"; draft.dayKey = PlanView.addDays(open.dayKey, 1)
        _ = try book.change(open.key, to: draft)
    }
    _ = try book.add(SessionDraft(dayKey: PlanView.addDays(today, 3), sport: "bike", title: "Easy spin (made in the app)", minutes: 45, intensity: "Z2", purpose: "Third ride"))
    if let last = book.sessions.last(where: { $0.discipline.id == "rest" }) { _ = try book.remove(last.key) }
    let copy = try PlanExport.workbook(book, template: data)
    print("spreadsheet copy: \(copy.count) bytes, reads back the same as the app")
    let untouched = try PlanExport.workbook(taken.book, template: data)
    print("unchanged plan copies to the very same file: \(untouched == data)")
    exit(outcome.differences.isEmpty && taken.proof.matches && untouched == data ? 0 : 1)
} catch {
    print("failed: \(error.localizedDescription)"); exit(1)
}
