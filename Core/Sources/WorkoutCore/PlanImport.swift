import Foundation

/*
 * The one-time move: a workbook read into a book, and the proof that nothing
 * changed on the way.
 *
 * The reading is the app's own (Plan.build, Extras.read, Zones.read) — the
 * code that has read this plan every day since September. What is added here
 * is only what the app never needed while Excel was the home: each row's
 * cells word for word, the week headings, and a list of anything that looks
 * odd. Odd values are taken in exactly as written and shown; nothing is
 * "fixed" on the way in.
 */

public struct Oddity: Equatable, Codable, Identifiable {
    public var id: String { kind + "|" + place }
    /* pace | effort | future | restDay | order */
    public let kind: String
    /* "Weekly Schedules!4", or "" for a count. */
    public let place: String
    public let words: String

    public init(kind: String, place: String, words: String) {
        self.kind = kind; self.place = place; self.words = words
    }
}

public struct MonthTally: Equatable, Codable, Identifiable {
    public var id: String { month }
    /* "2026-09" */
    public let month: String
    public var sessions = 0
    public var done = 0
    public var missed = 0
    public var plannedMinutes = 0
    public var recordedMinutes = 0

    public var label: String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let parts = month.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return month }
        return names[m - 1] + " " + parts[0]
    }
}

/* The plan counted: what both sides of the proof are measured by. */
public struct PlanTally: Equatable, Codable {
    public var sessions = 0
    public var training = 0
    public var rest = 0
    public var done = 0
    public var missed = 0
    public var toCome = 0
    public var extras = 0
    public var extrasThatCount = 0
    public var plannedMinutes = 0
    public var recordedMinutes = 0
    /* Every month with a training session before today. */
    public var months: [MonthTally] = []
}

public struct ProofLine: Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let before: String
    public let after: String
    public var same: Bool { before == after }
}

public struct PlanProof: Equatable {
    public let before: PlanTally
    public let after: PlanTally
    /* Session by session, field by field: every difference in words. Empty is the proof. */
    public let differences: [String]
    public let compared: Int

    public var matches: Bool { differences.isEmpty && before == after }

    public var lines: [ProofLine] {
        func line(_ label: String, _ pick: (PlanTally) -> Int) -> ProofLine {
            ProofLine(label: label, before: String(pick(before)), after: String(pick(after)))
        }
        return [
            line("Plan days", { $0.sessions }),
            line("Training sessions", { $0.training }),
            line("Rest days", { $0.rest }),
            line("Done", { $0.done }),
            line("Missed", { $0.missed }),
            line("Still to come", { $0.toCome }),
            line("Extra workouts", { $0.extras }),
            line("Planned minutes", { $0.plannedMinutes }),
            line("Recorded minutes", { $0.recordedMinutes })
        ]
    }
}

public struct PlanImport {
    public let book: PlanBook
    public let oddities: [Oddity]
    public let proof: PlanProof

    // MARK: reading

    public static func read(_ data: Data, fileName: String, today: String, now: Date = Date()) throws -> PlanImport {
        let workbook = try Workbook(data: data)
        guard let mapping = try Plan.mapping(for: workbook) else { throw SyncError.noLayout }
        let plan = Plan.build(workbook, mapping)
        let extras = Extras.read(workbook)
        let zones = Zones.read(workbook)

        var sessions = plan
        var weeks: [PlanWeek] = []
        for name in mapping.sheets {
            guard let sheet = try? workbook.readSheet(name) else { continue }
            let headings = headingNames(sheet, mapping)
            for i in sessions.indices where sessions[i].sheet == name && sessions[i].rows.count == 1 {
                sessions[i].source = cells(sheet, sessions[i].row, headings)
            }
            weeks += weekHeadings(sheet, mapping, headings)
        }

        var book = PlanBook(
            sessions: sessions, extras: extras, zones: zones,
            weeks: weeks.sorted { $0.monday < $1.monday },
            mapping: mapping,
            origin: PlanOrigin(fileName: fileName, takenAt: now, sessions: sessions.count, extras: extras.count))
        book.tests = tests(workbook)
        // The proof is taken on the book as it comes back off the disk, not on
        // the one in memory: what is stored is what he will be training from.
        book = try PlanBook.decoded(try book.encoded())

        let proof = PlanProof(
            before: tally(plan, extras: extras, mapping: mapping, today: today),
            after: tally(book.sessions, extras: book.extras, mapping: book.mapping, today: today),
            differences: differences(plan, book.sessions) + extraDifferences(extras, book.extras),
            compared: plan.count)
        return PlanImport(book: book, oddities: oddities(plan, extras: extras, mapping: mapping, today: today), proof: proof)
    }

    static func headingNames(_ sheet: Sheet, _ mapping: Mapping) -> [Int: String] {
        var names: [Int: String] = [:]
        guard sheet.maxCol >= 1 else { return names }
        for col in 1...sheet.maxCol {
            let text = sheet.textAt(mapping.headerRow, col)
            if !text.isEmpty { names[col] = text }
        }
        return names
    }

    /* A row's cells by heading. A formula's cell is kept as its answer, as the app always read it. */
    static func cells(_ sheet: Sheet, _ row: Int, _ headings: [Int: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (col, name) in headings {
            let text = sheet.textAt(row, col)
            if !text.isEmpty { out[name] = text }
        }
        return out
    }

    private static let range = Pattern("^(\\d{1,2})\\s+([A-Za-z]{3})[a-z]*\\s*[–-]\\s*(\\d{1,2})\\s+([A-Za-z]{3})[a-z]*\\s+(\\d{4})$")
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /* "07 Sep – 13 Sep 2026" → the Monday, as a day key. */
    static func monday(of text: String) -> String? {
        guard let m = range.first(text.trimmingCharacters(in: .whitespaces)),
              let d = Int(m[1]!), let from = monthNames.firstIndex(of: m[2]!.lowercased()),
              let to = monthNames.firstIndex(of: m[4]!.lowercased()), var year = Int(m[5]!) else { return nil }
        // The year written is the last day's: a week from December into January starts the year before.
        if from > to { year -= 1 }
        let key = String(format: "%04d-%02d-%02d", year, from + 1, d)
        // A day that does not exist is no Monday.
        return parseDayKey(key) == nil ? nil : key
    }

    /*
     * The week headings: rows that carry a week number and a range of dates
     * where a session carries a date and a sport. Read by what they hold, and
     * simply absent from a plan that has none.
     */
    static func weekHeadings(_ sheet: Sheet, _ mapping: Mapping, _ headings: [Int: String]) -> [PlanWeek] {
        guard let dateCol = mapping.columns["date"], sheet.maxRow >= mapping.firstDataRow else { return [] }
        let weekCol = headings.first { normalise($0.value) == "week" }?.key
        let phaseCol = mapping.columns["phase"]
        var out: [PlanWeek] = []
        for row in mapping.firstDataRow...sheet.maxRow {
            guard let monday = monday(of: sheet.textAt(row, dateCol)) else { continue }
            let number = weekCol.flatMap { Int(sheet.textAt(row, $0)) } ?? (out.count + 1)
            let words = phaseCol.map { sheet.textAt(row, $0) } ?? ""
            let parts = words.components(separatedBy: " · ")
            out.append(PlanWeek(number: number, monday: monday, phase: parts.first ?? "",
                                tag: parts.dropFirst().joined(separator: " · ")))
        }
        return out
    }

    // MARK: counting

    static func minutes(_ seconds: Double?) -> Int { Int(((seconds ?? 0) / 60).rounded()) }

    public static func tally(_ plan: [Workout], extras: [ExtraRecord], mapping: Mapping, today: String) -> PlanTally {
        var t = PlanTally()
        var months: [String: MonthTally] = [:]
        t.sessions = plan.count
        for w in plan {
            if w.discipline.id == "rest" { t.rest += 1; continue }
            t.training += 1
            let isDone = w.loggedInSheet && !w.missed
            if w.missed { t.missed += 1 } else if isDone { t.done += 1 }
            // "So far" is every day before today, and anything already
            // logged whatever its day — so the months add up to Done and Missed.
            if w.dayKey >= today && !w.loggedInSheet {
                t.toCome += 1
                continue
            }
            let planned = minutes(Plan.plannedSeconds(w, mapping))
            let recorded = isDone ? Int(Load.minutes(of: w, mapping).rounded()) : 0
            t.plannedMinutes += planned
            t.recordedMinutes += recorded
            let month = String(w.dayKey.prefix(7))
            var m = months[month] ?? MonthTally(month: month)
            m.sessions += 1
            if w.missed { m.missed += 1 } else if isDone { m.done += 1 }
            m.plannedMinutes += planned
            m.recordedMinutes += recorded
            months[month] = m
        }
        t.extras = extras.count
        t.extrasThatCount = extras.filter(\.isTraining).count
        t.months = months.values.sorted { $0.month < $1.month }
        return t
    }

    // MARK: comparing

    /* Two readings of the same plan, session by session. Every difference in words; none is the proof. */
    public static func differences(_ a: [Workout], _ b: [Workout]) -> [String] {
        var out: [String] = []
        let theirs = Dictionary(b.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        if a.count != b.count { out.append("\(a.count) sessions before, \(b.count) after") }
        if a.map(\.key) != b.map(\.key) { out.append("the sessions are not in the same order") }
        for w in a {
            guard let o = theirs[w.key] else { out.append("\(w.key) is missing"); continue }
            func check<T: Equatable>(_ name: String, _ x: T, _ y: T) {
                if x != y { out.append("\(w.key) \(name): \(x) became \(y)") }
            }
            check("day", w.dayKey, o.dayKey)
            check("sport", w.disciplineRaw, o.disciplineRaw)
            check("sport read as", w.discipline.id, o.discipline.id)
            check("words", w.title, o.title)
            check("phase", w.phase, o.phase)
            check("blocks", w.sections, o.sections)
            check("planned", w.planned, o.planned)
            check("done", w.loggedInSheet, o.loggedInSheet)
            check("missed", w.missed, o.missed)
            for field in Set(w.results.keys).union(o.results.keys).sorted() {
                let x = w.results[field], y = o.results[field]
                if x?.text != y?.text || x?.number != y?.number {
                    out.append("\(w.key) \(field): \(x?.text ?? "empty") became \(y?.text ?? "empty")")
                }
            }
            if out.count > 200 { out.append("… and more"); break }
        }
        return out
    }

    public static func extraDifferences(_ a: [ExtraRecord], _ b: [ExtraRecord]) -> [String] {
        if a == b { return [] }
        if a.count != b.count { return ["\(a.count) extra workouts before, \(b.count) after"] }
        return zip(a, b).filter { $0 != $1 }.map { "extra of \($0.0.date) (\($0.0.label)) changed" }
    }

    // MARK: what looks odd

    private static let clock = Pattern("^(\\d{1,2}):(\\d{2})$")

    public static func oddities(_ plan: [Workout], extras: [ExtraRecord], mapping: Mapping, today: String) -> [Oddity] {
        var out: [Oddity] = []
        let restDays = Set(plan.filter { $0.discipline.id == "rest" }.map(\.dayKey))

        var outOfOrder = 0
        var bySheet: [String: [Workout]] = [:]
        for w in plan { bySheet[w.sheet, default: []].append(w) }
        for (_, list) in bySheet {
            let rows = list.sorted { $0.row < $1.row }
            for (previous, w) in zip(rows, rows.dropFirst()) where w.dayKey < previous.dayKey { outOfOrder += 1 }
        }
        if outOfOrder > 0 {
            out.append(Oddity(kind: "order", place: "",
                              words: "\(outOfOrder) rows stood out of date order in the sheet. The app goes by the date, as it always has."))
        }

        for w in plan {
            if let pace = w.results["avgPace"]?.text, let m = clock.first(pace), let seconds = Int(m[2]!), seconds >= 60 {
                out.append(Oddity(kind: "pace", place: w.key,
                                  words: "\(PlanBook.day(w.dayKey)), \(w.discipline.label): the pace reads \u{201C}\(pace)\u{201D}."))
            }
            if let effort = w.results["rpe"]?.number, effort < 1 || effort > 10 {
                out.append(Oddity(kind: "effort", place: w.key,
                                  words: "\(PlanBook.day(w.dayKey)), \(w.discipline.label): how hard it was reads \(jsNumberString(effort)), outside 1 to 10."))
            }
            if w.discipline.id != "rest", w.loggedInSheet, !w.missed, w.dayKey > today {
                out.append(Oddity(kind: "future", place: w.key,
                                  words: "\(PlanBook.day(w.dayKey)), \(w.discipline.label): ticked as done, and the day has not come yet."))
            }
            if w.discipline.id != "rest", restDays.contains(w.dayKey), w.dayKey < today {
                out.append(Oddity(kind: "restDay", place: w.key,
                                  words: "\(PlanBook.day(w.dayKey)), \(w.discipline.label): on a day the plan also calls a rest day."))
            }
        }
        for x in extras {
            let effort = jsParseFloat(firstCommaToDot(x.effort))
            if !effort.isNaN, effort < 1 || effort > 10 {
                out.append(Oddity(kind: "effort", place: "Extras!\(x.row)",
                                  words: "\(PlanBook.day(x.date)), \(x.label): how hard it was reads \(x.effort), outside 1 to 10."))
            }
        }
        return out
    }
}
