import Foundation

/*
 * "Export for Claude": the whole season as one readable text he can paste
 * into the Claude app and talk about. Plain headings, short lines, no JSON.
 * Pure: it reads the book it is given and sends nothing anywhere.
 */
public enum ClaudeExport {
    static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    public static func brief(_ book: PlanBook, today: String) -> String {
        var out: [String] = []
        let plan = book.sessions
        let mapping = book.mapping
        let thisMonday = PlanView.weekStart(today)

        out.append("MY TRAINING SEASON")
        out.append("Made on \(today) by the AMS Triathlon Training app. I am an amateur preparing for a half-distance triathlon.")
        out.append("Please read it all, then I will ask you about my season. Minutes are shown as done / planned.")

        // Phases
        out.append("")
        out.append("PHASES")
        var runs: [(phase: String, first: PlanWeek, last: PlanWeek)] = []
        for w in book.weeks.sorted(by: { $0.number < $1.number }) {
            if let last = runs.last, last.phase == w.phase { runs[runs.count - 1].last = w }
            else { runs.append((w.phase, w, w)) }
        }
        if runs.isEmpty { out.append("No phases in the plan.") }
        for r in runs {
            let weeks = r.first.number == r.last.number ? "week \(r.first.number)" : "weeks \(r.first.number) to \(r.last.number)"
            out.append("\(r.phase.isEmpty ? "(unnamed)" : r.phase): \(weeks), \(r.first.monday) to \(PlanView.addDays(r.last.monday, 6))")
        }
        let tagged = book.weeks.filter { !$0.tag.isEmpty }
        if !tagged.isEmpty {
            out.append("Special weeks: " + tagged.sorted { $0.number < $1.number }.map { "week \($0.number) \($0.tag.lowercased()) (from \($0.monday))" }.joined(separator: "; "))
        }

        // Tests and zones
        out.append("")
        out.append("TESTS AND ZONES")
        if book.tests.isEmpty { out.append("No tests yet.") }
        for t in book.tests {
            var parts: [String] = []
            if let v = t.lthr { parts.append("threshold heart rate \(figure(v))") }
            if let v = t.ftp { parts.append("bike power \(figure(v)) W") }
            if let v = t.css { parts.append("swim pace \(figure(v))") }
            if let v = t.weight { parts.append("weight \(figure(v)) kg") }
            let line = t.label + ": " + (parts.isEmpty ? "not done yet" : parts.joined(separator: ", "))
            out.append(t.notes.isEmpty ? line : line + ". " + t.notes)
        }
        if let z = book.zones {
            let now = z.current.filter { !$0.value.isEmpty }
            if !now.isEmpty { out.append("In use now: " + now.map { "\($0.label) \($0.value)" }.joined(separator: ", ")) }
            for table in z.tables where !table.rows.isEmpty {
                out.append(table.title)
                for row in table.rows { out.append("  \(row.label): \(row.value)") }
            }
        }

        // The last 8 weeks
        out.append("")
        out.append("THE LAST 8 WEEKS (minutes done / planned, per sport)")
        for i in stride(from: 8, to: 0, by: -1) {
            let monday = PlanView.addDays(thisMonday, -7 * i)
            let days = Set((0..<7).map { PlanView.addDays(monday, $0) })
            let sessions = plan.filter { days.contains($0.dayKey) && $0.discipline.id != "rest" }
            var order: [String] = []
            var label: [String: String] = [:]
            var planned: [String: Double] = [:], done: [String: Double] = [:]
            var missed = 0, open = 0
            for w in sessions {
                let id = w.discipline.id
                if label[id] == nil { label[id] = w.discipline.label; order.append(id) }
                let p = (Plan.plannedSeconds(w, mapping) ?? 0) / 60
                planned[id, default: 0] += p
                if w.missed { missed += 1 }
                else if w.logged { done[id, default: 0] += Load.minutes(of: w, mapping) }
                else { open += 1 }
            }
            let weekInfo = book.weeks.first { $0.monday == monday }
            var head = "Week of \(monday)"
            if let weekInfo { head += " (week \(weekInfo.number), \(weekInfo.phase)\(weekInfo.tag.isEmpty ? "" : ", " + weekInfo.tag.lowercased()))" }
            out.append(head)
            if sessions.isEmpty { out.append("  nothing planned"); continue }
            for id in order { out.append("  \(label[id] ?? id): \(figure(done[id] ?? 0)) / \(figure(planned[id] ?? 0))") }
            out.append("  Total: \(figure(done.values.reduce(0, +))) / \(figure(planned.values.reduce(0, +)))"
                       + (missed > 0 ? ", \(missed) missed" : "") + (open > 0 ? ", \(open) not logged" : ""))
            let extras = book.extras.filter { days.contains($0.date) && $0.isTraining }
            if !extras.isEmpty {
                out.append("  Extras: " + extras.map { "\($0.label.isEmpty ? $0.activity : $0.label) \(figure($0.minutes ?? 0)) min" }.joined(separator: ", "))
            }
        }

        // The next 4 weeks
        out.append("")
        out.append("THE NEXT 4 WEEKS (from this week's Monday)")
        for i in 0..<4 {
            let monday = PlanView.addDays(thisMonday, 7 * i)
            let weekInfo = book.weeks.first { $0.monday == monday }
            var head = "Week of \(monday)"
            if let weekInfo { head += " (week \(weekInfo.number), \(weekInfo.phase)\(weekInfo.tag.isEmpty ? "" : ", " + weekInfo.tag.lowercased()))" }
            out.append(head)
            for d in 0..<7 {
                let day = PlanView.addDays(monday, d)
                let sessions = plan.filter { $0.dayKey == day && $0.discipline.id != "rest" }
                guard !sessions.isEmpty else { continue }
                let text = sessions.map { w -> String in
                    var s = w.discipline.label
                    if let p = Plan.plannedSeconds(w, mapping), p > 0 { s += " \(figure(p / 60)) min" }
                    if !w.planned.intensity.isEmpty { s += " " + w.planned.intensity }
                    if !w.title.isEmpty { s += ", " + w.title }
                    if w.logged && !w.missed { s += " (done)" } else if w.missed { s += " (missed)" }
                    return s
                }.joined(separator: "; ")
                out.append("  \(weekdays[d]) \(day): \(text)")
            }
        }
        out.append("")
        return out.joined(separator: "\n")
    }

    static func figure(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
