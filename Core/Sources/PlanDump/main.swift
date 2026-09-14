import Foundation
import WorkoutCore

/*
 * plan-dump <workbook.xlsx>
 *
 * Prints what the native reader makes of a workbook, as JSON in exactly the
 * shape tools/js-dump.js prints for the web app, so tools/parity.py can put
 * the two side by side and name every session they disagree about.
 */

func dump(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let workbook = try Workbook(data: data)
    guard let mapping = try Plan.mapping(for: workbook) else { return ["mapping": NSNull(), "workouts": []] }
    let plan = Plan.build(workbook, mapping)

    let workouts: [[String: Any]] = plan.map { w in
        [
            "key": w.key,
            "sheet": w.sheet,
            "row": w.row,
            "rows": w.rows,
            "dayKey": w.dayKey,
            "discipline": w.discipline.id,
            "title": w.title,
            "phase": w.phase,
            "sections": w.sections.map { ["kind": $0.kind, "label": $0.label, "text": $0.text] },
            "plannedDurationRaw": w.planned.durationRaw ?? NSNull(),
            "plannedDistanceRaw": w.planned.distanceRaw ?? NSNull(),
            "intensity": w.planned.intensity,
            "plannedSeconds": Plan.plannedSeconds(w, mapping) ?? NSNull(),
            "results": w.results.mapValues { $0.text },
            "loggedInSheet": w.loggedInSheet,
            "missed": w.missed
        ]
    }

    var columns: [String: Any] = [:]
    for (k, v) in mapping.columns { columns[k] = v }
    return [
        "mapping": [
            "sheets": mapping.sheets,
            "headerRow": mapping.headerRow,
            "firstDataRow": mapping.firstDataRow,
            "lastDataRow": mapping.lastDataRow,
            "mode": mapping.mode,
            "sectionColumn": mapping.sectionColumn ?? NSNull(),
            "columns": columns,
            "units": ["duration": mapping.units.duration, "distance": mapping.units.distance,
                      "paceIsTime": mapping.units.paceIsTime],
            "doneValue": mapping.doneValue,
            "missedValue": mapping.missedValue
        ],
        "workouts": workouts
    ]
}

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    FileHandle.standardError.write("usage: plan-dump <workbook.xlsx> [...]\n".data(using: .utf8)!)
    exit(2)
}

var out: [String: Any] = [:]
for path in paths {
    do {
        out[URL(fileURLWithPath: path).lastPathComponent] = try dump(path)
    } catch {
        out[URL(fileURLWithPath: path).lastPathComponent] = ["error": error.localizedDescription]
    }
}
let json = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write("\n".data(using: .utf8)!)
