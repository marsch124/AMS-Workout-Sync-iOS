import Foundation

/*
 * Reading an .xlsx: shared strings, styles (so a date is told from the number
 * 45000), and a sheet's cells.
 *
 * A port of js/xlsx.js in the web app, deliberately close to it line for line.
 * Where the two could differ — how a number becomes text, which styles count
 * as dates — they must not, because the plan built from these cells is
 * compared against the web app's by tools/parity.sh, and any drift here shows
 * up there as a session read differently.
 */

let builtinDateFormats: Set<Int> = [14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]
let days1904Offset = 1462.0

// MARK: - references

public func colToIndex(_ letters: String) -> Int {
    var n = 0
    for scalar in letters.uppercased().unicodeScalars {
        n = n * 26 + Int(scalar.value) - 64
    }
    return n
}

public func indexToCol(_ index: Int) -> String {
    var s = ""
    var n = index
    while n > 0 {
        let rem = (n - 1) % 26
        s = String(UnicodeScalar(UInt8(65 + rem))) + s
        n = (n - 1) / 26
    }
    return s
}

func parseRef(_ ref: String) -> (col: Int, row: Int)? {
    var letters = ""
    var digits = ""
    for ch in ref.trimmingCharacters(in: .whitespaces) {
        if ch.isLetter, digits.isEmpty, ch.isASCII { letters.append(ch) }
        else if ch.isNumber, ch.isASCII, !letters.isEmpty { digits.append(ch) }
        else { return nil }
    }
    guard !letters.isEmpty, let row = Int(digits) else { return nil }
    return (colToIndex(letters), row)
}

// MARK: - regex helpers

final class Pattern {
    let regex: NSRegularExpression
    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func matches(_ text: String) -> [[String?]] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
        }
    }

    func first(_ text: String) -> [String?]? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    func test(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    func replace(_ text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                       withTemplate: template)
    }
}

// MARK: - xml helpers

private let hexEntity = Pattern("&#x([0-9a-fA-F]+);")
private let decEntity = Pattern("&#(\\d+);")

func unescapeXml(_ text: String) -> String {
    guard text.contains("&") else { return text }
    var s = text
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
    for (pattern, radix) in [(hexEntity, 16), (decEntity, 10)] {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in pattern.regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let digits = ns.substring(with: m.range(at: 1))
            if let code = UInt32(digits, radix: radix), let scalar = UnicodeScalar(code) {
                out.unicodeScalars.append(scalar)
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        s = out
    }
    return s.replacingOccurrences(of: "&amp;", with: "&")
}

func attr(_ attrs: String, _ name: String) -> String? {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    return Pattern("\\s" + escaped + "=\"([^\"]*)\"").first(" " + attrs)?[1]
}

private let textRun = Pattern("<t(?:\\s[^>]*)?>([\\s\\S]*?)</t>|<t\\s*/>")

/* Concatenate every <t> in a fragment — rich text is split across runs. */
func joinText(_ fragment: String) -> String {
    textRun.matches(fragment).map { unescapeXml($0[1] ?? "") }.joined()
}

/*
 * How a number becomes text, the way JavaScript's String(number) does it —
 * "40", not "40.0". Swift's own description already gives the shortest
 * round-tripping digits, which is what JavaScript prints too; only the
 * trailing ".0" and the exponent style differ.
 */
public func jsNumberString(_ n: Double) -> String {
    if n.isNaN { return "NaN" }
    if n == 0 { return "0" }
    if n.isInfinite { return n < 0 ? "-Infinity" : "Infinity" }
    if n < 0 { return "-" + jsNumberString(-n) }

    // Swift's description is the shortest digit string that round-trips, the
    // same digits ECMAScript's Number::toString chooses; only the layout
    // differs. Take the digits and the exponent out of it, then lay them out
    // the way the spec does.
    let d = n.description.lowercased()
    var mantissa = d
    var exp = 0
    if let e = d.firstIndex(of: "e") {
        mantissa = String(d[d.startIndex..<e])
        exp = Int(d[d.index(after: e)...]) ?? 0
    }
    var intPart = mantissa
    var fracPart = ""
    if let dot = mantissa.firstIndex(of: ".") {
        intPart = String(mantissa[mantissa.startIndex..<dot])
        fracPart = String(mantissa[mantissa.index(after: dot)...])
    }
    var digits = intPart + fracPart
    var point = intPart.count + exp             // decimal point position within digits
    while digits.hasPrefix("0") && digits.count > 1 { digits.removeFirst(); point -= 1 }
    while digits.hasSuffix("0") && digits.count > 1 { digits.removeLast() }

    let k = digits.count
    let e10 = point                             // value = 0.digits × 10^e10  →  spec's n
    if k <= e10 && e10 <= 21 {
        return digits + String(repeating: "0", count: e10 - k)
    }
    if 0 < e10 && e10 <= 21 {
        let i = digits.index(digits.startIndex, offsetBy: e10)
        return String(digits[..<i]) + "." + String(digits[i...])
    }
    if -6 < e10 && e10 <= 0 {
        return "0." + String(repeating: "0", count: -e10) + digits
    }
    let shown = e10 - 1
    let sign = shown < 0 ? "-" : "+"
    let head = String(digits.prefix(1))
    let tail = String(digits.dropFirst())
    return head + (tail.isEmpty ? "" : "." + tail) + "e" + sign + String(abs(shown))
}

// MARK: - dates

private let quoted = Pattern("\"[^\"]*\"")
private let bracketed = Pattern("\\[[^\\]]*\\]")
private let backslashed = Pattern("\\\\.")
private let dateTokens = Pattern("[ymdhs]", [.caseInsensitive])

func isDateFormatCode(_ code: String?) -> Bool {
    guard let code, !code.isEmpty else { return false }
    let stripped = backslashed.replace(bracketed.replace(quoted.replace(code, with: ""), with: ""), with: "")
    return dateTokens.test(stripped)
}

public let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func serialToDate(_ serial: Double, _ date1904: Bool) -> Date {
    let n = date1904 ? serial + days1904Offset : serial
    let ms = ((n - 25569) * 86_400_000).rounded()
    return Date(timeIntervalSince1970: ms / 1000)
}

/* A date-only key (YYYY-MM-DD) read in UTC, so a workbook opened in one
   timezone never slides a workout onto the day before. */
public func dayKey(_ date: Date?) -> String? {
    guard let date else { return nil }
    let c = utc.dateComponents([.year, .month, .day], from: date)
    guard let y = c.year, let m = c.month, let d = c.day else { return nil }
    return String(format: "%04d-%02d-%02d", y, m, d)
}

public func parseDayKey(_ key: String?) -> Date? {
    guard let key, let m = Pattern("^(\\d{4})-(\\d{2})-(\\d{2})$").first(key.trimmingCharacters(in: .whitespaces)),
          let y = Int(m[1]!), let mo = Int(m[2]!), let d = Int(m[3]!) else { return nil }
    return utc.date(from: DateComponents(year: y, month: mo, day: d))
}

// MARK: - cells and sheets

public struct Cell {
    public let row: Int
    public let col: Int
    public let styleIndex: Int
    public let hasFormula: Bool
    public let formula: String
    public let type: String
    public var text: String
    public var number: Double?
    public var date: Date?
}

public final class Sheet {
    public let name: String
    public let rows: [Int: [Int: Cell]]
    public let maxRow: Int
    public let maxCol: Int

    init(name: String, rows: [Int: [Int: Cell]], maxRow: Int, maxCol: Int) {
        self.name = name
        self.rows = rows
        self.maxRow = maxRow
        self.maxCol = maxCol
    }

    public func cell(_ row: Int, _ col: Int) -> Cell? { rows[row]?[col] }

    public func textAt(_ row: Int, _ col: Int) -> String {
        (cell(row, col)?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SheetMeta {
    public let name: String
    public let path: String
    public let hidden: Bool
}

// MARK: - workbook

public final class Workbook {
    public enum WorkbookError: Error, LocalizedError {
        case notAWorkbook, noSheets, noSheet(String)
        public var errorDescription: String? {
            switch self {
            case .notAWorkbook: return "This file is not a workbook — xl/workbook.xml is missing."
            case .noSheets: return "This workbook has no readable sheets."
            case .noSheet(let name): return "No sheet named \"\(name)\" in this workbook."
            }
        }
    }

    public let archive: Archive
    public internal(set) var sheets: [SheetMeta] = []
    public private(set) var sharedStrings: [String] = []
    public private(set) var dateStyles: Set<Int> = []
    public private(set) var date1904 = false
    var cache: [String: Sheet] = [:]
    public internal(set) var dirtySheets = Set<String>()
    public internal(set) var formulaDropped = false

    public init(data: Data) throws {
        archive = try Archive(data: data)
        try loadWorkbook()
        try loadSharedStrings()
        try loadStyles()
    }

    private func loadWorkbook() throws {
        guard let xml = try archive.text("xl/workbook.xml") else { throw WorkbookError.notAWorkbook }
        date1904 = Pattern("date1904=\"(1|true)\"").test(xml)

        let relsXml = try archive.text("xl/_rels/workbook.xml.rels") ?? ""
        var rels: [String: String] = [:]
        for m in Pattern("<Relationship\\s([^>]*)/?>").matches(relsXml) {
            let attrs = m[1] ?? ""
            guard let id = attr(attrs, "Id"), var target = attr(attrs, "Target") else { continue }
            if target.hasPrefix("/xl/") { target.removeFirst(4) }
            if target.hasPrefix("./") { target.removeFirst(2) }
            rels[id] = target.hasPrefix("xl/") ? target : "xl/" + target
        }

        for m in Pattern("<sheet\\s([^>]*)/?>").matches(xml) {
            let attrs = m[1] ?? ""
            let name = unescapeXml(attr(attrs, "name") ?? "")
            let rid = attr(attrs, "r:id") ?? attr(attrs, "relationshipId")
            let state = attr(attrs, "state")
            if !name.isEmpty, let rid, let path = rels[rid] {
                sheets.append(SheetMeta(name: name, path: path, hidden: state == "hidden" || state == "veryHidden"))
            }
        }
        if sheets.isEmpty { throw WorkbookError.noSheets }
    }

    private func loadSharedStrings() throws {
        guard let xml = try archive.text("xl/sharedStrings.xml") else { return }
        for m in Pattern("<si>([\\s\\S]*?)</si>|<si\\s*/>").matches(xml) {
            sharedStrings.append(m[1].map(joinText) ?? "")
        }
    }

    private func loadStyles() throws {
        guard let xml = try archive.text("xl/styles.xml") else { return }

        var custom: [Int: String] = [:]
        for m in Pattern("<numFmt\\s([^>]*)/?>").matches(xml) {
            let attrs = m[1] ?? ""
            if let id = Int(attr(attrs, "numFmtId") ?? "") {
                custom[id] = unescapeXml(attr(attrs, "formatCode") ?? "")
            }
        }

        // Only <cellXfs> maps a cell's s="" index; <cellStyleXfs> is a
        // different table and must not be counted.
        guard let start = xml.range(of: "<cellXfs") else { return }
        let end = xml.range(of: "</cellXfs>", range: start.upperBound..<xml.endIndex)
        let block = String(xml[start.lowerBound..<(end?.lowerBound ?? xml.endIndex)])

        var index = 0
        for m in Pattern("<xf\\s([^>]*?)/?>").matches(block) {
            let numFmtId = Int(attr(m[1] ?? "", "numFmtId") ?? "0") ?? 0
            if builtinDateFormats.contains(numFmtId) || isDateFormatCode(custom[numFmtId]) {
                dateStyles.insert(index)
            }
            index += 1
        }
    }

    public var sheetNames: [String] { sheets.map(\.name) }

    public func findSheet(_ name: String) -> SheetMeta? { sheets.first { $0.name == name } }

    public func readSheet(_ name: String) throws -> Sheet {
        if let cached = cache[name] { return cached }
        guard let meta = findSheet(name) else { throw WorkbookError.noSheet(name) }
        guard let xml = try archive.text(meta.path) else { throw WorkbookError.noSheet(name) }
        let sheet = parseSheet(name, xml)
        cache[name] = sheet
        return sheet
    }

    private static let cellOpen = Pattern("<c\\s([^>]*?)(/?)>")
    private static let formulaText = Pattern("<f(?:\\s[^>]*)?>([\\s\\S]*?)</f>")
    private static let valueText = Pattern("<v(?:\\s[^>]*)?>([\\s\\S]*?)</v>")

    func parseSheet(_ name: String, _ xml: String) -> Sheet {
        let ns = xml as NSString
        let bodyStart = ns.range(of: "<sheetData")
        guard bodyStart.location != NSNotFound else { return Sheet(name: name, rows: [:], maxRow: 0, maxCol: 0) }
        let bodyEndRange = ns.range(of: "</sheetData>")
        let bodyEnd = bodyEndRange.location == NSNotFound ? ns.length : bodyEndRange.location
        let body = ns.substring(with: NSRange(location: bodyStart.location, length: bodyEnd - bodyStart.location)) as NSString
        let bodyString = body as String

        var rows: [Int: [Int: Cell]] = [:]
        var maxRow = 0
        var maxCol = 0
        var searchFrom = 0

        while searchFrom < body.length,
              let m = Self.cellOpen.regex.firstMatch(in: bodyString,
                                                     range: NSRange(location: searchFrom, length: body.length - searchFrom)) {
            let attrs = body.substring(with: m.range(at: 1))
            let selfClosing = body.substring(with: m.range(at: 2)) == "/"
            var content = ""
            searchFrom = m.range.location + m.range.length
            if !selfClosing {
                let close = body.range(of: "</c>", range: NSRange(location: searchFrom, length: body.length - searchFrom))
                if close.location == NSNotFound { break }
                content = body.substring(with: NSRange(location: searchFrom, length: close.location - searchFrom))
                searchFrom = close.location + 4
            }

            guard let ref = attr(attrs, "r"), let pos = parseRef(ref) else { continue }
            let styleIndex = Int(attr(attrs, "s") ?? "-1") ?? -1
            let type = attr(attrs, "t") ?? "n"
            let hasFormula = content.contains("<f")
            let formula = hasFormula ? unescapeXml(Self.formulaText.first(content)?[1] ?? "") : ""
            let rawValue = unescapeXml(Self.valueText.first(content)?[1] ?? "")

            var cell = Cell(row: pos.row, col: pos.col, styleIndex: styleIndex, hasFormula: hasFormula,
                            formula: formula, type: type, text: "", number: nil, date: nil)

            switch type {
            case "s":
                if let idx = Int(rawValue), idx >= 0, idx < sharedStrings.count { cell.text = sharedStrings[idx] }
            case "inlineStr":
                cell.text = joinText(content)
            case "str", "e":
                cell.text = rawValue
            case "b":
                cell.text = rawValue == "1" ? "TRUE" : "FALSE"
            default:
                if !rawValue.isEmpty {
                    if let num = Double(rawValue.trimmingCharacters(in: .whitespaces)) {
                        cell.number = num
                        if dateStyles.contains(styleIndex) {
                            let date = serialToDate(num, date1904)
                            cell.date = date
                            cell.text = dayKey(date) ?? jsNumberString(num)
                        } else {
                            cell.text = jsNumberString(num)
                        }
                    } else {
                        cell.text = rawValue
                    }
                }
            }

            rows[cell.row, default: [:]][cell.col] = cell
            maxRow = max(maxRow, cell.row)
            maxCol = max(maxCol, cell.col)
        }

        return Sheet(name: name, rows: rows, maxRow: maxRow, maxCol: maxCol)
    }
}
