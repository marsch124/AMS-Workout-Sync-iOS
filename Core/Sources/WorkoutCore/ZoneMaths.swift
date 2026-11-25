import Foundation

/*
 * Tests and zones, once the plan lives in the app.
 *
 * In the workbook a test's three numbers went into a row, and Excel worked
 * the zone tables out from the last row that had a number in each column.
 * The same arithmetic lives here, with the plan's own percentages, so a test
 * entered in the app changes the zones the way entering it in Excel did —
 * and a zone only ever changes from a test.
 */
public struct TestResult: Codable, Equatable, Identifiable {
    public var id: String { name }
    /* "Test 2" */
    public var name: String
    /* "W9" */
    public var week: String
    /* "02 Nov–04 Nov 2026", as the plan writes it */
    public var dates: String
    public var lthr: Double?
    public var ftp: Double?
    /* Seconds per 100 m. */
    public var css: Double?
    public var weight: Double?
    public var notes: String

    public init(name: String, week: String = "", dates: String = "", lthr: Double? = nil, ftp: Double? = nil,
                css: Double? = nil, weight: Double? = nil, notes: String = "") {
        self.name = name; self.week = week; self.dates = dates
        self.lthr = lthr; self.ftp = ftp; self.css = css; self.weight = weight; self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        week = (try? c.decode(String.self, forKey: .week)) ?? ""
        dates = (try? c.decode(String.self, forKey: .dates)) ?? ""
        lthr = try? c.decodeIfPresent(Double.self, forKey: .lthr)
        ftp = try? c.decodeIfPresent(Double.self, forKey: .ftp)
        css = try? c.decodeIfPresent(Double.self, forKey: .css)
        weight = try? c.decodeIfPresent(Double.self, forKey: .weight)
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }

    public var hasNumbers: Bool { lthr != nil || ftp != nil || css != nil || weight != nil }
    public var label: String { dates.isEmpty ? name : name + ", " + dates }
}

public enum ZoneMaths {
    /* Excel's ROUND: halves away from zero. */
    static func whole(_ x: Double) -> String { jsNumberString(x.rounded(.toNearestOrAwayFromZero)) }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.toNearestOrAwayFromZero))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func longClock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.toNearestOrAwayFromZero))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func band(_ base: Double, _ low: Double, _ high: Double) -> String { whole(base * low) + "–" + whole(base * high) }

    /* A heart-rate row, by its zone number. Nil for a row this arithmetic does not know. */
    static func heart(_ label: String, _ lthr: Double) -> String? {
        switch Zones.zoneNumber(of: label) {
        case 1: return "< " + whole(lthr * 0.81)
        case 2: return band(lthr, 0.81, 0.89)
        case 3: return band(lthr, 0.90, 0.95)
        case 4: return band(lthr, 0.96, 1.02)
        case 5: return "> " + whole(lthr * 1.02)
        default: return nil
        }
    }

    static func bike(_ label: String, _ ftp: Double) -> String? {
        if label.contains("70.3") { return band(ftp, 0.75, 0.82) }
        switch Zones.zoneNumber(of: label) {
        case 1: return "< " + whole(ftp * 0.55)
        case 2: return band(ftp, 0.56, 0.75)
        case 3: return band(ftp, 0.76, 0.90)
        case 4: return band(ftp, 0.91, 1.05)
        default: return nil
        }
    }

    static func swim(_ label: String, _ css: Double) -> String? {
        let l = label.lowercased()
        if l.contains("projection") { return longClock((css + 4) * 19) + " (at 70.3 effort)" }
        if l.contains("70.3") { return clock(css + 3) + "–" + clock(css + 5) }
        if l.contains("endurance") { return clock(css + 5) + "–" + clock(css + 7) }
        if l.contains("speed") || l.contains("reps") { return clock(css - 2) + "–" + clock(css) }
        if l.contains("css") || l.contains("threshold") { return clock(css) }
        return nil
    }

    /* What counts now: for each number, the last test that has it — as the sheet's CURRENT row did. */
    public static func current(_ tests: [TestResult]) -> (lthr: Double?, ftp: Double?, css: Double?, weight: Double?, latest: TestResult?) {
        (tests.last { $0.lthr != nil }?.lthr, tests.last { $0.ftp != nil }?.ftp, tests.last { $0.css != nil }?.css,
         tests.last { $0.weight != nil }?.weight, tests.last { $0.hasNumbers })
    }
}

extension Zones {
    /*
     * The same tables, worked out afresh from the tests. A row the arithmetic
     * does not know keeps what it said; a number that is missing leaves its
     * table's rows empty, as the sheet's formulas did.
     */
    public func recalculated(from tests: [TestResult]) -> Zones {
        let now = ZoneMaths.current(tests)
        func value(_ label: String) -> String? {
            let l = label.uppercased()
            if l.contains("LTHR") { return now.lthr.map(jsNumberString) ?? "" }
            if l.contains("FTP") { return now.ftp.map(jsNumberString) ?? "" }
            if l.contains("CSS") { return now.css.map(jsNumberString) ?? "" }
            if l.contains("WEIGHT") { return now.weight.map(jsNumberString) ?? "" }
            return nil
        }
        let newCurrent = current.map { ZoneRow(label: $0.label, value: value($0.label) ?? $0.value) }
        let newTables = tables.map { table -> ZoneTable in
            ZoneTable(title: table.title, rows: table.rows.map { row in
                let worked: String?
                switch table.kind {
                case .heart: worked = now.lthr.map { ZoneMaths.heart(row.label, $0) } ?? ""
                case .bike: worked = now.ftp.map { ZoneMaths.bike(row.label, $0) } ?? ""
                case .swim: worked = now.css.map { ZoneMaths.swim(row.label, $0) } ?? ""
                }
                return ZoneRow(label: row.label, value: worked ?? row.value)
            })
        }
        return Zones(sheet: sheet, current: newCurrent, latestTest: now.latest?.label ?? latestTest,
                     tables: newTables, note: note, abbreviations: abbreviations)
    }
}

extension PlanImport {
    /* The test rows of the zones sheet, in order: the ones with numbers and the ones still to come. */
    public static func tests(_ workbook: Workbook) -> [TestResult] {
        guard let name = workbook.sheetNames.first(where: { $0.lowercased().contains("zone") }),
              let sheet = try? workbook.readSheet(name) else { return [] }
        let rows = sheet.rows.keys.sorted()
        func t(_ r: Int, _ c: Int?) -> String { c.map { sheet.textAt(r, $0) } ?? "" }
        func n(_ r: Int, _ c: Int?) -> Double? {
            guard let c, let cell = sheet.cell(r, c) else { return nil }
            if let number = cell.number { return number }
            let parsed = jsParseFloat(firstCommaToDot(cell.text))
            return parsed.isNaN ? nil : parsed
        }
        var header: Int?
        var labelCol = 1
        for r in rows {
            if let c = (sheet.rows[r] ?? [:]).keys.sorted().first(where: { sheet.textAt(r, $0).lowercased() == "test block" }) {
                header = r; labelCol = c; break
            }
        }
        guard let header else { return [] }
        func col(_ needle: String) -> Int? {
            (sheet.rows[header] ?? [:]).keys.sorted().first { sheet.textAt(header, $0).lowercased().contains(needle) }
        }
        let week = col("week"), dates = col("date"), lthr = col("lthr"), ftp = col("ftp"), css = col("css")
        let weight = col("weight"), notes = col("note")
        var out: [TestResult] = []
        for r in rows where r > header {
            let label = t(r, labelCol)
            if label.uppercased().hasPrefix("CURRENT") { break }
            guard label.lowercased().hasPrefix("test") else { continue }
            out.append(TestResult(name: label, week: t(r, week), dates: t(r, dates), lthr: n(r, lthr), ftp: n(r, ftp),
                                  css: n(r, css), weight: n(r, weight), notes: t(r, notes)))
        }
        return out
    }
}
