import Foundation
import WorkoutCore

/*
 * stats-dump <workbook.xlsx> [...]
 *
 * The Progress figures the native reader derives from a workbook — kept,
 * streaks, by sport, trends, twelve weeks of load — in the shape
 * tools/js-dump.js prints from AmsSync.stats(), so tools/stats-parity.py can
 * put them side by side. Today is the real today on both sides.
 */
func dump(_ path: String) throws -> [String: Any] {
    let wb = try Workbook(data: try Data(contentsOf: URL(fileURLWithPath: path)))
    guard let mapping = try Plan.mapping(for: wb) else { return ["error": "no layout"] }
    let plan = Plan.build(wb, mapping)
    let today = PlanView.todayKey()
    let view = PlanView(plan: plan, mapping: mapping)
    let s = Stats.summarise(plan, moves: [:], movesSince: nil, today: today, mapping: mapping)
    let trends = Stats.trends(Stats.trendRows(plan, mapping))
    let load = Stats.load(Stats.loadRows(plan, mapping), weekStarts: Stats.recentWeekStarts(12, today: today),
                          endExclusive: PlanView.addDays(PlanView.weekStart(today), 7))
    let road = Stats.road(view.visible, today: today, mapping: mapping)
    let n = { (d: Double?) -> Any in d.map { $0.isFinite ? $0 : -1 } ?? NSNull() }
    return [
        "today": today,
        "summary": [
            "any": s.any, "counted": s.counted, "done": s.done, "missed": s.missed, "unlogged": s.unlogged, "answered": s.answered,
            "firstDay": s.firstDay.map { $0 as Any } ?? NSNull(), "lastDay": s.lastDay.map { $0 as Any } ?? NSNull(),
            "streak": ["current": s.streakCurrent, "longest": s.streakLongest],
            "sport": ["rows": s.sports.map { ["id": $0.id, "label": $0.label, "planned": $0.planned, "done": $0.done, "missed": $0.missed,
                                              "unlogged": $0.unlogged, "plannedSeconds": $0.plannedSeconds, "doneSeconds": $0.doneSeconds, "rate": n($0.rate)] },
                      "worst": s.worst.map { $0.id as Any } ?? NSNull()],
            "moves": ["missed": s.movesMissed, "moved": s.moved, "keptByMoving": n(s.keptByMoving)]
        ],
        "trends": trends.map { t -> [String: Any] in
            var d: [String: Any] = ["sport": t.sport, "enough": t.enough, "have": t.have, "need": t.need, "easyOnly": t.easyOnly]
            if !t.enough { d["usable"] = t.usable }
            if t.enough, let a = t.then, let b = t.now {
                d["sessions"] = t.sessions; d["change"] = t.change; d["verdict"] = t.verdict
                d["speedChange"] = t.speedChange; d["hrChange"] = t.hrChange
                d["then"] = ["sessions": a.sessions, "from": a.from, "to": a.to, "speed": a.speed, "hr": a.hr, "paceSeconds": a.paceSeconds, "perBeat": a.perBeat]
                d["now"] = ["sessions": b.sessions, "from": b.from, "to": b.to, "speed": b.speed, "hr": b.hr, "paceSeconds": b.paceSeconds, "perBeat": b.perBeat]
            }
            return d
        },
        "load": [
            "planned": load.planned, "actual": load.actual,
            "weeks": load.weeks.map { ["start": $0.start, "planned": $0.planned, "actual": $0.actual, "sessions": $0.sessions] },
            "sports": load.sports.map { ["sport": $0.sport, "planned": $0.planned, "actual": $0.actual, "shareActual": $0.shareActual, "sharePlanned": $0.sharePlanned] }
        ],
        "road": road.map { r -> [String: Any] in
            ["raceDay": r.raceDay, "raceTitle": r.raceTitle, "isRace": r.isRace, "start": r.start,
             "phases": r.phases.map { ["name": $0.name, "from": $0.from, "to": $0.to] },
             "sessions": r.sessions, "done": r.done, "behind": r.behind, "toCome": r.toCome,
             "plannedAll": r.plannedAll, "plannedSoFar": r.plannedSoFar, "doneSeconds": r.doneSeconds,
             "daysToGo": r.daysToGo, "weeksToGo": r.weeksToGo, "through": r.through, "started": r.started]
        } ?? NSNull()
    ]
}

var out: [String: Any] = [:]
for path in CommandLine.arguments.dropFirst() {
    do { out[URL(fileURLWithPath: path).lastPathComponent] = try dump(path) }
    catch { out[URL(fileURLWithPath: path).lastPathComponent] = ["error": error.localizedDescription] }
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]))
FileHandle.standardOutput.write("\n".data(using: .utf8)!)
