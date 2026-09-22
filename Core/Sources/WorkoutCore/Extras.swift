import Foundation

/*
 * Things you did that the plan did not ask for. A port of js/extras.js.
 *
 * They go on their own sheet, never into the plan: the plan's sheet is
 * totalled by fixed row ranges and by whole columns, so a row added to it
 * would be counted by one and missed by the other — and twenty minutes of
 * meditation is not twenty minutes of training, so folding it in would make
 * the compliance figure dishonest. A column says whether each one counts.
 */

public struct Activity: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let kind: String       // training | restorative | everyday
    public let icon: String
    public let colorId: String    // a sport id for the palette, or "rest" for grey
}

/*
 * An extra already written, and what an adjustment to it may change.
 *
 * An extra is appended rather than written to a row the app knows, so
 * correcting one means finding its row again at sync time: by the reference
 * the phone gave it, and — for the rows his sheet carries from before
 * references existed — by the day, activity and length that identified one
 * then. That is alreadyRecorded's own fallback, and the rule holds here too:
 * anything that points at an extra points at it the way the writer does.
 *
 * `fields` names the columns the person actually altered. The whole record
 * travels with the entry, but only those columns are written. The phone's
 * copy of the row was read before whatever was last done to the file in
 * Excel, so writing all eleven cells back would put stale values over newer
 * ones — the log form's changedOnly rule, for the same reason.
 *
 * `id` is the record this was made from, for pairing an edit waiting on the
 * phone with the row it belongs to on screen. It is never written anywhere.
 */
public struct ExtraTarget: Codable, Equatable {
    public var id: String
    public var ref: String
    public var date: String
    public var label: String
    public var minutes: Double?
    public var fields: [String]

    public init(id: String, ref: String, date: String, label: String, minutes: Double?, fields: [String]) {
        self.id = id
        self.ref = ref
        self.date = date
        self.label = label
        self.minutes = minutes
        self.fields = fields
    }
}

/* The columns an adjustment may name. The date carries the weekday beside it. */
public enum ExtraField {
    public static let date = "date"
    public static let activity = "activity"
    public static let what = "what"
    public static let duration = "duration"
    public static let distance = "distance"
    public static let avgHr = "avgHr"
    public static let effort = "effort"
    public static let isTraining = "isTraining"
    public static let notes = "notes"
}

public struct ExtraEntry: Codable, Equatable {
    public var date: String
    public var activity: String
    public var what: String = ""
    public var minutes: Double?
    public var distance: Double?
    public var avgHr: Double?
    public var effort: Double?
    public var isTraining: Bool = false
    public var notes: String = ""
    public var ref: String
    /* Set when this corrects a row already on the sheet rather than adding one. */
    public var editing: ExtraTarget?

    public init(date: String, activity: String, ref: String = Extras.newRef()) {
        self.date = date
        self.activity = activity
        self.ref = ref
    }
}

/* A row of the Extras sheet, read back. */
public struct ExtraRecord: Identifiable, Equatable {
    public var id: String { ref.isEmpty ? "row-\(row)" : ref }
    public let row: Int
    public let date: String
    public let activity: String
    public let label: String
    public let what: String
    public let minutes: Double?
    public let distance: String
    public let avgHr: String
    public let effort: String
    public let isTraining: Bool
    public let notes: String
    public let ref: String
}

public enum Extras {
    public static let sheetName = "Extras"
    static let altSheetName = "AMS Extras"

    public static let columns = ["Date", "Day", "Activity", "What it was", "Duration (min)", "Distance (km)",
                                 "Avg HR", "Effort", "Counts as training", "Notes", "Ref"]

    enum Col {
        static let date = 1, weekday = 2, activity = 3, what = 4, duration = 5, distance = 6
        static let avgHr = 7, effort = 8, isTraining = 9, notes = 10, ref = 11
    }

    public static let defaultActivities: [Activity] = [
        Activity(id: "swim", label: "Swim", kind: "training", icon: "icon-swim", colorId: "swim"),
        Activity(id: "bike", label: "Bike", kind: "training", icon: "icon-bike", colorId: "bike"),
        Activity(id: "run", label: "Run", kind: "training", icon: "icon-run", colorId: "run"),
        Activity(id: "strength", label: "Strength", kind: "training", icon: "icon-strength", colorId: "strength"),
        Activity(id: "mobility", label: "Mobility", kind: "restorative", icon: "icon-mobility", colorId: "mobility"),
        Activity(id: "yoga", label: "Yoga", kind: "restorative", icon: "icon-mobility", colorId: "mobility"),
        Activity(id: "meditation", label: "Meditation", kind: "restorative", icon: "icon-check", colorId: "rest"),
        Activity(id: "breathing", label: "Breathing", kind: "restorative", icon: "icon-check", colorId: "rest"),
        Activity(id: "walk", label: "Walk", kind: "everyday", icon: "icon-run", colorId: "rest"),
        Activity(id: "hike", label: "Hike", kind: "everyday", icon: "icon-run", colorId: "rest"),
        Activity(id: "ski", label: "Ski", kind: "everyday", icon: "icon-run", colorId: "rest"),
        Activity(id: "other", label: "Something else", kind: "everyday", icon: "icon-other", colorId: "rest")
    ]

    /* An unknown id resolves to "Something else" rather than failing — an extra
       logged under an activity later deleted still has to render. */
    public static func activity(_ id: String) -> Activity {
        defaultActivities.first { $0.id == id } ?? defaultActivities.last!
    }

    public static func wantsMetrics(_ id: String) -> Bool { activity(id).kind != "restorative" }

    /* Short, unique: what alreadyRecorded() recognises a replay by. */
    public static func newRef() -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        var rnd = ""
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        for _ in 0..<4 { rnd.append(alphabet[Int.random(in: 0..<36)]) }
        return "x" + String(ms, radix: 36) + rnd
    }

    /* What identifies one extra to anything that points at it — mirrors alreadyRecorded's fallback. */
    public static func keyFor(date: String, label: String, minutes: Double?) -> String {
        "extra:" + date + ":" + normalise(label) + ":" + (minutes.map(jsNumberString) ?? "")
    }

    /* A sheet of that name is only used when its headings say it is ours. */
    public static func looksLikeOurs(_ sheet: Sheet) -> Bool {
        normalise(sheet.textAt(1, Col.date)) == "date"
            && normalise(sheet.textAt(1, Col.activity)) == "activity"
            && normalise(sheet.textAt(1, Col.duration)).hasPrefix("duration")
    }

    public static func sheetName(for workbook: Workbook) throws -> String {
        if workbook.findSheet(sheetName) == nil { return sheetName }
        if let sheet = try? workbook.readSheet(sheetName), looksLikeOurs(sheet) { return sheetName }
        for n in 0..<20 {
            let name = n == 0 ? altSheetName : altSheetName + " " + String(n + 1)
            if workbook.findSheet(name) == nil { return name }
            if let sheet = try? workbook.readSheet(name), looksLikeOurs(sheet) { return name }
        }
        throw SyncError.extrasSheetTaken
    }

    public static func ensureSheet(_ workbook: Workbook) throws -> String {
        let name = try sheetName(for: workbook)
        if workbook.findSheet(name) != nil { return name }
        try workbook.createSheet(name, headers: columns)
        return name
    }

    /* First row with nothing in it. */
    static func nextRow(_ sheet: Sheet) -> Int {
        var row = 2
        while row <= sheet.maxRow {
            let used = sheet.rows[row]?.values.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
            if !used { return row }
            row += 1
        }
        return max(row, 2)
    }

    /*
     * Has this already been written? Extras append rather than overwrite, so a
     * queue replayed twice would otherwise duplicate them. Matched by the ref
     * the phone gave it; the old day + activity + length rule only for entries
     * and rows from before refs existed.
     */
    public static func alreadyRecorded(_ sheet: Sheet, _ entry: ExtraEntry) -> Bool {
        if !entry.ref.isEmpty {
            if sheet.maxRow >= 2 {
                for row in 2...sheet.maxRow where sheet.textAt(row, Col.ref) == entry.ref { return true }
            }
            return false
        }
        guard sheet.maxRow >= 2 else { return false }
        for row in 2...sheet.maxRow {
            if sheet.textAt(row, Col.date) != entry.date { continue }
            if normalise(sheet.textAt(row, Col.activity)) != normalise(activity(entry.activity).label) { continue }
            let theirs = sheet.cell(row, Col.duration)?.number
            if theirs == entry.minutes { return true }
        }
        return false
    }

    /* The cells for one extra, on the first free row. */
    public static func buildEdits(_ sheet: Sheet, _ entry: ExtraEntry, weekdayNames: [Int: String]) -> (row: Int, edits: [CellEdit]) {
        let row = nextRow(sheet)
        var edits: [CellEdit] = []
        func push(_ col: Int, _ value: EditValue?) {
            guard let value else { return }
            if case .text(let t) = value, t.isEmpty { return }
            edits.append(CellEdit(ref: makeRef(col, row), value: value, field: "extra"))
        }
        push(Col.date, .text(entry.date))
        if let date = parseDayKey(entry.date) {
            let index = utc.component(.weekday, from: date) - 1
            let name = weekdayNames[index] ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index]
            push(Col.weekday, .text(name))
        }
        push(Col.activity, .text(activity(entry.activity).label))
        push(Col.what, .text(entry.what))
        push(Col.duration, entry.minutes.map { .number($0) })
        push(Col.distance, entry.distance.map { .number($0) })
        push(Col.avgHr, entry.avgHr.map { .number($0) })
        push(Col.effort, entry.effort.map { .number($0) })
        push(Col.isTraining, .text(entry.isTraining ? "Yes" : "No"))
        push(Col.notes, .text(entry.notes))
        push(Col.ref, .text(entry.ref))

        // A sheet written before refs existed has ten headings: give it the
        // eleventh in the same write as the row that needs it.
        if !entry.ref.isEmpty && sheet.textAt(1, Col.ref).isEmpty {
            edits.append(CellEdit(ref: makeRef(Col.ref, 1), value: .text("Ref"), field: "extra"))
        }
        return (row, edits)
    }

    /*
     * The row an adjustment belongs to, in a sheet that may have been edited
     * since the phone last read it.
     *
     * The reference first, because it is the one thing about a row that does
     * not change when its cells do. A row written before references existed
     * has only the identity it had then, so the old triple stands in — and
     * only for rows that still carry no reference, or a second walk of the
     * same length on the same day would answer for the first.
     */
    public static func findRow(_ sheet: Sheet, _ target: ExtraTarget) -> Int? {
        guard sheet.maxRow >= 2 else { return nil }
        if !target.ref.isEmpty {
            for row in 2...sheet.maxRow where sheet.textAt(row, Col.ref) == target.ref { return row }
        }
        for row in 2...sheet.maxRow {
            if !sheet.textAt(row, Col.ref).isEmpty { continue }
            if sheet.textAt(row, Col.date) != target.date { continue }
            if normalise(sheet.textAt(row, Col.activity)) != normalise(target.label) { continue }
            if sheet.cell(row, Col.duration)?.number != target.minutes { continue }
            return row
        }
        return nil
    }

    /*
     * The cells for an adjustment, on the row it names: only the columns the
     * person changed, and a box he emptied is emptied in the sheet — an extra
     * is this app's own row, so there is no plan value underneath to protect.
     */
    public static func buildEdits(_ sheet: Sheet, _ entry: ExtraEntry, row: Int, weekdayNames: [Int: String]) -> [CellEdit] {
        guard let target = entry.editing else { return [] }
        let changed = Set(target.fields)
        var edits: [CellEdit] = []
        func put(_ col: Int, _ value: EditValue) {
            edits.append(CellEdit(ref: makeRef(col, row), value: value, field: "extra"))
        }
        func text(_ col: Int, _ value: String) { put(col, value.isEmpty ? .blank : .text(value)) }
        func number(_ col: Int, _ value: Double?) { put(col, value.map { EditValue.number($0) } ?? .blank) }

        if changed.contains(ExtraField.date) {
            text(Col.date, entry.date)
            if let date = parseDayKey(entry.date) {
                let index = utc.component(.weekday, from: date) - 1
                text(Col.weekday, weekdayNames[index] ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index])
            } else {
                put(Col.weekday, .blank)
            }
        }
        if changed.contains(ExtraField.activity) { text(Col.activity, activity(entry.activity).label) }
        if changed.contains(ExtraField.what) { text(Col.what, entry.what) }
        if changed.contains(ExtraField.duration) { number(Col.duration, entry.minutes) }
        if changed.contains(ExtraField.distance) { number(Col.distance, entry.distance) }
        if changed.contains(ExtraField.avgHr) { number(Col.avgHr, entry.avgHr) }
        if changed.contains(ExtraField.effort) { number(Col.effort, entry.effort) }
        if changed.contains(ExtraField.isTraining) { text(Col.isTraining, entry.isTraining ? "Yes" : "No") }
        if changed.contains(ExtraField.notes) { text(Col.notes, entry.notes) }
        if edits.isEmpty { return [] }

        // A row from before references existed gains one now, so the next
        // correction finds it by name rather than by what it happens to say —
        // which this very write may be about to change.
        if !entry.ref.isEmpty && sheet.textAt(row, Col.ref).isEmpty {
            put(Col.ref, .text(entry.ref))
            if sheet.textAt(1, Col.ref).isEmpty {
                edits.append(CellEdit(ref: makeRef(Col.ref, 1), value: .text("Ref"), field: "extra"))
            }
        }
        return edits
    }

    private static let yes = Pattern("^y|^j|^1|^true", [.caseInsensitive])

    /* Everything recorded so far, newest first. */
    public static func read(_ workbook: Workbook) -> [ExtraRecord] {
        guard let name = try? sheetName(for: workbook), workbook.findSheet(name) != nil,
              let sheet = try? workbook.readSheet(name), looksLikeOurs(sheet), sheet.maxRow >= 2 else { return [] }
        var out: [ExtraRecord] = []
        for row in 2...sheet.maxRow {
            let date = sheet.textAt(row, Col.date)
            let label = sheet.textAt(row, Col.activity)
            if date.isEmpty && label.isEmpty { continue }
            let match = defaultActivities.first { normalise($0.label) == normalise(label) }
            out.append(ExtraRecord(
                row: row, date: date, activity: match?.id ?? "other",
                label: label.isEmpty ? "Something else" : label,
                what: sheet.textAt(row, Col.what),
                minutes: sheet.cell(row, Col.duration)?.number,
                distance: sheet.textAt(row, Col.distance),
                avgHr: sheet.textAt(row, Col.avgHr),
                effort: sheet.textAt(row, Col.effort),
                isTraining: yes.test(sheet.textAt(row, Col.isTraining)),
                notes: sheet.textAt(row, Col.notes),
                ref: sheet.textAt(row, Col.ref)))
        }
        return out.sorted { a, b in a.date != b.date ? a.date > b.date : a.row > b.row }
    }
}
