import Foundation

/*
 * Working out what the spreadsheet means: which row is the header, which
 * column is which, whether sections run across columns or down rows.
 *
 * A port of js/mapping.js. Detection only — the web app's Sheet setup screen,
 * where a guess is corrected by hand, is not part of the read-only preview.
 * A plan the web app reads correctly by detection is read the same way here,
 * and tools/parity.sh is what says so.
 */

public struct Field {
    public let id: String
    public let label: String
    public let group: String
    public let write: Bool
    public let synonyms: [String]
}

public enum Fields {
    public static let all: [Field] = [
        Field(id: "date", label: "Date", group: "plan", write: false,
              synonyms: ["date", "datum", "day", "tag", "when", "workout date", "trainingstag"]),
        Field(id: "phase", label: "Phase or block", group: "plan", write: false,
              synonyms: ["phase", "block", "period", "mesocycle", "trainingsphase", "zyklus", "makrozyklus", "stage"]),
        Field(id: "weekday", label: "Weekday", group: "plan", write: false,
              synonyms: ["day", "weekday", "tag", "wochentag", "week day"]),
        Field(id: "discipline", label: "Discipline", group: "plan", write: false,
              synonyms: ["discipline", "sport", "sportart", "activity", "aktivitat", "type", "art",
                         "workout type", "trainingsart", "disziplin"]),
        Field(id: "title", label: "Session name", group: "plan", write: false,
              synonyms: ["session", "workout", "title", "name", "einheit", "training", "session name",
                         "übung", "ubung", "beschreibung kurz"]),
        Field(id: "plannedDuration", label: "Planned duration", group: "plan", write: false,
              synonyms: ["planned duration", "plan duration", "duration plan", "target duration",
                         "soll dauer", "geplante dauer", "dauer plan", "planzeit", "target time",
                         "duration", "dauer", "zeit", "time"]),
        Field(id: "plannedDistance", label: "Planned distance", group: "plan", write: false,
              synonyms: ["planned distance", "plan distance", "target distance", "soll distanz",
                         "geplante distanz", "distance", "distanz", "strecke", "km", "meter"]),
        Field(id: "description", label: "Description", group: "plan", write: false,
              synonyms: ["description", "details", "detail", "beschreibung", "inhalt", "content",
                         "ubung", "vorgabe", "aufgabe", "programm", "purpose", "zweck", "focus"]),
        Field(id: "plannedIntensity", label: "Planned intensity", group: "plan", write: false,
              synonyms: ["intensity", "intensitat", "zone", "target zone", "zielzone",
                         "belastung", "target hr", "ziel puls", "target", "ziel", "pace target"]),

        Field(id: "warmup", label: "Warm-up", group: "section", write: false,
              synonyms: ["warm up", "warmup", "warm-up", "aufwarmen", "aufwarmung", "einlaufen",
                         "einschwimmen", "einrollen", "warming up"]),
        Field(id: "intervals", label: "Intervals / main set", group: "section", write: false,
              synonyms: ["intervals", "interval", "intervalle", "main set", "mainset", "main",
                         "hauptteil", "hauptsatz", "set", "sets", "belastung", "kernsatz", "body"]),
        Field(id: "cooldown", label: "Cool-down", group: "section", write: false,
              synonyms: ["cool down", "cooldown", "cool-down", "abwarmen", "auslaufen",
                         "ausschwimmen", "ausrollen", "abkuhlen"]),
        Field(id: "technique", label: "Technique", group: "section", write: false,
              synonyms: ["technique", "technik", "drills", "drill", "form", "technikubungen",
                         "skills", "koordination"]),
        Field(id: "sectionLabel", label: "Section (one row each)", group: "section", write: false,
              synonyms: ["section", "abschnitt", "teil", "part"]),

        Field(id: "actualDuration", label: "Duration", group: "result", write: true,
              synonyms: ["actual duration", "duration actual", "ist dauer", "dauer ist",
                         "real duration", "tatsachliche dauer", "actual time", "ist zeit", "gesamtzeit",
                         "moving time", "elapsed time",
                         "actual min", "actual mins", "actual minutes", "actual h", "actual hours",
                         "actual hrs", "ist min", "ist minuten"]),
        Field(id: "actualDistance", label: "Distance", group: "result", write: true,
              synonyms: ["actual distance", "ist distanz", "distanz ist", "gelaufen",
                         "real distance", "tatsachliche distanz", "actual km"]),
        Field(id: "avgHr", label: "Average heart rate", group: "result", write: true,
              synonyms: ["avg hr", "average hr", "avg heart rate", "average heart rate",
                         "hr", "heart rate", "puls", "herzfrequenz", "durchschnittspuls", "hf",
                         "mittlere hf", "ø puls"]),
        Field(id: "maxHr", label: "Max heart rate", group: "result", write: true,
              synonyms: ["max hr", "maximum hr", "max heart rate", "maxpuls", "max puls",
                         "maximalpuls", "hf max", "max hf"]),
        Field(id: "avgPace", label: "Pace", group: "result", write: true,
              synonyms: ["pace", "avg pace", "average pace", "tempo", "schnitt",
                         "min/km", "pace /100m", "pace per km"]),
        Field(id: "avgSpeed", label: "Speed", group: "result", write: true,
              synonyms: ["speed", "avg speed", "average speed", "geschwindigkeit",
                         "km/h", "schnitt kmh", "ø geschwindigkeit"]),
        Field(id: "avgPower", label: "Power", group: "result", write: true,
              synonyms: ["power", "avg power", "average power", "watt", "watts",
                         "leistung", "np", "normalized power"]),
        Field(id: "cadence", label: "Cadence", group: "result", write: true,
              synonyms: ["cadence", "kadenz", "trittfrequenz", "schrittfrequenz", "rpm", "spm"]),
        Field(id: "elevation", label: "Elevation gain", group: "result", write: true,
              synonyms: ["elevation", "elevation gain", "ascent", "hohenmeter", "hm", "anstieg", "climb"]),
        Field(id: "calories", label: "Calories", group: "result", write: true,
              synonyms: ["calories", "kalorien", "kcal", "energy", "energie"]),
        Field(id: "rpe", label: "Perceived effort (RPE)", group: "result", write: true,
              synonyms: ["rpe", "perceived effort", "effort", "anstrengung", "borg",
                         "empfinden", "gefuhl", "feeling"]),
        Field(id: "notes", label: "Notes", group: "result", write: true,
              synonyms: ["notes", "note", "notizen", "notiz", "comment", "comments", "kommentar",
                         "bemerkung", "bemerkungen", "remarks"]),
        Field(id: "done", label: "Completed", group: "result", write: true,
              synonyms: ["done", "completed", "complete", "erledigt", "fertig", "status", "abgehakt",
                         "absolviert", "ok"]),
        Field(id: "completedAt", label: "Logged on", group: "result", write: true,
              synonyms: ["logged", "logged on", "completed on", "completed date", "erfasst",
                         "eingetragen", "log date"])
    ]

    public static let byId: [String: Field] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    public static let sectionFields = ["warmup", "intervals", "cooldown", "technique"]
    public static let resultFields = all.filter(\.write).map(\.id)

    /* Synonyms normalised once; the JS normalises inside every loop. */
    static let normalisedSynonyms: [String: [String]] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.synonyms.map(normalise)) })
}

private let nonWord = Pattern("[^a-z0-9/]+")
private let spaces = Pattern("\\s+")

/* Fold a heading down to something comparable: lower case, umlauts and
   accents flattened, punctuation dropped, whitespace collapsed. */
public func normalise(_ text: String?) -> String {
    var s = (text ?? "").lowercased()
        .replacingOccurrences(of: "ä", with: "a").replacingOccurrences(of: "ö", with: "o")
        .replacingOccurrences(of: "ü", with: "u").replacingOccurrences(of: "ß", with: "ss")
    s = String(String.UnicodeScalarView(s.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
        !(0x300...0x36f).contains($0.value)
    }))
    s = nonWord.replace(s, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return spaces.replace(s, with: " ")
}

func scoreHeading(_ heading: String, _ fieldId: String) -> Int {
    let h = normalise(heading)
    if h.isEmpty { return 0 }
    var best = 0
    for s in Fields.normalisedSynonyms[fieldId] ?? [] where !s.isEmpty {
        if h == s {
            best = max(best, 1000 + s.count * 10)
        } else if h.hasPrefix(s + " ") || h.hasSuffix(" " + s) {
            best = max(best, 400 + s.count * 10)
        } else if h.contains(s) {
            best = max(best, 200 + s.count * 10)
        }
    }
    return best
}

struct HeadingCell { let col: Int; let text: String }

func readRow(_ sheet: Sheet, _ rowNum: Int) -> [HeadingCell] {
    guard let row = sheet.rows[rowNum] else { return [] }
    return row.compactMap { col, cell -> HeadingCell? in
        let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : HeadingCell(col: col, text: text)
    }.sorted { $0.col < $1.col }
}

struct ScoredHeader {
    let rowNum: Int
    var total: Int
    var claims: [String: Int]   // field id -> column
}

func scoreHeaderRow(_ sheet: Sheet, _ rowNum: Int) -> ScoredHeader? {
    let cells = readRow(sheet, rowNum)
    if cells.count < 2 { return nil }
    if let row = sheet.rows[rowNum], row.values.contains(where: { $0.date != nil }) { return nil }

    struct Pair { let col: Int; let fieldId: String; let score: Int; let order: Int }
    var pairs: [Pair] = []
    for cell in cells {
        for field in Fields.all {
            let score = scoreHeading(cell.text, field.id)
            if score > 0 { pairs.append(Pair(col: cell.col, fieldId: field.id, score: score, order: pairs.count)) }
        }
    }
    // Stable, as Array.prototype.sort is: ties keep the order they were met in.
    pairs.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }

    var claims: [String: Int] = [:]
    var taken = Set<Int>()
    var total = 0
    for pair in pairs {
        if claims[pair.fieldId] != nil || taken.contains(pair.col) { continue }
        claims[pair.fieldId] = pair.col
        taken.insert(pair.col)
        total += pair.score
    }
    if claims.isEmpty { return nil }
    if claims["date"] == nil && claims["discipline"] == nil { total = total / 4 }
    return ScoredHeader(rowNum: rowNum, total: total, claims: claims)
}

func signatureOf(_ sheet: Sheet, _ headerRow: Int) -> String {
    readRow(sheet, headerRow).map { normalise($0.text) }.joined(separator: "|")
}

func looksLikeSectionColumn(_ sheet: Sheet, _ col: Int, _ firstDataRow: Int) -> Bool {
    let synonyms = Fields.sectionFields.flatMap { Fields.normalisedSynonyms[$0] ?? [] }
    var seen = 0
    var matched = 0
    let last = min(sheet.maxRow, firstDataRow + 120)
    if firstDataRow <= last {
        for r in firstDataRow...last {
            let text = normalise(sheet.textAt(r, col))
            if text.isEmpty { continue }
            seen += 1
            if synonyms.contains(where: { !$0.isEmpty && (text == $0 || text.contains($0)) }) { matched += 1 }
        }
    }
    return seen >= 3 && Double(matched) >= max(3, Double(seen) * 0.4)
}

public func findLastDataRow(_ sheet: Sheet, _ firstDataRow: Int, _ dateCol: Int?) -> Int {
    var last = firstDataRow - 1
    var blanks = 0
    var r = firstDataRow
    while r <= sheet.maxRow + 5 {
        let row = sheet.rows[r]
        let hasAnything = row?.values.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        if hasAnything {
            last = r
            blanks = 0
        } else {
            blanks += 1
            if blanks >= 12 { break }
        }
        r += 1
    }
    return last
}

public struct Units: Codable, Equatable {
    public var duration: String      // hours | minutes | time
    public var distance: String      // km | m
    public var paceIsTime: Bool
}

public struct Mapping: Codable, Equatable {
    public var sheets: [String]
    public var headerRow: Int
    public var firstDataRow: Int
    public var lastDataRow: Int
    public var mode: String
    public var sectionColumn: Int?
    public var columns: [String: Int]
    public var units: Units
    public var doneValue: String
    public var missedValue: String

    public func column(_ id: String) -> Int? { columns[id] }
}

/*
 * Look at every sheet and return the best guess, or nil if nothing in the
 * workbook looks like a training plan. Units and the done/missed markers are
 * filled in afterwards by Plan.prepare, as the web app's prepareMapping does.
 */
public func autoDetect(_ workbook: Workbook) throws -> Mapping? {
    var best: (sheetName: String, sheet: Sheet, scored: ScoredHeader)?

    for meta in workbook.sheets where !meta.hidden {
        guard let sheet = try? workbook.readSheet(meta.name) else { continue }
        let limit = min(sheet.maxRow, 40)
        guard limit >= 1 else { continue }
        for r in 1...limit {
            guard let scored = scoreHeaderRow(sheet, r) else { continue }
            if best == nil || scored.total > best!.scored.total {
                best = (meta.name, sheet, scored)
            }
        }
    }

    guard var found = best else { return nil }
    var columns = found.scored.claims
    let headerRow = found.scored.rowNum
    let firstDataRow = headerRow + 1

    if let col = columns["sectionLabel"], !looksLikeSectionColumn(found.sheet, col, firstDataRow) {
        columns["sectionLabel"] = nil
        found.scored.claims["sectionLabel"] = nil
    }

    let mode: String
    if columns["sectionLabel"] != nil { mode = "section-rows" }
    else if Fields.sectionFields.contains(where: { columns[$0] != nil }) { mode = "section-columns" }
    else { mode = "simple" }

    let signature = signatureOf(found.sheet, headerRow)
    var sheets = [found.sheetName]
    for meta in workbook.sheets where meta.name != found.sheetName && !meta.hidden {
        if let other = try? workbook.readSheet(meta.name), signatureOf(other, headerRow) == signature {
            sheets.append(meta.name)
        }
    }

    return Mapping(
        sheets: sheets,
        headerRow: headerRow,
        firstDataRow: firstDataRow,
        lastDataRow: findLastDataRow(found.sheet, firstDataRow, columns["date"]),
        mode: mode,
        sectionColumn: columns["sectionLabel"],
        columns: columns,
        units: Units(duration: "hours", distance: "km", paceIsTime: false),
        doneValue: "Yes",
        missedValue: "Missed")
}
