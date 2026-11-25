import Foundation

/*
 * The plan written out as a spreadsheet again.
 *
 * Once the plan lives in the app, the workbook is no longer its home — but a
 * copy anyone can open in twenty years is worth keeping, and it is the road
 * back should he ever want Excel to be the home again. The copy is made from
 * the workbook as it stood at the switch: only the cells that differ are
 * written, by the writer that has always written his plan, so every sheet,
 * heading, colour and formula he made is still his.
 *
 * Before the bytes are handed over they are read back and held against the
 * book. A copy that does not say what the app says is never given out.
 */
public enum PlanExport {
    public enum Problem: Error, LocalizedError {
        case doesNotMatch([String])
        public var errorDescription: String? {
            switch self {
            case .doesNotMatch(let why):
                return "The spreadsheet copy did not read back the same as the plan in the app (\(why.prefix(3).joined(separator: "; "))). It was not saved."
            }
        }
    }

    public static func workbook(_ book: PlanBook, template: Data) throws -> Data {
        let wb = try Workbook(data: template)
        guard let mapping = try Plan.mapping(for: wb), let home = mapping.sheets.first else { throw SyncError.noLayout }
        let was = Dictionary(Plan.build(wb, mapping).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let cols = mapping.columns
        var edits: [String: [CellEdit]] = [:]
        var weekdayNames: [String: [Int: String]] = [:]
        var nextRow: [String: Int] = [:]

        func put(_ sheet: String, _ row: Int, _ field: String, _ value: EditValue) {
            guard let col = cols[field] else { return }
            edits[sheet, default: []].append(CellEdit(ref: makeRef(col, row), value: value, field: field))
        }
        func words(_ text: String) -> EditValue { text.isEmpty ? .blank : .text(text) }
        func names(_ sheet: String) -> [Int: String] {
            if let known = weekdayNames[sheet] { return known }
            let learned = (try? wb.readSheet(sheet)).map { learnWeekdayNames($0, mapping) } ?? [:]
            weekdayNames[sheet] = learned
            return learned
        }

        for w in book.sessions where w.rows.count <= 1 {
            let old = was[w.key]
            let sheet = old == nil ? home : w.sheet
            var row = w.row
            if old == nil {
                let free = nextRow[sheet] ?? (((try? wb.readSheet(sheet))?.maxRow ?? mapping.firstDataRow) + 2)
                row = free
                nextRow[sheet] = free + 1
                put(sheet, row, "phase", words(w.phase))
            }
            if old?.dayKey != w.dayKey {
                put(sheet, row, "date", .date(w.date))
                let index = utc.component(.weekday, from: w.date) - 1
                let name = names(sheet)[index] ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index]
                put(sheet, row, "weekday", .text(name))
            }
            if old?.disciplineRaw != w.disciplineRaw { put(sheet, row, "discipline", words(w.disciplineRaw)) }
            if old?.title != w.title { put(sheet, row, "title", words(w.title)) }
            if old?.planned.durationRaw != w.planned.durationRaw {
                put(sheet, row, "plannedDuration", w.planned.durationRaw.map { .number($0) } ?? .blank)
            }
            if old?.planned.distanceRaw != w.planned.distanceRaw {
                put(sheet, row, "plannedDistance", w.planned.distanceRaw.map { .number($0) } ?? .blank)
            }
            if (old?.planned.intensity ?? "") != w.planned.intensity { put(sheet, row, "plannedIntensity", words(w.planned.intensity)) }
            if (old?.planned.description ?? "") != w.planned.description { put(sheet, row, "description", words(w.planned.description)) }
            for field in Set(old?.results.keys.map { $0 } ?? []).union(w.results.keys).sorted() {
                let before = old?.results[field], now = w.results[field]
                if before?.text == now?.text { continue }
                guard let now else { put(sheet, row, field, .blank); continue }
                put(sheet, row, field, now.number.map { .number($0) } ?? .text(now.text))
            }
        }

        // A session taken out of the plan: its row is emptied of what makes it a session.
        let kept = Set(book.sessions.map(\.key))
        for (key, old) in was where !kept.contains(key) && old.rows.count == 1 {
            for field in ["discipline", "title", "description", "plannedDuration", "plannedIntensity"] {
                put(old.sheet, old.row, field, .blank)
            }
        }

        for (sheet, list) in edits { try wb.writeCells(sheet, list) }

        // Extras: every row that is new or reads differently, written whole.
        let before = Dictionary(Extras.read(wb).map { ($0.row, $0) }, uniquingKeysWith: { first, _ in first })
        let changed = book.extras.filter { before[$0.row] != $0 }
        if !changed.isEmpty {
            let name = try Extras.ensureSheet(wb)
            let learned = names(home)
            var cells: [CellEdit] = []
            func cell(_ col: Int, _ row: Int, _ value: EditValue) {
                cells.append(CellEdit(ref: makeRef(col, row), value: value, field: "extra"))
            }
            func figure(_ text: String) -> EditValue {
                if text.isEmpty { return .blank }
                let n = jsParseFloat(firstCommaToDot(text))
                return n.isNaN || jsNumberString(n) != text ? .text(text) : .number(n)
            }
            for x in changed {
                cell(Extras.Col.date, x.row, words(x.date))
                if let date = parseDayKey(x.date) {
                    let index = utc.component(.weekday, from: date) - 1
                    cell(Extras.Col.weekday, x.row, .text(learned[index] ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index]))
                }
                cell(Extras.Col.activity, x.row, words(x.label))
                cell(Extras.Col.what, x.row, words(x.what))
                cell(Extras.Col.duration, x.row, x.minutes.map { .number($0) } ?? .blank)
                cell(Extras.Col.distance, x.row, figure(x.distance))
                cell(Extras.Col.avgHr, x.row, figure(x.avgHr))
                cell(Extras.Col.effort, x.row, figure(x.effort))
                cell(Extras.Col.isTraining, x.row, .text(x.isTraining ? "Yes" : "No"))
                cell(Extras.Col.notes, x.row, words(x.notes))
                cell(Extras.Col.ref, x.row, words(x.ref))
            }
            if changed.contains(where: { !$0.ref.isEmpty }), let sheet = try? wb.readSheet(name), sheet.textAt(1, Extras.Col.ref).isEmpty {
                cell(Extras.Col.ref, 1, .text("Ref"))
            }
            try wb.writeCells(name, cells)
        }

        let bytes = edits.isEmpty && changed.isEmpty ? template : try wb.save()
        let problems = try mismatches(bytes, book)
        if !problems.isEmpty { throw Problem.doesNotMatch(problems) }
        return bytes
    }

    /* The copy read back and held against the book. A session made in the app is found by its day, sport and words. */
    static func mismatches(_ bytes: Data, _ book: PlanBook) throws -> [String] {
        let wb = try Workbook(data: bytes)
        guard let mapping = try Plan.mapping(for: wb) else { return ["the copy has no plan in it"] }
        let read = Plan.build(wb, mapping)
        let byKey = Dictionary(read.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [String] = []
        if read.count != book.sessions.count { out.append("\(book.sessions.count) sessions in the app, \(read.count) in the copy") }
        for w in book.sessions where w.rows.count <= 1 {
            let twin = byKey[w.key] ?? read.first { $0.dayKey == w.dayKey && $0.title == w.title && $0.disciplineRaw == w.disciplineRaw }
            guard let o = twin else { out.append("\(w.title) on \(w.dayKey) is not in the copy"); continue }
            if o.dayKey != w.dayKey || o.disciplineRaw != w.disciplineRaw || o.title != w.title
                || o.planned != w.planned || o.missed != w.missed || o.loggedInSheet != w.loggedInSheet {
                out.append("\(w.title) on \(w.dayKey) reads differently in the copy")
                continue
            }
            for field in Set(w.results.keys).union(o.results.keys) where w.results[field]?.text != o.results[field]?.text {
                out.append("\(w.title) on \(w.dayKey): \(field) reads differently in the copy")
            }
            if out.count > 30 { break }
        }
        let extras = Extras.read(wb)
        if extras != book.extras { out.append("the extra activities read differently in the copy") }
        return out
    }
}
