import SwiftUI
import WorkoutCore

/*
 * The Load card on Progress, beside Fitness and freshness.
 *
 * Load is minutes times how hard it was (1 to 10), for everything: the
 * plan's sessions, the extra workouts, and what the watch sent to Apple
 * Health that is in neither — the hikes and gym sessions the plan never
 * counted. It shows the weeks and says how it was worked out; it gives no
 * advice and draws no warning.
 */
struct LoadBoard {
    let weeks: [Load.Week]
    let usual: Double?
    /* Activities in the weeks drawn, and how many of them carry no number of his own. */
    let counted: Int
    let unanswered: Int
    /* Health workouts of the last fortnight, outside the plan, still without a number. */
    let toScore: [Load.Found]
    /* The last fourteen mornings, oldest first. */
    let mornings: [Feel?]

    @MainActor
    static func make(store: Store, diary: Diary) -> LoadBoard? {
        guard let mapping = store.mapping else { return nil }
        let today = store.today
        let plan = store.displayed
        let extras = store.allExtras
        let outside = Load.outside(diary.found, recorded: Load.recorded(plan, extras: extras, mapping: mapping))
        let items = Load.items(plan, extras: extras, mapping: mapping, outside: outside, answers: diary.answers)
        let starts = Stats.recentWeekStarts(Diary.weeks, today: today)
        guard let first = starts.first else { return nil }
        let shown = items.filter { $0.dayKey >= first && $0.dayKey < PlanView.addDays(PlanView.weekStart(today), 7) }
        let since = PlanView.addDays(today, -13)
        return LoadBoard(
            weeks: Load.weeks(items, starts: starts),
            usual: Load.usual(Load.weeks(items, starts: starts), firstDay: items.map(\.dayKey).min()),
            counted: shown.count,
            unanswered: shown.filter { $0.score.source != .answered }.count,
            toScore: outside.filter { $0.dayKey >= since && $0.dayKey <= today && diary.answers[$0.id] == nil }
                .sorted { $0.dayKey > $1.dayKey },
            mornings: diary.feel.last(14, endingOn: today))
    }
}

struct LoadCard: View {
    let board: LoadBoard
    @ObservedObject private var diary = Diary.shared
    /* The Health workout whose row of numbers is open. */
    @State private var asking: String?

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_GB")
        f.maximumFractionDigits = 0
        return f
    }()

    private func figure(_ n: Double?) -> String {
        guard let n else { return "—" }
        return Self.number.string(from: NSNumber(value: n.rounded())) ?? "\(Int(n.rounded()))"
    }

    var body: some View {
        let weeks = board.weeks
        let tallest = max(weeks.map(\.total).max() ?? 0, 1)
        StatCard(title: "Load") {
            HStack(alignment: .top, spacing: 10) {
                Figure(value: figure(weeks.last?.total), label: "this week so far")
                    .accessibilityIdentifier("load-this-week")
                Figure(value: figure(weeks.dropLast().last?.total), label: "last week")
                Figure(value: figure(board.usual), label: "usual week")
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { i, week in
                    VStack(spacing: 4) {
                        VStack(spacing: 2) {
                            Spacer(minLength: 0)
                            if week.total <= 0 {
                                RoundedRectangle(cornerRadius: 1).fill(Theme.border).frame(height: 2)
                            }
                            if week.outside > 0 {
                                DottedBlock(colour: Theme.progress)
                                    .frame(height: max(5, 96 * week.outside / tallest))
                            }
                            if week.inPlan > 0 {
                                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.progress)
                                    .frame(height: max(5, 96 * week.inPlan / tallest))
                            }
                        }
                        .frame(height: 104)
                        Text(label(i, week.start, last: i == weeks.count - 1))
                            .font(.caption2).foregroundStyle(Theme.secondary)
                            .lineLimit(1).fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("load-bars")
            .accessibilityLabel("Load, the last eight weeks: " + weeks.map { figure($0.total) }.joined(separator: ", "))

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.progress).frame(width: 14, height: 10)
                    Text("In the plan").font(.caption).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 6) {
                    DottedBlock(colour: Theme.progress).frame(width: 14, height: 10)
                    Text("Outside the plan (hikes, gym)").font(.caption).foregroundStyle(Theme.secondary)
                }
            }

            Text(explanation)
                .font(.caption).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !board.toScore.isEmpty {
                Divider()
                ForEach(board.toScore.prefix(3)) { f in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("\(Dates.short(f.dayKey)) · \(f.name) · \(formatDuration(f.minutes * 60))")
                                .font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 0)
                            if asking != f.id {
                                Button("How hard?") { withAnimation(.easeInOut(duration: 0.15)) { asking = f.id } }
                                    .settingsButton(tint: Theme.progress)
                                    .accessibilityIdentifier("load-how-hard")
                            }
                        }
                        if asking == f.id {
                            EffortRow(tint: Theme.progress, idPrefix: "load-effort") { n in
                                diary.setAnswer(n, for: f.id)
                                asking = nil
                            }
                        }
                    }
                }
                if board.toScore.count > 3 {
                    Text("and \(board.toScore.count - 3) more from the last two weeks")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }

            if board.mornings.contains(where: { $0 != nil }) {
                Divider()
                HStack(alignment: .bottom, spacing: 10) {
                    Text("Mornings").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(board.mornings.enumerated()), id: \.offset) { _, feel in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(feel == nil ? Theme.border : Theme.progress)
                                .frame(width: 8, height: feel.map { CGFloat($0.rawValue) * 4 + 2 } ?? 2)
                        }
                    }
                    .frame(height: 22, alignment: .bottom)
                    Spacer(minLength: 0)
                    Text("taller = felt better").font(.caption2).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("load-mornings")
                .accessibilityLabel("How you felt, the last fourteen mornings: "
                                    + board.mornings.map { $0?.word ?? "not answered" }.joined(separator: ", "))
            }
        }
    }

    private var explanation: String {
        var text = "Load = minutes × how hard (1–10). A 60-minute run at 5 counts 300. Hikes and gym sessions come from Apple Health."
        if board.unanswered > 0 {
            text += " \(board.unanswered) of \(board.counted) had no number from you: counted from the plan's zone, or as 3 (easy)."
        }
        return text
    }

    /* The Monday a week starts on: day and month for the first bar and each new month, the day alone between, "now" last. */
    private func label(_ i: Int, _ start: String, last: Bool) -> String {
        if last { return "now" }
        guard let date = parseDayKey(start) else { return "" }
        let day = utc.component(.day, from: date)
        return i == 0 || day <= 7 ? Dates.formatter("dMMM").string(from: date) : "\(day)"
    }
}

/* Dotted means outside the plan, here as in the week strip on Today. */
struct DottedBlock: View {
    let colour: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(colour.opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                .foregroundStyle(colour))
    }
}
