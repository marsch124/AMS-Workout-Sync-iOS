import Foundation

/*
 * Writing cells into a workbook without disturbing anything else in it.
 *
 * A port of the writing half of js/xlsx.js — writeCells, buildCell,
 * spliceSheetData, buildRow, widenDimension, save and forceRecalcOnLoad —
 * kept deliberately close to the original, including its string offsets:
 * every slice here is taken in UTF-16 units through NSString, because that is
 * what JavaScript's string indices are, and a writer that counted characters
 * differently would cut a row in a different place the first time a note held
 * an emoji.
 *
 * The rules it inherits (see the web app's CLAUDE.md, invariants 1 and 2):
 * only the cells named are rebuilt; every other row, cell and part is copied
 * across as the exact text or bytes it already was; a cell written over loses
 * its formula, which makes calcChain.xml stale, so that part goes; and the
 * workbook is told to recalculate on open.
 *
 * Nothing in the app calls this yet. It exists to be compared against the web
 * app's writer by tools/write-parity, and it earns a Save button only when
 * that comparison has come back clean.
 */

public enum EditValue: Equatable {
    case number(Double)
    case text(String)
    case date(Date)
    case blank
}

public struct CellEdit: Equatable {
    public let ref: String
    public let value: EditValue
    public let field: String
    public var styleIndex: Int = -1
}

/* escapeXml from js/xlsx.js: the five entities, and control characters dropped. */
func escapeXml(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        switch scalar {
        case "&": out.append(contentsOf: "&amp;".unicodeScalars)
        case "<": out.append(contentsOf: "&lt;".unicodeScalars)
        case ">": out.append(contentsOf: "&gt;".unicodeScalars)
        case "\"": out.append(contentsOf: "&quot;".unicodeScalars)
        default:
            let v = scalar.value
            if v <= 0x08 || v == 0x0B || v == 0x0C || (v >= 0x0E && v <= 0x1F) { continue }
            out.append(scalar)
        }
    }
    return String(out)
}

public func makeRef(_ col: Int, _ row: Int) -> String { indexToCol(col) + String(row) }

func dateToSerial(_ date: Date, _ date1904: Bool) -> Double {
    // getTime() is whole milliseconds; divide it exactly as the web app does.
    let ms = (date.timeIntervalSince1970 * 1000).rounded()
    let serial = ms / 86_400_000 + 25569
    return date1904 ? serial - days1904Offset : serial
}

private let rowOpen = Pattern("<row\\s([^>]*?)(/?)>")
private let cellOpen = Pattern("<c\\s([^>]*?)(/?)>")
private let spansAttr = Pattern("\\sspans=\"[^\"]*\"")
private let dimensionTag = Pattern("<dimension\\s+ref=\"([^\"]*)\"\\s*/>")
private let calcPrTest = Pattern("<calcPr\\b")
private let calcPrTag = Pattern("<calcPr\\b([^>]*?)/?>")
private let fullCalcAttr = Pattern("\\sfullCalcOnLoad=\"[^\"]*\"")

/* String.prototype.replace with a regex and no /g: the first match only. */
func replaceFirst(_ pattern: Pattern, in text: String, with replacement: (NSTextCheckingResult, NSString) -> String) -> String {
    let ns = text as NSString
    guard let m = pattern.regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return text }
    return ns.substring(to: m.range.location) + replacement(m, ns) + ns.substring(from: m.range.location + m.range.length)
}

/* String.prototype.replace with a string pattern: the first occurrence only. */
func replaceFirst(_ needle: String, in text: String, with replacement: String) -> String {
    let ns = text as NSString
    let r = ns.range(of: needle)
    guard r.location != NSNotFound else { return text }
    return ns.replacingCharacters(in: r, with: replacement)
}

private func trimEnd(_ s: String) -> String {
    var scalars = Array(s.unicodeScalars)
    while let last = scalars.last, CharacterSet.whitespacesAndNewlines.contains(last) { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars))
}

extension Workbook {
    public func writeCells(_ sheetName: String, _ edits: [CellEdit]) throws {
        guard let meta = findSheet(sheetName) else { throw WorkbookError.noSheet(sheetName) }
        if edits.isEmpty { return }

        let sheet = try readSheet(sheetName)
        guard var xml = try archive.text(meta.path) else { throw WorkbookError.noSheet(sheetName) }

        var byRow: [Int: [Int: String]] = [:]
        var newMaxRow = sheet.maxRow
        var newMaxCol = sheet.maxCol

        for edit in edits {
            guard let pos = parseRef(edit.ref) else { continue }
            let existing = sheet.cell(pos.row, pos.col)
            if existing?.hasFormula == true { formulaDropped = true }
            byRow[pos.row, default: [:]][pos.col] = buildCell(pos, edit, existing)
            newMaxRow = max(newMaxRow, pos.row)
            newMaxCol = max(newMaxCol, pos.col)
        }

        xml = spliceSheetData(xml, byRow)
        xml = widenDimension(xml, newMaxRow, newMaxCol)

        archive.set(meta.path, xml)
        dirtySheets.insert(sheetName)
        cache[sheetName] = nil
    }

    func buildCell(_ pos: (col: Int, row: Int), _ edit: CellEdit, _ existing: Cell?) -> String {
        let ref = makeRef(pos.col, pos.row)
        let styleIndex: Int
        if let existing, existing.styleIndex >= 0 { styleIndex = existing.styleIndex }
        else { styleIndex = edit.styleIndex >= 0 ? edit.styleIndex : -1 }
        let s = styleIndex >= 0 ? " s=\"\(styleIndex)\"" : ""

        switch edit.value {
        case .blank:
            return "<c r=\"\(ref)\"\(s)/>"
        case .text(let t) where t.isEmpty:
            return "<c r=\"\(ref)\"\(s)/>"
        case .number(let n):
            if n.isNaN { return "<c r=\"\(ref)\"\(s)/>" }
            return "<c r=\"\(ref)\"\(s)><v>\(jsNumberString(n))</v></c>"
        case .date(let date):
            // Only a bare serial into a cell already formatted as a date —
            // anywhere else 45871 would show up and look broken.
            if styleIndex >= 0 && dateStyles.contains(styleIndex) {
                return "<c r=\"\(ref)\"\(s)><v>\(jsNumberString(dateToSerial(date, date1904)))</v></c>"
            }
            return "<c r=\"\(ref)\"\(s) t=\"inlineStr\"><is><t>\(escapeXml(dayKey(date) ?? ""))</t></is></c>"
        case .text(let t):
            return "<c r=\"\(ref)\"\(s) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXml(t))</t></is></c>"
        }
    }

    func spliceSheetData(_ xml: String, _ byRow: [Int: [Int: String]]) -> String {
        let doc = xml as NSString
        let openIdx = doc.range(of: "<sheetData").location
        if openIdx == NSNotFound { return xml }

        let openEnd = doc.range(of: ">", range: NSRange(location: openIdx, length: doc.length - openIdx)).location
        let selfClosed = openEnd > 0 && doc.substring(with: NSRange(location: openEnd - 1, length: 1)) == "/"
        let closeIdx = selfClosed ? openEnd + 1 : doc.range(of: "</sheetData>").location
        let body: NSString = selfClosed ? "" : doc.substring(with: NSRange(location: openEnd + 1, length: closeIdx - openEnd - 1)) as NSString
        let bodyString = body as String

        var pending = byRow
        var out: [String] = []
        var cursor = 0
        var searchFrom = 0

        while searchFrom <= body.length,
              let m = rowOpen.regex.firstMatch(in: bodyString, range: NSRange(location: searchFrom, length: body.length - searchFrom)) {
            let attrs = body.substring(with: m.range(at: 1))
            let selfClosingRow = body.substring(with: m.range(at: 2)) == "/"
            let rowStart = m.range.location
            var rowEnd: Int
            var content = ""
            let afterTag = m.range.location + m.range.length
            if selfClosingRow {
                rowEnd = afterTag
                searchFrom = afterTag
            } else {
                let close = body.range(of: "</row>", range: NSRange(location: afterTag, length: body.length - afterTag)).location
                if close == NSNotFound { break }
                content = body.substring(with: NSRange(location: afterTag, length: close - afterTag))
                rowEnd = close + 6
                searchFrom = rowEnd
            }
            if m.range.length == 0 { searchFrom += 1 }

            let rowNum = Int(attr(attrs, "r") ?? "0") ?? 0

            let inserted = pending.keys.filter { rowNum != 0 && $0 < rowNum }.sorted()
            out.append(body.substring(with: NSRange(location: cursor, length: rowStart - cursor)))
            for num in inserted {
                out.append(buildRow(num, pending[num]!, nil))
                pending[num] = nil
            }

            if let cells = pending[rowNum] {
                out.append(buildRow(rowNum, cells, (attrs, content)))
                pending[rowNum] = nil
            } else {
                out.append(body.substring(with: NSRange(location: rowStart, length: rowEnd - rowStart)))
            }
            cursor = rowEnd
        }

        out.append(body.substring(from: cursor))
        for num in pending.keys.sorted() {
            out.append(buildRow(num, pending[num]!, nil))
        }

        let newBody = out.joined()
        if selfClosed {
            let openTag = trimEnd(doc.substring(with: NSRange(location: openIdx, length: openEnd - 1 - openIdx))) + ">"
            return doc.substring(to: openIdx) + openTag + newBody + "</sheetData>" + doc.substring(from: openEnd + 1)
        }
        return doc.substring(to: openEnd + 1) + newBody + doc.substring(from: closeIdx)
    }

    func buildRow(_ rowNum: Int, _ cellsByCol: [Int: String], _ existing: (attrs: String, content: String)?) -> String {
        var kept: [Int: String] = [:]

        if let existing {
            let content = existing.content as NSString
            let contentString = existing.content
            var searchFrom = 0
            while searchFrom <= content.length,
                  let m = cellOpen.regex.firstMatch(in: contentString, range: NSRange(location: searchFrom, length: content.length - searchFrom)) {
                let start = m.range.location
                let afterTag = m.range.location + m.range.length
                let end: Int
                if content.substring(with: m.range(at: 2)) == "/" {
                    end = afterTag
                } else {
                    let close = content.range(of: "</c>", range: NSRange(location: afterTag, length: content.length - afterTag)).location
                    if close == NSNotFound { break }
                    end = close + 4
                }
                searchFrom = end
                if let pos = parseRef(attr(content.substring(with: m.range(at: 1)), "r") ?? "") {
                    kept[pos.col] = content.substring(with: NSRange(location: start, length: end - start))
                }
            }
        }

        for (col, xml) in cellsByCol { kept[col] = xml }
        let cols = kept.keys.sorted()
        let inner = cols.map { kept[$0]! }.joined()

        var attrs: String
        if let existing {
            attrs = replaceFirst(spansAttr, in: existing.attrs) { _, _ in "" }
            if attrs.hasSuffix("/") { attrs.removeLast() }
            attrs = attrs.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            attrs = "r=\"\(rowNum)\""
        }
        if let first = cols.first, let last = cols.last {
            attrs += " spans=\"\(first):\(last)\""
        }
        return "<row \(attrs)>\(inner)</row>"
    }

    func widenDimension(_ xml: String, _ maxRow: Int, _ maxCol: Int) -> String {
        guard let m = dimensionTag.first(xml), let whole = m[0], let ref = m[1] else { return xml }
        let parts = ref.components(separatedBy: ":")
        guard let end = parseRef(parts.last ?? "") else { return xml }
        if end.row >= maxRow && end.col >= maxCol { return xml }
        let start = parts.count > 1 ? parts[0] : "A1"
        let widened = start + ":" + makeRef(max(end.col, maxCol), max(end.row, maxRow))
        return replaceFirst(whole, in: xml, with: "<dimension ref=\"\(widened)\"/>")
    }

    public func save() throws -> Data {
        if formulaDropped && archive.has("xl/calcChain.xml") {
            archive.remove("xl/calcChain.xml")
        }
        if !dirtySheets.isEmpty { try forceRecalcOnLoad() }
        return try archive.save()
    }

    func forceRecalcOnLoad() throws {
        guard var xml = try archive.text("xl/workbook.xml") else { return }
        if calcPrTest.test(xml) {
            if xml.contains("fullCalcOnLoad=\"1\"") { return }
            xml = replaceFirst(calcPrTag, in: xml) { m, ns in
                var cleaned = replaceFirst(fullCalcAttr, in: ns.substring(with: m.range(at: 1))) { _, _ in "" }
                if cleaned.hasSuffix("/") { cleaned.removeLast() }
                return "<calcPr" + cleaned + " fullCalcOnLoad=\"1\"/>"
            }
        } else {
            xml = replaceFirst("</workbook>", in: xml, with: "<calcPr fullCalcOnLoad=\"1\"/></workbook>")
        }
        archive.set("xl/workbook.xml", xml)
    }
}
