/*
 * zones-dump <workbook.xlsx> [...]
 *
 * What the app reads out of the Test Results & Zones sheet, as JSON, with a
 * few worked examples of what a session's intensity would show — checked by
 * tools/zones-parity.py against openpyxl reading the same cells.
 */
import Foundation
import WorkoutCore

struct Example: Codable { let intensity: String; let sport: String; let tables: [ZoneTable] }
struct Out: Codable { let zones: Zones?; let examples: [Example] }

var result: [String: Out] = [:]
for path in CommandLine.arguments.dropFirst() {
    let name = (path as NSString).lastPathComponent
    guard let data = FileManager.default.contents(atPath: path), let wb = try? Workbook(data: data) else {
        result[name] = Out(zones: nil, examples: []); continue
    }
    let z = Zones.read(wb)
    let samples: [(String, String)] = [("Z4–Z5", "bike"), ("Z2", "run"), ("Z1–Z2", "swim"), ("RPE 6", "strength"), ("upper Z2–low Z3", "brick")]
    result[name] = Out(zones: z, examples: samples.map { Example(intensity: $0.0, sport: $0.1, tables: z?.explain(intensity: $0.0, sport: $0.1) ?? []) })
}
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(data: try enc.encode(result), encoding: .utf8)!)
