import Foundation

/*
 * The training plan: mapped spreadsheet rows turned into sessions.
 *
 * A port of the reading half of js/plan.js. What gets *written* — buildEdits,
 * the done marker, units going back into cells — is stage 2 and is not here
 * yet, deliberately.
 */

public struct Discipline: Equatable, Hashable {
    public let id: String
    public let label: String
    public let synonyms: [String]
}

public enum Disciplines {
    public static let five: [Discipline] = [
        Discipline(id: "swim", label: "Swim",
                   synonyms: ["swim", "swimming", "schwimmen", "schwimmtraining", "pool", "open water",
                              "freiwasser", "kraul", "crawl", "bahnen"]),
        Discipline(id: "bike", label: "Bike",
                   synonyms: ["bike", "biking", "cycling", "cycle", "rad", "radfahren", "radeln", "velo",
                              "ride", "spinning", "mtb", "rennrad", "turbo", "rollentraining", "indoor bike"]),
        Discipline(id: "run", label: "Run",
                   synonyms: ["run", "running", "laufen", "lauf", "jog", "jogging", "joggen", "trail",
                              "trailrun", "dauerlauf", "bahn"]),
        Discipline(id: "strength", label: "Strength",
                   synonyms: ["strength", "kraft", "krafttraining", "gym", "weights", "lifting", "core",
                              "rumpf", "stabilisation", "stabi", "athletik"]),
        Discipline(id: "mobility", label: "Mobility",
                   synonyms: ["mobility", "mobilitat", "beweglichkeit", "yoga", "faszien", "foam roll",
                              "faszientraining", "mobi",
                              "stretch", "stretching", "dehnen", "dehnung", "flexibility", "dehnprogramm"])
    ]

    public static let compound: [Discipline] = [
        Discipline(id: "brick", label: "Brick",
                   synonyms: ["brick", "bike run", "bike + run", "rad lauf", "koppeltraining", "koppel"]),
        Discipline(id: "race", label: "Race",
                   synonyms: ["race", "rennen", "wettkampf", "ironman", "event", "competition"])
    ]

    public static let rest = Discipline(id: "rest", label: "Rest",
        synonyms: ["rest", "rest day", "ruhetag", "ruhe", "pause", "frei", "off", "day off", "recovery day"])

    public static let other = Discipline(id: "other", label: "Other", synonyms: [])

    static let all: [Discipline] = compound + [rest] + five
    private static let normalised: [(Discipline, [String])] = all.map { ($0, $0.synonyms.map(normalise)) }

    public static func classify(_ raw: String) -> Discipline {
        let text = normalise(raw)
        if text.isEmpty { return other }
        var best: Discipline?
        var bestLength = 0
        for (discipline, synonyms) in normalised {
            for s in synonyms where !s.isEmpty {
                if text == s || text.hasPrefix(s) || text.contains(s), s.count > bestLength {
                    bestLength = s.count
                    best = discipline
                }
            }
        }
        return best ?? other
    }

    public static func order(_ id: String) -> Int {
        five.firstIndex { $0.id == id } ?? five.count
    }
}

public struct Section: Equatable {
    public let kind: String
    public let label: String
    public let text: String
}

public struct ResultValue: Equatable {
    public let text: String
    public let number: Double?
    public let date: Date?
}

public struct Planned: Equatable {
    public var durationRaw: Double?
    public var distanceRaw: Double?
    public var intensity: String
    public var description: String
}

public struct Workout: Identifiable, Equatable {
    public var id: String { key }
    public let key: String
    public let sheet: String
    public let row: Int
    public var rows: [Int]
    public let date: Date
    public let dayKey: String
    public var disciplineRaw: String
    public var discipline: Discipline
    public var title: String
    public var phase: String
    public var sections: [Section]
    public var planned: Planned
    public var results: [String: ResultValue]
    public var loggedInSheet: Bool
    public var missed: Bool
}

let sectionOrder = ["warmup", "intervals", "technique", "cooldown"]
let sectionLabels = ["warmup": "Warm-up", "intervals": "Intervals", "cooldown": "Cool-down",
                     "technique": "Technique", "main": "Session"]

func classifySection(_ raw: String) -> String {
    let text = normalise(raw)
    if text.isEmpty { return "main" }
    for id in ["warmup", "intervals", "cooldown", "technique"] {
        for s in Fields.normalisedSynonyms[id] ?? [] where !s.isEmpty {
            if text == s || text.contains(s) { return id }
        }
    }
    return "main"
}

// MARK: - durations

public func durationFromCell(_ value: Double?, _ unit: String) -> Double? {
    guard let value, !value.isNaN else { return nil }
    switch unit {
    case "time": return value * 86400
    case "minutes": return value * 60
    default: return value * 3600
    }
}

public func formatDuration(_ seconds: Double?) -> String {
    guard let seconds, !seconds.isNaN else { return "" }
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return "\(h)h " + String(format: "%02dm", m) }
    if m > 0 { return s > 0 ? "\(m)m " + String(format: "%02ds", s) : "\(m)m" }
    return "\(s)s"
}

private let minuteWords = Pattern("\\b(min|mins|minute|minutes|minuten)\\b")
private let hourWords = Pattern("\\b(h|hr|hrs|hour|hours|std|stunden)\\b")
private let clockWords = Pattern("\\b(hh|hh mm|hh mm ss|h mm)\\b")
private let kmWords = Pattern("\\b(km|kilometer|kilometre|kilometers|kilometres)\\b")
private let metreWords = Pattern("\\b(m|meter|metre|meters|metres|meilen)\\b")

func unitFromHeading(_ heading: String) -> String? {
    let text = normalise(heading)
    if text.isEmpty { return nil }
    if minuteWords.test(text) { return "minutes" }
    if hourWords.test(text) { return "hours" }
    if clockWords.test(text) { return "time" }
    return nil
}

func distanceUnitFromHeading(_ heading: String) -> String? {
    let text = normalise(heading)
    if text.isEmpty { return nil }
    if kmWords.test(text) { return "km" }
    if metreWords.test(text) { return "m" }
    return nil
}

private func dataRows(_ sheet: Sheet, _ mapping: Mapping, extra: Int) -> ClosedRange<Int>? {
    let last = min(mapping.lastDataRow > 0 ? mapping.lastDataRow : sheet.maxRow, mapping.firstDataRow + extra)
    return mapping.firstDataRow <= last ? mapping.firstDataRow...last : nil
}

func inferDurationUnitFromData(_ workbook: Workbook, _ sheet: Sheet, _ col: Int?, _ mapping: Mapping) -> String? {
    guard let col, let range = dataRows(sheet, mapping, extra: 200) else { return nil }
    var samples: [Double] = []
    var timeFormatted = 0
    for r in range {
        guard let cell = sheet.cell(r, col) else { continue }
        if cell.styleIndex >= 0 && workbook.dateStyles.contains(cell.styleIndex) { timeFormatted += 1 }
        if let n = cell.number, n > 0 { samples.append(n) }
    }
    if timeFormatted >= 1 && Double(timeFormatted) >= Double(samples.count) / 2 { return "time" }
    if samples.isEmpty { return nil }
    samples.sort()
    return samples[samples.count / 2] >= 10 ? "minutes" : "hours"
}

func inferDistanceUnitFromData(_ sheet: Sheet, _ col: Int?, _ mapping: Mapping) -> String? {
    guard let col, let range = dataRows(sheet, mapping, extra: 200) else { return nil }
    var samples: [Double] = []
    for r in range {
        if let n = sheet.cell(r, col)?.number, n > 0 { samples.append(n) }
    }
    if samples.isEmpty { return nil }
    samples.sort()
    return samples[samples.count / 2] >= 400 ? "m" : "km"
}

func columnIsTimeFormatted(_ workbook: Workbook, _ sheet: Sheet, _ col: Int?, _ mapping: Mapping) -> Bool {
    guard let col, let range = dataRows(sheet, mapping, extra: 200) else { return false }
    var hits = 0
    var seen = 0
    for r in range {
        guard let cell = sheet.cell(r, col), cell.styleIndex >= 0 else { continue }
        seen += 1
        if workbook.dateStyles.contains(cell.styleIndex) { hits += 1 }
    }
    return seen > 0 && Double(hits) >= Double(seen) / 2
}

// MARK: - done and missed markers

let affirmative = ["\u{2713}", "\u{2714}", "\u{2705}", "x", "yes", "y", "ja", "done", "ok",
                   "erledigt", "fertig", "complete", "completed", "true", "1"]
let negative = ["missed", "miss", "skipped", "skip", "verpasst", "ausgefallen", "versaumt",
                "nein", "no", "not done", "dnf", "abgebrochen", "false", "0"]

func detectDoneMarkers(_ workbook: Workbook, _ mapping: Mapping) -> (done: String?, missed: String?) {
    guard let col = mapping.columns["done"] else { return (nil, nil) }
    let letter = indexToCol(col)
    let pattern = Pattern("\\$" + letter + "(?::\\$" + letter + ")?\\s*,\\s*\"([^\"]{1,24})\"")
    var found: [String] = []

    for meta in workbook.sheets {
        guard let sheet = try? workbook.readSheet(meta.name) else { continue }
        // Row and column order, as the JS walks its Maps in the order the XML listed them.
        for rowNum in sheet.rows.keys.sorted() {
            guard let row = sheet.rows[rowNum] else { continue }
            for colNum in row.keys.sorted() {
                let formula = row[colNum]!.formula
                guard formula.contains("COUNTIF") else { continue }
                for m in pattern.matches(formula) { if let v = m[1] { found.append(v) } }
            }
        }
    }

    var done: String?
    var missed: String?
    for candidate in found {
        let key = candidate.lowercased()
        if done == nil, affirmative.contains(key) { done = candidate }
        if missed == nil, negative.contains(key) { missed = candidate }
    }
    return (done, missed)
}

// MARK: - reading the plan

public enum Plan {
    /* Detection, then units and markers — the web app's autoDetect followed by prepareMapping. */
    public static func mapping(for workbook: Workbook) throws -> Mapping? {
        guard var mapping = try autoDetect(workbook) else { return nil }
        guard let sheet = try? workbook.readSheet(mapping.sheets[0]) else { return mapping }
        let heading = { (id: String) -> String in
            guard let col = mapping.columns[id] else { return "" }
            return sheet.textAt(mapping.headerRow, col)
        }

        mapping.units.duration = unitFromHeading(heading("actualDuration"))
            ?? unitFromHeading(heading("plannedDuration"))
            ?? inferDurationUnitFromData(workbook, sheet, mapping.columns["actualDuration"], mapping)
            ?? inferDurationUnitFromData(workbook, sheet, mapping.columns["plannedDuration"], mapping)
            ?? "hours"
        mapping.units.distance = distanceUnitFromHeading(heading("actualDistance"))
            ?? distanceUnitFromHeading(heading("plannedDistance"))
            ?? inferDistanceUnitFromData(sheet, mapping.columns["actualDistance"], mapping)
            ?? inferDistanceUnitFromData(sheet, mapping.columns["plannedDistance"], mapping)
            ?? "km"
        mapping.units.paceIsTime = columnIsTimeFormatted(workbook, sheet, mapping.columns["avgPace"], mapping)

        let markers = detectDoneMarkers(workbook, mapping)
        mapping.doneValue = markers.done ?? "Yes"
        mapping.missedValue = markers.missed ?? "Missed"
        return mapping
    }

    static func cellText(_ sheet: Sheet, _ row: Int, _ col: Int?) -> String {
        guard let col else { return "" }
        return sheet.textAt(row, col)
    }

    static func cellNumber(_ sheet: Sheet, _ row: Int, _ col: Int?) -> Double? {
        guard let col else { return nil }
        return sheet.cell(row, col)?.number
    }

    private static let isoDate = Pattern("^(\\d{4})-(\\d{1,2})-(\\d{1,2})")
    private static let euroDate = Pattern("^(\\d{1,2})[./](\\d{1,2})[./](\\d{2,4})")

    static func readDate(_ sheet: Sheet, _ row: Int, _ col: Int?) -> Date? {
        guard let col, let cell = sheet.cell(row, col) else { return nil }
        if let date = cell.date { return date }
        let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if let m = isoDate.first(text), let y = Int(m[1]!), let mo = Int(m[2]!), let d = Int(m[3]!) {
            return utcDate(y, mo, d)
        }
        if let m = euroDate.first(text), let d = Int(m[1]!), let mo = Int(m[2]!), var y = Int(m[3]!) {
            if y < 100 { y += 2000 }
            return utcDate(y, mo, d)
        }
        return nil
    }

    /* Date.UTC rolls an impossible day over (31 Feb is 3 March); so does this. */
    static func utcDate(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        var c = DateComponents()
        c.year = y; c.month = 1; c.day = 1
        guard let start = utc.date(from: c),
              let months = utc.date(byAdding: .month, value: m - 1, to: start) else { return nil }
        return utc.date(byAdding: .day, value: d - 1, to: months)
    }

    static func sectionsFromRow(_ sheet: Sheet, _ row: Int, _ mapping: Mapping) -> [Section] {
        var sections: [Section] = []
        for id in sectionOrder {
            guard let col = mapping.columns[id] else { continue }
            let text = cellText(sheet, row, col)
            if !text.isEmpty { sections.append(Section(kind: id, label: sectionLabels[id]!, text: text)) }
        }
        if sections.isEmpty {
            let description = cellText(sheet, row, mapping.columns["description"])
            let text = description.isEmpty ? cellText(sheet, row, mapping.columns["title"]) : description
            if !text.isEmpty {
                let heading = mapping.columns["description"].map { sheet.textAt(mapping.headerRow, $0) } ?? ""
                sections.append(Section(kind: "main", label: heading.isEmpty ? sectionLabels["main"]! : heading, text: text))
            }
        }
        return sections
    }

    static func readResults(_ sheet: Sheet, _ row: Int, _ mapping: Mapping) -> [String: ResultValue] {
        var results: [String: ResultValue] = [:]
        for id in Fields.resultFields {
            guard let col = mapping.columns[id], let cell = sheet.cell(row, col) else { continue }
            let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { results[id] = ResultValue(text: text, number: cell.number, date: cell.date) }
        }
        return results
    }

    static func isLogged(_ results: [String: ResultValue]) -> Bool {
        ["actualDuration", "actualDistance", "avgHr", "done", "notes", "rpe"].contains { !(results[$0]?.text ?? "").isEmpty }
    }

    public static func build(_ workbook: Workbook, _ mapping: Mapping) -> [Workout] {
        var workouts: [Workout] = []

        for sheetName in mapping.sheets {
            guard let sheet = try? workbook.readSheet(sheetName) else { continue }
            let lastRow = max(findLastDataRow(sheet, mapping.firstDataRow, mapping.columns["date"]), mapping.firstDataRow)

            var carriedDate: Date?
            var groupIndex: Int?
            var groupKey: String?

            for row in mapping.firstDataRow...lastRow {
                let rowDate = readDate(sheet, row, mapping.columns["date"])
                if let rowDate { carriedDate = rowDate }
                let date = rowDate ?? carriedDate

                let disciplineRaw = cellText(sheet, row, mapping.columns["discipline"])
                let title = cellText(sheet, row, mapping.columns["title"])
                let anyContent = !disciplineRaw.isEmpty || !title.isEmpty
                    || sectionOrder.contains { !cellText(sheet, row, mapping.columns[$0]).isEmpty }
                    || !cellText(sheet, row, mapping.columns["description"]).isEmpty

                let needsDiscipline = mapping.mode != "section-rows"
                guard let date, anyContent, !(needsDiscipline && disciplineRaw.isEmpty) else {
                    if !anyContent { groupIndex = nil; groupKey = nil }
                    continue
                }

                if mapping.mode == "section-rows" {
                    let carriedRaw = disciplineRaw.isEmpty ? (groupIndex.map { workouts[$0].disciplineRaw } ?? "") : disciplineRaw
                    let key = (dayKey(date) ?? "") + "|" + normalise(carriedRaw)
                    if groupIndex == nil || groupKey != key {
                        workouts.append(Workout(
                            key: key, sheet: sheetName, row: row, rows: [], date: date, dayKey: dayKey(date) ?? "",
                            disciplineRaw: disciplineRaw, discipline: Disciplines.other, title: title,
                            phase: cellText(sheet, row, mapping.columns["phase"]), sections: [],
                            planned: Planned(durationRaw: nil, distanceRaw: nil, intensity: "", description: ""),
                            results: readResults(sheet, row, mapping), loggedInSheet: false, missed: false))
                        groupIndex = workouts.count - 1
                        groupKey = key
                    }
                    let g = groupIndex!
                    workouts[g].rows.append(row)
                    if workouts[g].disciplineRaw.isEmpty && !disciplineRaw.isEmpty { workouts[g].disciplineRaw = disciplineRaw }

                    let kind = classifySection(cellText(sheet, row, mapping.sectionColumn))
                    let descriptionText = cellText(sheet, row, mapping.columns["description"])
                    let text = descriptionText.isEmpty ? cellText(sheet, row, mapping.columns["title"]) : descriptionText
                    if !text.isEmpty {
                        let label = cellText(sheet, row, mapping.sectionColumn)
                        workouts[g].sections.append(Section(kind: kind, label: label.isEmpty ? sectionLabels[kind]! : label, text: text))
                    }
                    if let planned = cellNumber(sheet, row, mapping.columns["plannedDuration"]) {
                        workouts[g].planned.durationRaw = (workouts[g].planned.durationRaw ?? 0) + planned
                    }
                    continue
                }

                workouts.append(Workout(
                    key: sheetName + "!" + String(row), sheet: sheetName, row: row, rows: [row], date: date,
                    dayKey: dayKey(date) ?? "", disciplineRaw: disciplineRaw, discipline: Disciplines.other,
                    title: title, phase: cellText(sheet, row, mapping.columns["phase"]),
                    sections: sectionsFromRow(sheet, row, mapping),
                    planned: Planned(
                        durationRaw: cellNumber(sheet, row, mapping.columns["plannedDuration"]),
                        distanceRaw: cellNumber(sheet, row, mapping.columns["plannedDistance"]),
                        intensity: cellText(sheet, row, mapping.columns["plannedIntensity"]),
                        description: cellText(sheet, row, mapping.columns["description"])),
                    results: readResults(sheet, row, mapping), loggedInSheet: false, missed: false))
            }
        }

        let missedMarker = normalise(mapping.missedValue)
        for i in workouts.indices {
            workouts[i].discipline = Disciplines.classify(workouts[i].disciplineRaw)
            workouts[i].loggedInSheet = isLogged(workouts[i].results)
            if let done = workouts[i].results["done"] { workouts[i].missed = normalise(done.text) == missedMarker }
            let order = { (kind: String) -> Int in sectionOrder.firstIndex(of: kind) ?? 99 }
            workouts[i].sections = workouts[i].sections.enumerated()
                .sorted { order($0.element.kind) != order($1.element.kind) ? order($0.element.kind) < order($1.element.kind) : $0.offset < $1.offset }
                .map(\.element)
            if workouts[i].title.isEmpty {
                let first = workouts[i].sections.first.map { " — " + String($0.text.prefix(40)) } ?? ""
                workouts[i].title = workouts[i].discipline.label + first
            }
        }

        return workouts.enumerated().sorted {
            if $0.element.date != $1.element.date { return $0.element.date < $1.element.date }
            if $0.element.row != $1.element.row { return $0.element.row < $1.element.row }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    public static func plannedSeconds(_ workout: Workout, _ mapping: Mapping) -> Double? {
        durationFromCell(workout.planned.durationRaw, mapping.units.duration)
    }
}
