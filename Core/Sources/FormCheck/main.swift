import Foundation
import WorkoutCore

/*
 * form-check <workbook.xlsx>
 *
 * The log form's shape against a real workbook: which boxes each sport gets,
 * what a recorded session opens with, that an untouched form saves nothing,
 * and that a swim's metres and a decimal comma reach the sheet as the web app
 * would write them. Ends with "errors: none".
 */
setbuf(stdout, nil)
var errors: [String] = []
func line(_ l: String, _ v: Any) { print("   " + l.padding(toLength: 46, withPad: " ", startingAt: 0) + "\(v)") }
func check(_ ok: Bool, _ m: String) { if !ok { errors.append(m) } }

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let wb = try Workbook(data: data)
let mapping = try Plan.mapping(for: wb)!
let plan = Plan.build(wb, mapping)

print("WHICH BOXES EACH SPORT GETS")
for sport in ["swim", "bike", "run", "strength"] {
    guard let w = plan.first(where: { $0.discipline.id == sport }) else { continue }
    let f = LogForm.fields(for: w, mapping)
    line(sport + " first", f.primary.map(\.id).joined(separator: " "))
    let extra = f.all.filter { e in !f.primary.contains { $0.id == e.id } }
    line(sport + " more", extra.map(\.id).joined(separator: " "))
    check(f.primary.first?.id == "actualDuration", sport + ": duration should come first")
    check(f.all.last?.id == "notes" || mapping.columns["notes"] == nil, sport + ": notes should be last")
    check(f.primary.last?.id == "notes" || mapping.columns["notes"] == nil, sport + ": notes should close the short form too")
    check(!f.all.contains { $0.id == "done" || $0.id == "completedAt" }, sport + ": done/logged-on must never be a box")
    if sport == "swim" { check(f.primary.first { $0.id == "actualDistance" }?.unit == "m", "a swim's distance box should ask for metres") }
    if sport == "bike" { check(f.primary.first { $0.id == "avgPace" }?.label == "Average speed", "the bike's pace box should ask for speed") }
}

print("\nA RECORDED SESSION OPENS FILLED IN")
if let done = plan.first(where: { $0.loggedInSheet && $0.discipline.id == "run" }) {
    var opened: [String: String] = [:]
    for f in LogForm.fields(for: done, mapping).primary { opened[f.id] = LogForm.recordedValue(done, f.id, mapping, waiting: nil) }
    line("duration box", opened["actualDuration"] ?? "")
    line("distance box", opened["actualDistance"] ?? "")
    line("heart rate box", opened["avgHr"] ?? "")
    check(opened["actualDuration"] == done.results["actualDuration"]?.text, "minutes sheet: duration box should show the sheet's number")
    check(LogForm.changedOnly(opened, openedWith: opened).isEmpty, "an untouched form must have nothing to save")
    var edited = opened; edited["avgHr"] = "140"
    let changes = LogForm.changedOnly(edited, openedWith: opened)
    line("after changing one box, saves", changes.keys.joined(separator: " "))
    check(changes.keys.sorted() == ["avgHr"], "changing one box must save exactly that box")
}
if let swim = plan.first(where: { $0.loggedInSheet && $0.discipline.id == "swim" }) {
    let shown = LogForm.recordedValue(swim, "actualDistance", mapping, waiting: nil)
    line("swim distance in sheet / in box", (swim.results["actualDistance"]?.text ?? "") + " km / " + shown + " m")
    check(Double(shown) == (swim.results["actualDistance"]?.number ?? 0) * 1000, "a swim's km should open as metres")
}

print("\nWHAT A FILLED FORM WRITES")
if let swim = plan.first(where: { !$0.loggedInSheet && $0.discipline.id == "swim" }) {
    let entry = LogForm.entry(from: ["actualDuration": "41", "actualDistance": "1750", "avgPace": "1:52", "notes": " fine "], distanceUnit: "m")
    let edits = Plan.buildEdits(swim, entry, mapping)
    let byField = Dictionary(uniqueKeysWithValues: edits.map { ($0.field, $0.value) })
    line("distance written", "\(byField["actualDistance"] ?? .blank)")
    check(byField["actualDistance"] == .number(1.75), "1750 m should reach a km sheet as 1.75")
    check(byField["notes"] == .text("fine"), "notes should be trimmed")
}
if let run = plan.first(where: { !$0.loggedInSheet && $0.discipline.id == "run" }) {
    let entry = LogForm.entry(from: ["actualDistance": "10,4", "avgHr": "142"], distanceUnit: "km")
    let edits = Plan.buildEdits(run, entry, mapping)
    let byField = Dictionary(uniqueKeysWithValues: edits.map { ($0.field, $0.value) })
    line("10,4 km written as", "\(byField["actualDistance"] ?? .blank)")
    check(byField["actualDistance"] == .number(10.4), "a decimal comma must reach the sheet as 10.4")
    check(byField["actualDuration"] == nil, "a box left empty must not be written")
    check(byField["done"] != nil, "a log writes the done marker")
}

print("\nEFFORT IN WORDS")
line("6,5 reads as", LogForm.rpeNote("6,5"))
check(LogForm.rpeNote("6,5") == LogForm.rpeScale[6], "half-steps read down")
check(LogForm.rpeNote("11").isEmpty && LogForm.rpeNote("x").isEmpty, "out of range says nothing")

print("\nerrors:", errors.isEmpty ? "none" : "\n - " + errors.joined(separator: "\n - "))
exit(errors.isEmpty ? 0 : 1)
