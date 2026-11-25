import SwiftUI
import UIKit
import WorkoutCore

/*
 * Print the week or the month (round 28, pick 22).
 *
 * "Print" opens a preview of one A4 page — a week lies on the page with a
 * column per day, a month stands on it as a calendar — in black on white, the
 * sports only as small coloured bars (every session says its sport in words,
 * so it reads on a black-and-white printer too). From the preview: Print (the
 * system's own print panel), Save as PDF (the share sheet) or Cancel.
 *
 * The page is a SwiftUI view with a fixed paper size; it is drawn to a PDF
 * and the PDF is what is printed or saved. Its text sizes are fixed points on
 * purpose: paper does not grow with the phone's text size.
 */

enum PrintKind: String, CaseIterable, Identifiable {
    case thisWeek = "this-week", nextWeek = "next-week", thisMonth = "this-month"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thisWeek: return "This week"
        case .nextWeek: return "Next week"
        case .thisMonth: return "This month"
        }
    }
    var isMonth: Bool { self == .thisMonth }
    /* A4 in points: a week lies down, a month stands up. */
    var pageSize: CGSize { isMonth ? CGSize(width: 595, height: 842) : CGSize(width: 842, height: 595) }
}

/* One session on the page, as words. */
struct PrintItem: Identifiable {
    let id: String
    let sportId: String
    let sport: String
    let title: String
    let seconds: Double
    let zone: String
}

struct PrintDay: Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let inMonth: Bool
    let items: [PrintItem]
}

struct PrintSheetData {
    let kind: PrintKind
    let heading: String
    /* Rows of seven days: one row for a week, five or six for a month. */
    let rows: [[PrintDay]]
    let totalSeconds: Double
    let sessionCount: Int
    let bySport: [(sport: String, seconds: Double)]

    static func make(_ kind: PrintKind, view: PlanView, today: String) -> PrintSheetData {
        let monday = PlanView.weekStart(today)
        let month = PlanOverview.month(of: today)
        let dayRows: [[String]]
        let heading: String
        let from: String, to: String
        switch kind {
        case .thisWeek, .nextWeek:
            let start = kind == .thisWeek ? monday : PlanView.addDays(monday, 7)
            dayRows = [(0..<7).map { PlanView.addDays(start, $0) }]
            from = start; to = PlanView.addDays(start, 6)
            heading = Dates.short(from) + " \u{2013} " + Dates.short(to) + " " + String(to.prefix(4))
        case .thisMonth:
            dayRows = PlanOverview.grid(month)
            from = PlanOverview.firstDay(month); to = PlanOverview.lastDay(month)
            heading = MonthGrid.title(month)
        }
        let rows = dayRows.map { row in
            row.map { day in
                PrintDay(dayKey: day, inMonth: kind != .thisMonth || PlanOverview.month(of: day) == month, items: items(on: day, view))
            }
        }
        var seconds = 0.0, count = 0
        var per: [String: Double] = [:]
        for day in rows.flatMap({ $0 }) where day.dayKey >= from && day.dayKey <= to {
            for item in day.items { seconds += item.seconds; count += 1; per[item.sport, default: 0] += item.seconds }
        }
        let order = ["Swim", "Bike", "Run", "Strength", "Mobility"]
        let sports = per.keys.sorted {
            let a = order.firstIndex(of: $0) ?? order.count, b = order.firstIndex(of: $1) ?? order.count
            return a != b ? a < b : $0 < $1
        }.map { (sport: $0, seconds: per[$0] ?? 0) }
        return PrintSheetData(kind: kind, heading: heading, rows: rows, totalSeconds: seconds, sessionCount: count, bySport: sports)
    }

    private static func items(on day: String, _ view: PlanView) -> [PrintItem] {
        view.forDay(day).filter { $0.discipline.id != "rest" }.map { w in
            let zone = w.planned.intensity.trimmingCharacters(in: .whitespaces)
            return PrintItem(id: w.key, sportId: w.discipline.id, sport: w.discipline.label, title: w.title,
                             seconds: Plan.plannedSeconds(w, view.mapping) ?? 0,
                             zone: ["", "-", "\u{2013}", "\u{2014}"].contains(zone) ? "" : zone)
        }
    }
}

// MARK: the paper

/* Black on white, always: it is paper, whatever the phone's look. */
struct PrintPage: View {
    let data: PrintSheetData

    private let ink = Color.black
    private let faint = Color(white: 0.4)
    private let line = Color(white: 0.55)

    var body: some View {
        let size = data.kind.pageSize
        VStack(alignment: .leading, spacing: 8) {
            header
            if data.kind.isMonth { monthGrid } else { weekColumns }
            totals
        }
        .padding(28)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(data.heading).font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
            Spacer()
            Text(data.kind.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(faint)
        }
    }

    private func bar(_ item: PrintItem, height: CGFloat) -> some View {
        Rectangle().fill(Theme.sport(item.sportId)).frame(width: 4, height: height)
            .overlay(Rectangle().strokeBorder(ink.opacity(0.5), lineWidth: 0.5))
    }

    private func words(_ item: PrintItem) -> String {
        [item.seconds > 0 ? formatDuration(item.seconds) : "", item.zone].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    // A week: a column per day.
    private var weekColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(data.rows.first ?? []) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Dates.short(day.dayKey)).font(.system(size: 10, weight: .bold)).foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(ink).frame(height: 1)
                    if day.items.isEmpty {
                        Text("Rest").font(.system(size: 9)).foregroundStyle(faint)
                    }
                    ForEach(day.items) { item in
                        HStack(alignment: .top, spacing: 4) {
                            bar(item, height: 46)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.sport.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(ink)
                                Text(item.title).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(words(item)).font(.system(size: 8.5)).foregroundStyle(faint)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5).padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(Rectangle().strokeBorder(line, lineWidth: 0.5))
            }
        }
        .frame(maxHeight: .infinity)
    }

    // A month: a calendar grid.
    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { d in
                    Text(d).font(.system(size: 9, weight: .bold)).foregroundStyle(ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .overlay(Rectangle().strokeBorder(line, lineWidth: 0.5))
                }
            }
            ForEach(data.rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(data.rows[r]) { day in monthCell(day) }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func monthCell(_ day: PrintDay) -> some View {
        let shown = Array(day.items.prefix(4))
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(Int(day.dayKey.suffix(2)) ?? 0)).font(.system(size: 9, weight: .bold))
                .foregroundStyle(day.inMonth ? ink : faint.opacity(0.6))
            if day.inMonth {
                ForEach(shown) { item in
                    HStack(alignment: .top, spacing: 2) {
                        bar(item, height: 17)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.sport + (item.seconds > 0 ? " " + formatDuration(item.seconds) : ""))
                                .font(.system(size: 7, weight: .bold)).foregroundStyle(ink).lineLimit(1)
                            Text([item.title, item.zone].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                .font(.system(size: 6.5)).foregroundStyle(faint).lineLimit(1)
                        }
                    }
                }
                if day.items.count > shown.count {
                    Text("+\(day.items.count - shown.count) more").font(.system(size: 6.5, weight: .semibold)).foregroundStyle(faint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(Rectangle().strokeBorder(line, lineWidth: 0.5))
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(ink).frame(height: 1)
            HStack(spacing: 14) {
                Text("Total \(formatDuration(data.totalSeconds)) \u{00B7} \(data.sessionCount) sessions")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(ink)
                ForEach(data.bySport, id: \.sport) { s in
                    Text("\(s.sport) \(formatDuration(s.seconds))").font(.system(size: 9)).foregroundStyle(faint)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: the button and the preview

/* The word "Print", on the wide Plan page and on the Sessions page. */
struct PlanPrintButton: View {
    @EnvironmentObject var store: Store
    @State private var open: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_PRINT"] != nil
        #else
        return false
        #endif
    }()

    var body: some View {
        Button("Print") { open = true }
            .settingsButton(tint: Theme.plan)
            .accessibilityIdentifier("plan-print")
            .sheet(isPresented: $open) { PlanPrintSheet().environmentObject(store) }
    }
}

struct PlanPrintSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PrintKind = {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["AMSWS_PRINT"] {
        case "month": return .thisMonth
        case "next": return .nextWeek
        default: break
        }
        #endif
        return .thisWeek
    }()
    @State private var payload: SharePayload?

    private var data: PrintSheetData? {
        store.view.map { PrintSheetData.make(kind, view: $0, today: store.today) }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Print the plan").font(.title3.weight(.bold)).foregroundStyle(Theme.plan)
            HStack(spacing: 6) {
                ForEach(PrintKind.allCases) { k in
                    let on = k == kind
                    Button { kind = k } label: {
                        Text(k.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .foregroundStyle(on ? Color.white : Theme.plan)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(Capsule().fill(on ? Theme.plan : Theme.plan.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("print-choice-\(k.rawValue)")
                }
            }
            GeometryReader { geo in
                if let data {
                    let size = data.kind.pageSize
                    let scale = min(geo.size.width / size.width, geo.size.height / size.height)
                    PrintPage(data: data)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("print-preview")
                        .accessibilityLabel("Preview: \(data.heading), \(data.sessionCount) sessions")
                }
            }
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .settingsButton(tint: Theme.secondary)
                    .accessibilityIdentifier("print-cancel")
                Spacer(minLength: 0)
                Button("Save as PDF") { savePDF() }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("print-save")
                Button("Print") { printIt() }
                    .mainSmallButton()
                    .accessibilityIdentifier("print-do")
            }
        }
        .padding(16)
        .background(Theme.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("print-sheet")
        .sheet(item: $payload) { p in ActivitySheet(items: p.items) }
    }

    // MARK: the PDF

    @MainActor private func makePDF() -> URL? {
        guard let data else { return nil }
        let size = data.kind.pageSize
        let renderer = ImageRenderer(content: PrintPage(data: data))
        let name = "Training plan \(data.heading).pdf".replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var written = false
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            written = true
        }
        return written ? url : nil
    }

    private func savePDF() {
        if let url = makePDF() { payload = SharePayload(items: [url]) }
    }

    private func printIt() {
        guard let url = makePDF(), let data else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Training plan \(data.heading)"
        info.orientation = data.kind.isMonth ? .portrait : .landscape
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true, completionHandler: nil)
    }
}
