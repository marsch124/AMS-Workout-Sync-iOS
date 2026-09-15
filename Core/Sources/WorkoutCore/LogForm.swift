import Foundation

/*
 * The log form's shape: which boxes a session is offered, in what order, in
 * which unit, filled with what. A port of formFields() in js/plan.js and the
 * field configuration in js/ui.js, kept out of the views so it can be checked
 * on the Mac against his own workbook.
 *
 * The split into primary and extra is about ordering, not permission: every
 * column the sheet has is reachable on every session. What the discipline
 * decides is only what is asked for first.
 */

public struct FormField: Identifiable, Equatable {
    public enum Keys { case text, decimal, digits, multiline }
    public let id: String
    public let label: String
    public let unit: String
    public let placeholder: String
    public let keys: Keys
    public let hint: String
}

public enum LogForm {
    static let preference: [String: [String]] = [
        "swim":     ["actualDuration", "actualDistance", "avgPace", "avgHr", "maxHr", "rpe", "calories", "notes"],
        "bike":     ["actualDuration", "actualDistance", "avgPace", "avgSpeed", "avgPower", "avgHr", "maxHr", "cadence", "elevation", "rpe", "calories", "notes"],
        "run":      ["actualDuration", "actualDistance", "avgPace", "avgHr", "maxHr", "cadence", "elevation", "rpe", "calories", "notes"],
        "strength": ["actualDuration", "rpe", "avgHr", "calories", "notes"],
        "mobility": ["actualDuration", "rpe", "notes"],
        "other":    ["actualDuration", "actualDistance", "avgHr", "maxHr", "rpe", "calories", "notes"],
        "brick":    ["actualDuration", "actualDistance", "avgPace", "avgSpeed", "avgPower", "avgHr", "maxHr", "rpe", "calories", "notes"],
        "race":     ["actualDuration", "actualDistance", "avgPace", "avgHr", "maxHr", "rpe", "calories", "notes"],
        "rest":     []
    ]

    static let units: [String: String] = [
        "avgHr": "bpm", "maxHr": "bpm", "avgSpeed": "km/h", "avgPower": "watt", "cadence": "rpm / spm",
        "elevation": "m", "calories": "kcal", "rpe": "1-10"
    ]

    /* The one Avg Pace/Pwr column asks a different question per sport. */
    public static func pace(for disciplineId: String) -> (label: String, unit: String, placeholder: String, keys: FormField.Keys) {
        switch disciplineId {
        case "bike": return ("Average speed", "km/h", "e.g. 32.5", .decimal)
        case "swim": return ("Pace", "per 100m", "e.g. 1:45", .text)
        default: return ("Pace", "min/km", "e.g. 4:52", .text)
        }
    }

    /* The unit a distance is typed in: swimmers count metres. */
    public static func distanceUnit(for disciplineId: String) -> String {
        defaultDistanceUnit[disciplineId] ?? "km"
    }

    static func field(_ id: String, _ workout: Workout) -> FormField {
        let label = Fields.byId[id]?.label ?? id
        switch id {
        case "actualDuration":
            return FormField(id: id, label: label, unit: "", placeholder: "e.g. 45", keys: .text,
                             hint: "Just a number means minutes — 45 is 45 minutes, 90 is an hour and a half. Or write it out: 1:15, 1h20, 90min.")
        case "actualDistance":
            return FormField(id: id, label: label, unit: distanceUnit(for: workout.discipline.id),
                             placeholder: workout.discipline.id == "swim" ? "e.g. 2400" : "e.g. 12.4", keys: .decimal, hint: "")
        case "avgPace":
            let p = pace(for: workout.discipline.id)
            return FormField(id: id, label: p.label, unit: p.unit, placeholder: p.placeholder, keys: p.keys, hint: "")
        case "rpe":
            return FormField(id: id, label: label, unit: "1-10", placeholder: "1 easy — 10 all out", keys: .digits, hint: "")
        case "avgHr", "maxHr", "cadence":
            return FormField(id: id, label: label, unit: units[id] ?? "", placeholder: "", keys: .digits, hint: "")
        case "notes":
            return FormField(id: id, label: label, unit: "", placeholder: "How it felt, conditions, anything worth remembering", keys: .multiline, hint: "")
        default:
            return FormField(id: id, label: label, unit: units[id] ?? "", placeholder: "", keys: .decimal, hint: "")
        }
    }

    /*
     * Which fields the form offers. `primary` is what the form opens with,
     * the sport's own order; `all` is every column the sheet has, with notes
     * moved to the end so they are not stranded mid-list once the extra
     * fields are revealed. As formFields() in the web app.
     */
    public static func fields(for workout: Workout, _ mapping: Mapping) -> (primary: [FormField], all: [FormField]) {
        let preferred = preference[workout.discipline.id] ?? preference["other"]!
        let available = Fields.resultFields.filter { mapping.columns[$0] != nil }
        let managed: Set<String> = ["done", "completedAt"]
        let primaryIds = preferred.filter { available.contains($0) && !managed.contains($0) }
        let extraIds = available.filter { !primaryIds.contains($0) && !managed.contains($0) }
        var allIds = primaryIds + extraIds
        if let at = allIds.firstIndex(of: "notes"), at != allIds.count - 1 {
            allIds.remove(at: at)
            allIds.append("notes")
        }
        return (primaryIds.map { field($0, workout) }, allIds.map { field($0, workout) })
    }

    /*
     * What the box shows when the form opens: the value waiting to sync if
     * there is one, else what the sheet holds — in the unit the box asks for,
     * so a duration reads as minutes and a swim's distance as metres.
     */
    public static func recordedValue(_ workout: Workout, _ fieldId: String, _ mapping: Mapping, waiting: LogEntry?) -> String {
        if let waiting {
            if waiting.missed { return "" }
            switch fieldId {
            case "actualDuration": return waiting.actualDuration ?? ""
            case "actualDistance": return waiting.actualDistance ?? ""
            case "avgPace": return waiting.avgPace ?? ""
            case "notes": return waiting.notes ?? ""
            default: return waiting.number(fieldId) ?? ""
            }
        }
        guard let cell = workout.results[fieldId] else { return "" }
        switch fieldId {
        case "actualDuration":
            guard let n = cell.number, let seconds = durationFromCell(n, mapping.units.duration) else { return cell.text }
            return jsNumberString((seconds / 60 * 100).rounded() / 100)
        case "actualDistance":
            guard let n = cell.number else { return cell.text }
            let shown = distanceToCell(n, mapping.units.distance, distanceUnit(for: workout.discipline.id))
            return jsNumberString((shown * 1000).rounded() / 1000)
        default:
            return cell.text
        }
    }

    /* Only the boxes that were altered, so a correction of one cell never rewrites four. */
    public static func changedOnly(_ values: [String: String], openedWith: [String: String]) -> [String: String] {
        values.filter { key, value in value != (openedWith[key] ?? "") }
    }

    public static func entry(from values: [String: String], distanceUnit: String) -> LogEntry {
        var e = LogEntry()
        let v = { (id: String) -> String? in
            guard let s = values[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        e.actualDuration = v("actualDuration")
        e.actualDistance = v("actualDistance")
        if e.actualDistance != nil { e.distanceUnit = distanceUnit }
        e.avgHr = v("avgHr"); e.maxHr = v("maxHr"); e.avgSpeed = v("avgSpeed"); e.avgPower = v("avgPower")
        e.cadence = v("cadence"); e.elevation = v("elevation"); e.calories = v("calories"); e.rpe = v("rpe")
        e.avgPace = v("avgPace"); e.notes = v("notes")
        return e
    }

    public static let rpeScale: [String] = [
        "",
        "Barely moving. You could keep this up all day.",
        "Very easy. Warming up, or coming back down.",
        "Easy. Talking takes no effort at all.",
        "Steady. Still talking in whole sentences.",
        "Moderate. The sentences are getting shorter.",
        "Firm. A few words at a time.",
        "Hard. Single words, and you are watching the clock.",
        "Very hard. Talking is out.",
        "Nearly everything. You are counting down to the end.",
        "Everything. You could not hold this for long."
    ]

    /* Half-steps read down: 6.5 is described as a 6. */
    public static func rpeNote(_ raw: String) -> String {
        let value = jsParseFloat(firstCommaToDot(raw))
        guard value.isFinite else { return "" }
        let n = Int(value.rounded(.down))
        guard n >= 1, n <= 10 else { return "" }
        return rpeScale[n]
    }
}
