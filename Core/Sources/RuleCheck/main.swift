/*
 * rule-check <workbook.xlsx> <from yyyy-mm-dd> <to yyyy-mm-dd> [--import yyyy-mm-dd] [-v] [--sessions]
 *
 * The rule book walked over past days on a COPY of a plan: each day from
 * `from` to `to` is "today" in turn (morning, then evening), the engine is run
 * with what was known by then, and every card it would have shown is printed.
 * Unanswered cards close as "Keep my plan". The plan is taken into the app on
 * `--import` (default: `to`). -v also prints the triggers that fired but were
 * silenced by a limit; --sessions prints how each session was classed.
 * --extra day:activity:minutes (repeatable) adds an activity the workbook does
 * not hold, such as a hike only the watch recorded.
 * It writes nothing anywhere.
 */
import Foundation
import WorkoutCore

var args = Array(CommandLine.arguments.dropFirst())
let verbose = args.contains("-v")
let listSessions = args.contains("--sessions")
var importDay: String?
if let i = args.firstIndex(of: "--import"), i + 1 < args.count { importDay = args[i + 1]; args.removeSubrange(i...(i + 1)) }
var added: [RBExtra] = []
while let i = args.firstIndex(of: "--extra"), i + 1 < args.count {
    let p = args[i + 1].split(separator: ":").map(String.init)
    if p.count == 3, let m = Int(p[2]) { added.append(RBExtra(day: p[0], activity: p[1], minutes: m, countsAsTraining: p[1] != "walk")) }
    args.removeSubrange(i...(i + 1))
}
args.removeAll { $0 == "-v" || $0 == "--sessions" }
guard args.count == 3, let data = FileManager.default.contents(atPath: args[0]) else {
    print("usage: rule-check <copy.xlsx> <from> <to> [--import day] [-v] [--sessions]"); exit(2)
}
let from = args[1], to = args[2]

do {
    let taken = try PlanImport.read(data, fileName: (args[0] as NSString).lastPathComponent, today: to)
    let input = RuleBook.input(book: taken.book, extras: added, today: from, importDay: importDay ?? to)
    print("plan starts \(input.planStart); \(input.sessions.count) sessions, \(input.extras.count) extras")
    if listSessions {
        for w in input.weeks { print("  week \(w.number) \(w.monday) \(w.tag.rawValue)\(w.isTaper ? " taper" : "") \(w.phase) cap \(input.weekCaps[w.number] ?? 0)") }
        for s in input.sessions where s.day >= PlanView.addDays(from, -21) && s.day <= PlanView.addDays(to, 7) {
            let l = RuleBook.labels(s)
            print("  \(s.day) \(RuleBookWords.day(s.day)) w\(RuleBook.planWeek(s.day, start: input.planStart))/o\(s.originalWeek) \(s.slot.rawValue) \(RuleBook.sessionClass(s).rawValue)\(l.key ? " key" : "")\(l.long ? " long" : "") \(s.status.rawValue) \(s.plannedMin)/\(s.actualMin.map(String.init) ?? "-") rpe \(s.rpe.map(String.init) ?? "-")\(RuleBook.feltHarder(s, today: to, margin: 2) ? " HARDER" : "") | \(s.title.prefix(40)) | \(s.intensity)")
        }
        for x in input.extras where x.day >= PlanView.addDays(from, -28) && x.day <= to {
            print("  extra \(x.day) \(x.activity) \(x.minutes) min\(x.countsAsTraining ? " counts" : "")")
        }
        var w = RuleBook.planWeek(from, start: input.planStart)
        while input.monday(w) <= to {
            print("  week \(w): counted \(input.counted(w)) of cap \(input.weekCaps[w] ?? 0)")
            w += 1
        }
    }
    var cards = 0
    for line in RuleBook.replay(input, from: from, to: to) {
        let o = line.outcome
        if let s = o.suggestion {
            cards += 1
            print("\(line.day) \(RuleBookWords.day(line.day)) \(line.moment.rawValue) \(s.trigger.rawValue)\(s.step > 0 ? " step \(s.step)" : ""): \(s.headline)")
            print("    \(s.why)")
            for c in s.otherChoices { print("    other choice: \(c.headline)") }
        } else if verbose, let t = o.fired {
            print("\(line.day) \(line.moment.rawValue) \(t.rawValue) fired, silent:")
            for tried in o.tried { print("    \(tried.headline) — " + tried.failed.map { "\($0.limit.rawValue) \($0.reason)" }.joined(separator: "; ")) }
        }
    }
    print("cards: \(cards)")
} catch {
    print("could not read: \(error)"); exit(1)
}

extension RuleBookInput {
    func monday(_ w: Int) -> String { PlanView.addDays(planStart, 7 * (w - 1)) }
    func counted(_ w: Int) -> Int {
        let m = monday(w)
        var total = 0
        for d in 0..<7 {
            let day = PlanView.addDays(m, d)
            for s in sessions where s.day == day && s.status == .done && !s.isRest && !s.dropped { total += s.actualMin ?? s.plannedMin }
            for x in extras where x.day == day && (x.countsAsTraining || x.activity == "hike") { total += x.minutes }
        }
        return total
    }
}
