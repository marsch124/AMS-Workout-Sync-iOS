import SwiftUI
import WorkoutCore

/*
 * Month in review (his pick 32, round 28): a card on Progress for the month
 * that has just ended, shown from the 1st, and any earlier month through
 * "Earlier months". Hours and sessions done of planned, the hours per sport,
 * the longest session, plan followed (the same figure the Plan page shows),
 * and how he felt as a count per word. Worked out each time; nothing stored.
 */
struct MonthReviewCard: View {
    let plan: [Workout]
    let mapping: Mapping
    let today: String
    let feel: FeelLog
    let zones: Zones?
    let tests: [TestResult]
    var includingCurrent = false

    @State private var chosen: String?
    @State private var listing = false
    @State private var asking = false
    @State private var sharing: SharePayload?

    var body: some View {
        let months = MonthReview.months(plan, today: today, includingCurrent: includingCurrent)
        if let newest = months.last {
            let month = (chosen.flatMap { months.contains($0) ? $0 : nil }) ?? newest
            let f = MonthReview.facts(plan, mapping, month: month, today: today, feel: feel)
            VStack(alignment: .leading, spacing: 8) {
                head(f, newest: month == newest)
                ProgTileGrid {
                    ProgTile(name: "Hours", id: "month-hours") {
                        ProgFigure(figure: formatDuration(f.hours.done))
                        ProgNote(text: "done of \(formatDuration(f.hours.planned)) planned")
                    }
                    ProgTile(name: "Sessions", id: "month-sessions") {
                        ProgFigure(figure: "\(f.sessionsDone)")
                        ProgNote(text: "done of \(f.sessionsPlanned) planned")
                    }
                    ProgTile(name: "Plan followed", id: "month-followed") {
                        ProgFigure(figure: f.followed.percent.map { "\($0)" } ?? "—", unit: f.followed.percent == nil ? "" : "%")
                        ProgNote(text: "\(f.followed.done) of \(f.followed.due) sessions, as on the Plan page")
                    }
                    ProgTile(name: "Longest session", id: "month-longest") {
                        if let l = f.longest {
                            ProgFigure(figure: formatDuration(l.seconds))
                            ProgNote(text: "\(l.sport) · \(Dates.short(l.dayKey))")
                        } else {
                            ProgFigure(figure: "—")
                            ProgNote(text: "Nothing recorded")
                        }
                    }
                }
                if !f.sports.isEmpty { sports(f) }
                felt(f)
                Text(MonthReview.closing(f, day: Dates.short))
                    .font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("month-closing")
                actions(months: months, month: month, newest: newest)
                if listing { earlier(months: months, month: month) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("month-review")
            .sheet(isPresented: $asking) {
                MonthReportPage(month: month, make: {
                    asking = false
                    let url = MonthReportMaker.make(plan: plan, mapping: mapping, month: month, today: today, feel: feel,
                                                    zones: zones, tests: tests)
                    if let url { sharing = SharePayload(items: [url]) }
                }, cancel: { asking = false })
            }
            .sheet(item: $sharing) { p in ActivitySheet(items: p.items) }
        }
    }

    private func head(_ f: MonthReview.Facts, newest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(newest ? "MONTH IN REVIEW" : "AN EARLIER MONTH").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            Text(MonthReview.name(f.month)).font(.largeTitle.weight(.bold))
                .accessibilityIdentifier("month-review-title")
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ProgressLook.fill))
    }

    /* Hours per sport: its name and figure side by side, a slim bar under. */
    private func sports(_ f: MonthReview.Facts) -> some View {
        ProgTile(name: "Hours per sport", id: "month-sports") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(f.sports) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(s.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("\(formatDuration(s.hours.done)) of \(formatDuration(s.hours.planned))")
                                .font(.footnote).foregroundStyle(Theme.secondary)
                            Spacer(minLength: 0)
                        }
                        ProgBar(done: s.hours.done, planned: s.hours.planned, colour: Theme.sport(s.sport))
                    }
                }
            }
            .padding(.top, 3)
        }
    }

    /* How he felt: each of the five words with how many mornings it was. Counted, never scored. */
    private func felt(_ f: MonthReview.Facts) -> some View {
        ProgTile(name: "How you felt", id: "month-felt") {
            if f.feelAnswered == 0 {
                ProgNote(text: "No morning answers this month")
            } else {
                HStack(spacing: 12) {
                    ForEach(f.feelings, id: \.feel) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(c.feel.word).font(.subheadline).foregroundStyle(Theme.text)
                            Text("\(c.count)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                ProgNote(text: "mornings answered, by word")
            }
        }
    }

    private func actions(months: [String], month: String, newest: String) -> some View {
        HStack(spacing: 10) {
            Button { asking = true } label: {
                HStack(spacing: 6) {
                    Text("Report as PDF").font(.headline)
                    Glyph(name: "icon-share", size: 20)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ProgressLook.fill))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("report-pdf")
            if months.count > 1 {
                Button { withAnimation(.easeInOut(duration: 0.2)) { listing.toggle() } } label: {
                    Text(listing ? "Hide months" : "Earlier months").font(.headline).foregroundStyle(Theme.progress)
                        .frame(minHeight: 44).padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("month-review-earlier")
            }
        }
    }

    private func earlier(months: [String], month: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(months.reversed()), id: \.self) { m in
                Button { chosen = m; withAnimation { listing = false } } label: {
                    HStack {
                        Text(MonthReview.name(m)).font(.body.weight(m == month ? .bold : .regular)).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("month-review-earlier-\(m)")
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ProgressLook.tile))
    }
}
