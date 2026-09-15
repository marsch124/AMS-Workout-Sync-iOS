import Foundation
import WorkoutCore

/*
 * write-dump <scenarios.json> <out-dir>
 *
 * Applies each scenario's logging steps to a fresh copy of its workbook with
 * the native writer and saves the result as <out-dir>/<name>.xlsx.
 * tools/js-write.js does the same with the web app's writer, and
 * tools/write-parity.py compares the two archives part by part.
 */

struct Step: Decodable {
    let key: String?
    let entry: [String: EntryValue]?
    let extra: [String: EntryValue]?
}

enum EntryValue: Decodable {
    case string(String), bool(Bool), number(Double)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string(try c.decode(String.self)) }
    }
    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var number: Double? { if case .number(let n) = self { return n } else { return nil } }
    var bool: Bool { if case .bool(let b) = self { return b } else { return false } }
}

extension Decoder {
    func singleContainer() throws -> SingleValueDecodingContainer { try singleValueContainer() }
}

struct Scenario: Decodable {
    let name: String
    let file: String
    let steps: [Step]
}

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: write-dump <scenarios.json> <out-dir>\n".data(using: .utf8)!)
    exit(2)
}

let scenarios = try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

var failures = 0
for scenario in scenarios {
    do {
        let workbook = try Workbook(data: Data(contentsOf: URL(fileURLWithPath: scenario.file)))
        guard let mapping = try Plan.mapping(for: workbook) else { throw NSError(domain: "no mapping", code: 1) }
        let plan = Plan.build(workbook, mapping)
        var names: [String: [Int: String]] = [:]
        for sheet in mapping.sheets { names[sheet] = learnWeekdayNames(try workbook.readSheet(sheet), mapping) }

        for step in scenario.steps {
            if let x = step.extra {
                var extra = ExtraEntry(date: x["date"]?.string ?? "", activity: x["activity"]?.string ?? "other", ref: x["ref"]?.string ?? "")
                extra.what = x["what"]?.string ?? ""
                extra.minutes = x["minutes"]?.number
                extra.distance = x["distance"]?.number
                extra.avgHr = x["avgHr"]?.number
                extra.effort = x["effort"]?.number
                extra.isTraining = x["isTraining"]?.bool ?? false
                extra.notes = x["notes"]?.string ?? ""
                let name = try Extras.ensureSheet(workbook)
                let sheet = try workbook.readSheet(name)
                if Extras.alreadyRecorded(sheet, extra) { continue }
                let built = Extras.buildEdits(sheet, extra, weekdayNames: names[mapping.sheets[0]] ?? [:])
                try workbook.writeCells(name, built.edits)
                continue
            }
            guard let key = step.key, let workout = plan.first(where: { $0.key == key }) else { throw NSError(domain: "no session \(step.key ?? "?")", code: 2) }
            var e = LogEntry()
            let v = step.entry ?? [:]
            e.actualDuration = v["actualDuration"]?.string
            e.actualDistance = v["actualDistance"]?.string
            e.distanceUnit = v["distanceUnit"]?.string
            e.avgHr = v["avgHr"]?.string
            e.maxHr = v["maxHr"]?.string
            e.avgSpeed = v["avgSpeed"]?.string
            e.avgPower = v["avgPower"]?.string
            e.cadence = v["cadence"]?.string
            e.elevation = v["elevation"]?.string
            e.calories = v["calories"]?.string
            e.rpe = v["rpe"]?.string
            e.avgPace = v["avgPace"]?.string
            e.notes = v["notes"]?.string
            e.doneLabel = v["doneLabel"]?.string
            e.completedAt = v["completedAt"]?.string.flatMap { iso.date(from: $0) }
            if case .bool(let b)? = v["missed"] { e.missed = b }
            e.moveTo = v["moveTo"]?.string
            if e.moveTo != nil { e.weekdayNames = names[workout.sheet] }

            let edits = Plan.buildEdits(workout, e, mapping)
            try workbook.writeCells(workout.sheet, edits)
        }
        try workbook.save().write(to: outDir.appendingPathComponent(scenario.name + ".xlsx"))
    } catch {
        failures += 1
        print("\(scenario.name): \(error)")
    }
}
print("\(scenarios.count - failures) of \(scenarios.count) written")
