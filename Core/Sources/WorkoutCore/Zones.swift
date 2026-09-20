import Foundation

/*
 * The Test Results & Zones sheet, read for what a session's "Z2" or "Z4–Z5"
 * means for him this season: heart-rate zones from the latest LTHR, bike
 * power zones from FTP, swim paces from CSS. The cells are formulas; Excel's
 * last answers are what is read, and nothing is recalculated.
 *
 * The sheet is read by its shape rather than by fixed addresses — the row
 * that says "Test block" is the results table, the row whose first cell says
 * "CURRENT" carries the numbers in use, the row with "ZONES" in it heads the
 * tables, "ABBREVIATIONS" the glossary — so an inserted row or an extra
 * column does not quietly read the wrong number.
 */
public struct ZoneRow: Equatable, Codable {
    public let label: String
    public let value: String
    public init(label: String, value: String) { self.label = label; self.value = value }
}

public struct ZoneTable: Equatable, Codable {
    public enum Kind: String, Codable { case heart, bike, swim }

    public let title: String
    public let rows: [ZoneRow]
    public init(title: String, rows: [ZoneRow]) { self.title = title; self.rows = rows }

    public var kind: Kind {
        let t = title.uppercased()
        if t.contains("SWIM") { return .swim }
        if t.contains("POWER") || t.contains("BIKE") { return .bike }
        return .heart
    }

    /* The rows for the zones named: "Z2 — Aerobic" for 2. */
    public func rows(forZones zones: [Int]) -> [ZoneRow] {
        rows.filter { row in Zones.zoneNumber(of: row.label).map(zones.contains) ?? false }
    }
}

public struct Zones: Equatable, Codable {
    public let sheet: String
    /* LTHR, FTP, CSS and weight as the sheet labels them; an empty value is not entered yet. */
    public let current: [ZoneRow]
    /* "Test 1 (baseline), 14 Sep–16 Sep 2026" — the latest test with a number in it. */
    public let latestTest: String
    public let tables: [ZoneTable]
    public let note: String
    public let abbreviations: [ZoneRow]

    public var rpe: String? { abbreviations.first { $0.label.uppercased() == "RPE" }?.value }

    /* The zone tables are formulas. Empty means Excel has not worked them out
       since the file was last written — not that nothing was ever entered. */
    public var waitingForExcel: Bool {
        !tables.isEmpty && tables.allSatisfy { t in t.rows.allSatisfy { $0.value.isEmpty } }
    }

    /* "Z2 — Aerobic" → 2. Only a Z straight followed by one digit counts. */
    public static func zoneNumber(of label: String) -> Int? {
        let chars = Array(label.trimmingCharacters(in: .whitespaces))
        guard chars.count >= 2, chars[0] == "Z" || chars[0] == "z", let n = chars[1].wholeNumberValue, (1...9).contains(n) else { return nil }
        if chars.count > 2, chars[2].isNumber { return nil }
        return n
    }

    /* "Z4–Z5" → 4 and 5; "Z1–Z2" → 1 and 2; "Z2 + strides" → 2; "RPE 6" → nothing. */
    public static func zones(in intensity: String) -> [Int] {
        let chars = Array(intensity)
        var found: [Int] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "Z" || chars[i] == "z", i + 1 < chars.count, let n = chars[i + 1].wholeNumberValue, (1...9).contains(n),
               i + 2 >= chars.count || !chars[i + 2].isNumber,
               i == 0 || !chars[i - 1].isLetter {
                found.append(n)
                i += 2
                continue
            }
            i += 1
        }
        guard let lo = found.min(), let hi = found.max() else { return [] }
        return found.count >= 2 ? Array(lo...hi) : [lo]
    }

    /*
     * The tables cut down to what the intensity names, for the sport in hand:
     * the heart-rate rows always, bike power only on a ride, and on a swim the
     * whole pace table, which has no Z rows of its own. A row Excel has not
     * worked out yet (no FTP entered) is left out rather than shown blank.
     */
    public func explain(intensity: String, sport: String) -> [ZoneTable] {
        let zs = Self.zones(in: intensity)
        var out: [ZoneTable] = []
        for table in tables {
            let rows: [ZoneRow]
            switch table.kind {
            case .heart: rows = table.rows(forZones: zs)
            case .bike: rows = sport == "bike" || sport == "brick" ? table.rows(forZones: zs) : []
            case .swim: rows = sport == "swim" ? table.rows : []
            }
            let known = rows.filter { !$0.value.isEmpty }
            if !known.isEmpty { out.append(ZoneTable(title: table.title, rows: known)) }
        }
        return out
    }

    public static func read(_ workbook: Workbook) -> Zones? {
        guard let name = workbook.sheetNames.first(where: { $0.lowercased().contains("zone") }),
              let sheet = try? workbook.readSheet(name) else { return nil }
        func t(_ r: Int, _ c: Int) -> String { sheet.textAt(r, c).trimmingCharacters(in: .whitespacesAndNewlines) }
        func cells(_ r: Int) -> [(col: Int, text: String)] {
            (sheet.rows[r] ?? [:]).keys.sorted().compactMap { c in
                let s = t(r, c)
                return s.isEmpty ? nil : (c, s)
            }
        }
        let rowNumbers = sheet.rows.keys.sorted()

        // The results table: its heading row, and the columns by what they say.
        guard let headerRow = rowNumbers.first(where: { r in cells(r).contains { $0.text.lowercased() == "test block" } }),
              let labelCol = cells(headerRow).first(where: { $0.text.lowercased() == "test block" })?.col else { return nil }
        let header = cells(headerRow)
        func col(_ needle: String) -> Int? { header.first { $0.text.lowercased().contains(needle) }?.col }
        let valueCols = [col("lthr"), col("ftp"), col("css"), col("weight")].compactMap { $0 }
        let datesCol = col("date")

        var currentRow: Int?
        var latestTestRow: Int?
        for r in rowNumbers where r > headerRow {
            let a = t(r, labelCol)
            if a.uppercased().hasPrefix("CURRENT") { currentRow = r; break }
            if a.lowercased().hasPrefix("test"), valueCols.contains(where: { !t(r, $0).isEmpty }) { latestTestRow = r }
        }
        var current: [ZoneRow] = []
        if let cr = currentRow {
            for h in header where valueCols.contains(h.col) { current.append(ZoneRow(label: h.text, value: t(cr, h.col))) }
        }
        // The CURRENT row is a formula picking the last test with a number in it.
        // When its answer is missing, that test's own cells still hold the numbers.
        if current.allSatisfy({ $0.value.isEmpty }), let lr = latestTestRow {
            current = header.filter { valueCols.contains($0.col) }.map { ZoneRow(label: $0.text, value: t(lr, $0.col)) }
        }
        var latest = ""
        if let lr = latestTestRow {
            latest = t(lr, labelCol)
            if let dc = datesCol, !t(lr, dc).isEmpty { latest += ", " + t(lr, dc) }
        }

        // The zone tables: one heading row, a table under each heading on it.
        let after = currentRow ?? headerRow
        var tables: [ZoneTable] = []
        var tablesEnd = after
        if let titleRow = rowNumbers.first(where: { r in r > after && t(r, labelCol).uppercased().contains("ZONE") }) {
            for title in cells(titleRow) {
                var rows: [ZoneRow] = []
                var r = titleRow + 1
                while r <= sheet.maxRow, !t(r, title.col).isEmpty {
                    rows.append(ZoneRow(label: t(r, title.col), value: t(r, title.col + 1)))
                    r += 1
                }
                tablesEnd = max(tablesEnd, r)
                if !rows.isEmpty { tables.append(ZoneTable(title: title.text, rows: rows)) }
            }
        }
        guard !tables.isEmpty else { return nil }

        let note = rowNumbers.first(where: { r in r >= tablesEnd && t(r, labelCol).lowercased().hasPrefix("note") })
            .map { t($0, labelCol) } ?? ""

        var abbreviations: [ZoneRow] = []
        if let ar = rowNumbers.first(where: { r in r > after && t(r, labelCol).uppercased() == "ABBREVIATIONS" }) {
            var r = ar + 1
            while r <= sheet.maxRow, !t(r, labelCol).isEmpty, !t(r, labelCol + 1).isEmpty {
                abbreviations.append(ZoneRow(label: t(r, labelCol), value: t(r, labelCol + 1)))
                r += 1
            }
        }
        return Zones(sheet: name, current: current, latestTest: latest, tables: tables, note: note, abbreviations: abbreviations)
    }
}
