import SwiftUI
import UIKit
import WorkoutCore

/*
 * Report as PDF (his pick 38, round 28): a one-to-two-page A4 PDF of one
 * month for a coach or his doctor. First a short page says exactly what is in
 * it, with Cancel and "Make the PDF"; then the PDF is made on this device from
 * SwiftUI pages and handed to the system share sheet (on the Mac it can be
 * saved). The app itself sends nothing anywhere.
 */
struct MonthReportPage: View {
    let month: String
    let make: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report as PDF").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.progress)
            Text("\(MonthReview.name(month)) · one or two A4 pages").font(.subheadline).foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("IN THE REPORT").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.progress)
                ForEach(Array(MonthReport.contents.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ProgressLook.tile))
            Text("The PDF is made on this device. You choose where it goes: the app sends it nowhere itself.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
            Button(action: make) {
                Text("Make the PDF").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ProgressLook.fill))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("report-make")
            Button(action: cancel) {
                Text("Cancel").font(.headline).foregroundStyle(Theme.progress)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("report-cancel")
        }
        .padding(16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report-page")
    }
}

/* Makes the PDF file; nil when it could not be written. */
@MainActor
enum MonthReportMaker {
    static let page = CGSize(width: 595, height: 842)   // A4 in points
    static let linesPerPage = 40

    static func make(plan: [Workout], mapping: Mapping, month: String, today: String, feel: FeelLog,
                     zones: Zones?, tests: [TestResult]) -> URL? {
        let facts = MonthReview.facts(plan, mapping, month: month, today: today, feel: feel)
        let weeks = MonthReport.weeks(plan, mapping, month: month)
        let lines = MonthReport.lines(plan, mapping, month: month)
        let days = MonthReport.feelDays(feel, month: month)
        let chunks = stride(from: 0, to: max(lines.count, 1), by: linesPerPage).map { Array(lines[$0..<min($0 + linesPerPage, lines.count)]) }

        var pages: [AnyView] = [AnyView(ReportPageOne(facts: facts, weeks: weeks, tests: tests, zones: zones, today: today))]
        for (i, chunk) in chunks.enumerated() {
            pages.append(AnyView(ReportPageTwo(month: month, days: i == 0 ? days : [], lines: chunk, first: i == 0)))
        }

        let name = "Training report \(MonthReview.name(month)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for view in pages {
            let renderer = ImageRenderer(content: view.frame(width: page.width, height: page.height, alignment: .topLeading)
                .environment(\.colorScheme, .light))
            renderer.proposedSize = ProposedViewSize(page)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - the pages (paper: fixed light colours)

private enum Paper {
    static let ink = Color(hex: 0x1B1B1F)
    static let grey = Color(hex: 0x6B6B73)
    static let purple = Color(hex: 0x6D28D9)
    static let rule = Color(hex: 0xD9D4E6)
}

private struct ReportHead: View {
    let title: String
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AMS Triathlon Training · training report").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Paper.purple)
            Text(title).font(.title2.weight(.bold)).foregroundStyle(Paper.ink)
            if !line.isEmpty { Text(line).font(.caption).foregroundStyle(Paper.grey) }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Paper.purple)
            .padding(.top, 8).padding(.bottom, 2)
    }
}

private struct ReportPageOne: View {
    let facts: MonthReview.Facts
    let weeks: [MonthReport.WeekRow]
    let tests: [TestResult]
    let zones: Zones?
    let today: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ReportHead(title: MonthReview.name(facts.month),
                       line: MonthReview.closing(facts, day: Dates.short))
            SectionTitle("The month")
            HStack(alignment: .top, spacing: 18) {
                fact("Hours done", formatDuration(facts.hours.done), "of \(formatDuration(facts.hours.planned)) planned")
                fact("Sessions done", "\(facts.sessionsDone)", "of \(facts.sessionsPlanned) planned")
                fact("Plan followed", facts.followed.percent.map { "\($0) %" } ?? "—", "\(facts.followed.done) of \(facts.followed.due) due")
                fact("Longest session", facts.longest.map { formatDuration($0.seconds) } ?? "—",
                     facts.longest.map { "\($0.sport), \(Dates.short($0.dayKey))" } ?? "")
            }
            if !facts.sports.isEmpty {
                SectionTitle("Hours per sport")
                ForEach(facts.sports) { s in
                    HStack(spacing: 6) {
                        Text(s.label).frame(width: 80, alignment: .leading)
                        Text("\(formatDuration(s.hours.done)) of \(formatDuration(s.hours.planned))").foregroundStyle(Paper.grey)
                    }.font(.caption).foregroundStyle(Paper.ink)
                }
            }
            SectionTitle("Week by week · done of planned")
            weekTable
            SectionTitle("Tests")
            testTable
            zonesBlock
            Spacer(minLength: 0)
            Text("Made by AMS Triathlon Training on \(Dates.short(today)). Worked out from the sessions logged in the app.")
                .font(.caption2).foregroundStyle(Paper.grey)
        }
        .padding(.horizontal, 32).padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private func fact(_ name: String, _ figure: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.caption2).foregroundStyle(Paper.grey)
            Text(figure).font(.headline).foregroundStyle(Paper.ink)
            Text(line).font(.caption2).foregroundStyle(Paper.grey)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sportIds: [String] {
        var seen: [String] = []
        for w in weeks { for s in w.sports where !seen.contains(s.sport) { seen.append(s.sport) } }
        return seen.sorted { Disciplines.order($0) < Disciplines.order($1) }
    }

    private var weekTable: some View {
        let ids = sportIds
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("Week").frame(width: 92, alignment: .leading)
                ForEach(ids, id: \.self) { id in
                    Text(Disciplines.five.first { $0.id == id }?.label ?? id.capitalized).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("All").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2.weight(.bold)).foregroundStyle(Paper.grey)
            Rectangle().fill(Paper.rule).frame(height: 1)
            ForEach(weeks) { w in
                HStack(spacing: 4) {
                    Text("\(Dates.short(w.start).dropFirst(4)) – \(Dates.short(w.end).dropFirst(4))").frame(width: 92, alignment: .leading)
                    ForEach(ids, id: \.self) { id in
                        let h = w.sports.first { $0.sport == id }?.hours
                        hoursCell(h)
                    }
                    hoursCell(w.hours)
                }
                .font(.caption2).foregroundStyle(Paper.ink).lineLimit(1)
            }
        }
    }

    /* "1h 43m" with "of 1h 50m" in grey under it: two short lines instead of one long one that has to shrink. */
    private func hoursCell(_ h: PlanOverview.Hours?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let h, h.planned > 0 || h.done > 0 {
                Text(formatDuration(h.done))
                Text("of \(formatDuration(h.planned))").foregroundStyle(Paper.grey)
            } else {
                Text("—")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var testTable: some View {
        VStack(alignment: .leading, spacing: 2) {
            if tests.filter(\.hasNumbers).isEmpty {
                Text("No test has been entered.").font(.caption).foregroundStyle(Paper.grey)
            } else {
                HStack(spacing: 4) {
                    Text("Test").frame(width: 70, alignment: .leading)
                    Text("Days").frame(width: 130, alignment: .leading)
                    Text("Pulse").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Bike power").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Swim /100 m").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption2.weight(.bold)).foregroundStyle(Paper.grey)
                ForEach(tests.filter(\.hasNumbers)) { t in
                    HStack(spacing: 4) {
                        Text(t.name).frame(width: 70, alignment: .leading)
                        Text(t.dates.isEmpty ? "—" : t.dates).frame(width: 130, alignment: .leading)
                        Text(t.lthr.map { "\(jsNumberString($0.rounded())) bpm" } ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                        Text(t.ftp.map { "\(jsNumberString($0.rounded())) W" } ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                        Text(t.css.map(TestEntry.swimText) ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption2).foregroundStyle(Paper.ink).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
    }

    @ViewBuilder private var zonesBlock: some View {
        if let z = zones, !z.tables.isEmpty {
            SectionTitle("Zones in use")
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(z.tables.enumerated()), id: \.offset) { _, table in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(table.title).font(.caption2.weight(.bold)).foregroundStyle(Paper.ink)
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 4) {
                                Text(row.label).foregroundStyle(Paper.ink)
                                Text(row.value).foregroundStyle(Paper.grey)
                            }
                            .font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

private struct ReportPageTwo: View {
    let month: String
    let days: [(day: String, feel: Feel?)]
    let lines: [MonthReport.Line]
    let first: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ReportHead(title: MonthReview.name(month), line: first ? "How you felt, and the sessions" : "The sessions, continued")
            if first && !days.isEmpty {
                SectionTitle("How you felt each morning")
                let third = (days.count + 2) / 3
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<3, id: \.self) { c in
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(days.dropFirst(c * third).prefix(third)), id: \.day) { d in
                                HStack(spacing: 6) {
                                    Text(Dates.short(d.day)).foregroundStyle(Paper.grey).frame(width: 66, alignment: .leading)
                                    Text(d.feel?.word ?? "—").foregroundStyle(Paper.ink)
                                }
                                .font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            SectionTitle("Sessions")
            HStack(spacing: 4) {
                Text("Day").frame(width: 76, alignment: .leading)
                Text("Sport").frame(width: 50, alignment: .leading)
                Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                Text("Planned").frame(width: 56, alignment: .leading)
                Text("Done").frame(width: 56, alignment: .leading)
                Text("Hard 1–10").frame(width: 56, alignment: .leading)
            }
            .font(.caption2.weight(.bold)).foregroundStyle(Paper.grey)
            Rectangle().fill(Paper.rule).frame(height: 1)
            ForEach(lines) { l in
                HStack(spacing: 4) {
                    Text(Dates.short(l.dayKey)).frame(width: 76, alignment: .leading)
                    Text(l.sport).frame(width: 50, alignment: .leading)
                    Text(l.title.isEmpty ? "—" : l.title).frame(maxWidth: .infinity, alignment: .leading)
                    Text(l.planned.map(formatDuration) ?? "—").frame(width: 56, alignment: .leading)
                    Text(l.missed ? "Missed" : (l.done.map(formatDuration) ?? "—")).frame(width: 56, alignment: .leading)
                    Text(l.hard.map { "\($0)" } ?? "—").frame(width: 56, alignment: .leading)
                }
                .font(.caption2).foregroundStyle(Paper.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}
