import Foundation

/*
 * What a logged session puts into the sheet: buildEdits from js/plan.js,
 * with the small parsers it leans on.
 *
 * The values arrive as the web app's form hands them over — strings, typed
 * by a person, with decimal commas and units in them — so the parsing is
 * ported with its JavaScript semantics intact: parseFloat reads a leading
 * number and ignores the rest, a string replace changes the first comma only,
 * Math.round rounds halves up. Each of those is a place a tidier Swift
 * rewrite would quietly write a different number into his plan.
 */

public struct LogEntry {
    public var actualDuration: String?
    public var actualDistance: String?
    public var distanceUnit: String?
    public var avgHr: String?
    public var maxHr: String?
    public var avgSpeed: String?
    public var avgPower: String?
    public var cadence: String?
    public var elevation: String?
    public var calories: String?
    public var rpe: String?
    public var avgPace: String?
    public var notes: String?
    public var doneLabel: String?
    public var completedAt: Date?
    public var missed = false
    public var moveTo: String?
    public var weekdayNames: [Int: String]?

    public init() {}

    func number(_ id: String) -> String? {
        switch id {
        case "avgHr": return avgHr
        case "maxHr": return maxHr
        case "avgSpeed": return avgSpeed
        case "avgPower": return avgPower
        case "cadence": return cadence
        case "elevation": return elevation
        case "calories": return calories
        case "rpe": return rpe
        default: return nil
        }
    }
}

let defaultDistanceUnit = ["swim": "m", "bike": "km", "run": "km", "other": "km", "strength": "km",
                           "mobility": "km", "brick": "km", "race": "km", "rest": "km"]

/* "12,5" -> "12.5": String.prototype.replace(',', '.') changes the first comma only. */
func firstCommaToDot(_ s: String) -> String { replaceFirst(",", in: s, with: ".") }

private let floatPrefix = Pattern("^[\\t\\n\\v\\f\\r \\u00a0\\ufeff]*([+-]?(?:Infinity|\\d+\\.?\\d*(?:[eE][+-]?\\d+)?|\\.\\d+(?:[eE][+-]?\\d+)?))")

/* parseFloat: the longest number at the start of the string, or NaN. */
func jsParseFloat(_ s: String) -> Double {
    guard let m = floatPrefix.first(s), let text = m[1] else { return .nan }
    if text.hasSuffix("Infinity") { return text.hasPrefix("-") ? -.infinity : .infinity }
    return Double(text) ?? .nan
}

/* Math.round: halves go up, towards positive infinity. */
func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

/* String.prototype.trim, whose idea of whitespace is not quite Foundation's:
   it includes the byte-order mark and leaves U+0085 alone. */
private let jsSpace: Set<UInt32> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
                                    0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F,
                                    0x205F, 0x3000, 0xFEFF]
func jsTrim(_ s: String) -> String {
    var scalars = Array(s.unicodeScalars)
    while let f = scalars.first, jsSpace.contains(f.value) { scalars.removeFirst() }
    while let l = scalars.last, jsSpace.contains(l.value) { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars))
}

private let clockDuration = Pattern("^(\\d+):([0-5]?\\d)(?::([0-5]?\\d))?$")
private let unitDuration = Pattern("(\\d+(?:\\.\\d+)?)\\s*(h|hr|hrs|hour|hours|std|stunden|stunde|m|min|mins|minute|minuten|s|sec|secs|sek|sekunden)?")
private let hourUnits = Pattern("^(h|hr|hrs|hour|hours|std|stunde|stunden)$")
private let secondUnits = Pattern("^(s|sec|secs|sek|sekunden)$")
private let paceClock = Pattern("(\\d+):([0-5]?\\d)")
private let commaDecimal = Pattern("^\\d+,\\d+$")

/* 45, 45min, 1:15, 1:15:30, 1h20, 1,5h, 90 min -> seconds. */
public func parseDuration(_ input: String?) -> Double? {
    guard let input else { return nil }
    let text = firstCommaToDot(jsTrim(input).lowercased())
    if text.isEmpty { return nil }

    if let m = clockDuration.first(text), let a = Double(m[1]!), let b = Double(m[2]!) {
        if let cText = m[3], let c = Double(cText) { return a * 3600 + b * 60 + c }
        return a * 3600 + b * 60
    }

    var seconds = 0.0
    var matched = false
    for m in unitDuration.matches(text) {
        guard let valueText = m[1] else { continue }
        let value = jsParseFloat(valueText)
        if value.isNaN { continue }
        let unit = m[2] ?? ""
        matched = true
        if hourUnits.test(unit) { seconds += value * 3600 }
        else if secondUnits.test(unit) { seconds += value }
        else { seconds += value * 60 }
    }
    return matched ? jsRound(seconds) : nil
}

/* "4:52" or "4:52 /km" -> seconds per unit. */
func parsePace(_ input: String) -> Double? {
    if let m = paceClock.first(input), let a = Double(m[1]!), let b = Double(m[2]!) {
        return a * 60 + b
    }
    let num = jsParseFloat(firstCommaToDot(input))
    return num.isNaN ? nil : jsRound(num * 60)
}

func decimalDot(_ text: String) -> String {
    commaDecimal.test(text) ? firstCommaToDot(text) : text
}

func durationToCell(_ seconds: Double, _ unit: String) -> Double {
    switch unit {
    case "time": return seconds / 86400
    case "minutes": return seconds / 60
    default: return seconds / 3600
    }
}

func distanceToCell(_ value: Double, _ entered: String, _ sheet: String) -> Double {
    if entered == sheet { return value }
    if entered == "km" && sheet == "m" { return value * 1000 }
    if entered == "m" && sheet == "km" { return value / 1000 }
    return value
}

/* How this sheet spells its weekdays, read from the pairs it already holds. */
public func learnWeekdayNames(_ sheet: Sheet, _ mapping: Mapping) -> [Int: String] {
    var names: [Int: String] = [:]
    guard let dateCol = mapping.columns["date"], let dayCol = mapping.columns["weekday"] else { return names }
    let last = min(mapping.lastDataRow > 0 ? mapping.lastDataRow : sheet.maxRow, mapping.firstDataRow + 400)
    guard mapping.firstDataRow <= last else { return names }
    for r in mapping.firstDataRow...last {
        guard let date = Plan.readDate(sheet, r, dateCol) else { continue }
        let text = sheet.textAt(r, dayCol)
        if text.isEmpty { continue }
        let index = utc.component(.weekday, from: date) - 1   // getUTCDay: Sunday = 0
        if names[index] == nil { names[index] = text }
    }
    return names
}

extension Plan {
    /*
     * The cell edits for one logged session. A move restates only the date
     * (and the weekday beside it); a missed session writes only the marker, a
     * note and when; anything else writes what was typed, the done marker
     * and when — and then passes through protectPlanColumns, the last gate
     * before a number could land on the plan's own text.
     */
    public static func buildEdits(_ workout: Workout, _ entry: LogEntry, _ mapping: Mapping) -> [CellEdit] {
        let units = mapping.units
        let columns = mapping.columns
        let row = workout.row
        var edits: [CellEdit] = []

        func push(_ field: String, _ value: EditValue) {
            guard let col = columns[field] else { return }
            if case .text(let t) = value, t.isEmpty { return }
            edits.append(CellEdit(ref: makeRef(col, row), value: value, field: field))
        }

        if let moveTo = entry.moveTo, !moveTo.isEmpty {
            if let moved = parseDayKey(moveTo) {
                push("date", .date(moved))
                if columns["weekday"] != nil, let names = entry.weekdayNames {
                    let index = utc.component(.weekday, from: moved) - 1
                    if let name = names[index] { push("weekday", .text(name)) }
                }
            }
            return edits
        }

        if entry.missed {
            if columns["done"] != nil { push("done", .text(mapping.missedValue)) }
            if let notes = entry.notes, !notes.isEmpty { push("notes", .text(jsTrim(notes))) }
            if columns["completedAt"] != nil { push("completedAt", .date(entry.completedAt ?? Date())) }
            return edits
        }

        if let seconds = parseDuration(entry.actualDuration) {
            push("actualDuration", .number(durationToCell(seconds, units.duration)))
        }

        if let distance = entry.actualDistance, !distance.isEmpty {
            let raw = jsParseFloat(firstCommaToDot(distance))
            if !raw.isNaN {
                let entered = (entry.distanceUnit?.isEmpty == false ? entry.distanceUnit : nil)
                    ?? defaultDistanceUnit[workout.discipline.id] ?? "km"
                push("actualDistance", .number(distanceToCell(raw, entered, units.distance)))
            }
        }

        for id in ["avgHr", "maxHr", "avgSpeed", "avgPower", "cadence", "elevation", "calories", "rpe"] {
            guard let raw = entry.number(id), !raw.isEmpty else { continue }
            let num = jsParseFloat(firstCommaToDot(raw))
            if !num.isNaN { push(id, .number(num)) }
        }

        if let pace = entry.avgPace, !pace.isEmpty {
            if units.paceIsTime {
                if let paceSeconds = parsePace(pace) { push("avgPace", .number(paceSeconds / 86400)) }
            } else {
                push("avgPace", .text(decimalDot(jsTrim(pace))))
            }
        }

        if let notes = entry.notes, !notes.isEmpty { push("notes", .text(jsTrim(notes))) }
        if columns["done"] != nil {
            let label = entry.doneLabel?.isEmpty == false ? entry.doneLabel! : (mapping.doneValue.isEmpty ? "Yes" : mapping.doneValue)
            push("done", .text(label))
        }
        if columns["completedAt"] != nil { push("completedAt", .date(entry.completedAt ?? Date())) }

        return protectPlanColumns(edits, columns)
    }

    /* Never write a result into a column the plan itself lives in. */
    static func protectPlanColumns(_ edits: [CellEdit], _ columns: [String: Int]) -> [CellEdit] {
        var protected: [Int: String] = [:]
        for field in Fields.all where !field.write && field.id != "date" && field.id != "weekday" {
            if let col = columns[field.id] { protected[col] = field.id }
        }
        if protected.isEmpty { return edits }
        return edits.filter { edit in
            guard let col = parseRef(edit.ref)?.col, let clash = protected[col] else { return true }
            return clash == edit.field
        }
    }
}
