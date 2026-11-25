import SwiftUI
import WorkoutCore

/*
 * Round 28, Progress: the look the five new Progress cards share — Progress's
 * purple for the head card and the marks, lightly tinted tiles, slim round
 * bars, words and figures side by side. Only Progress uses these colours.
 */
enum ProgressLook {
    /* The head card's fill: white words stand on it by day and by night. */
    static let fill = Color.dynamic(light: 0x7C3AED, dark: 0x6D28D9)
    /* A tile, lightly tinted with Progress's purple. */
    static let tile = Color.dynamic(light: 0xF0E9FD, dark: 0x2B1D47)
}

/* A tile: its name in small capitals in purple, then what it holds. */
struct ProgTile<Content: View>: View {
    let name: String
    var id: String = ""
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased())
                .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.progress)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ProgressLook.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/* A figure right beside its unit. */
struct ProgFigure: View {
    let figure: String
    var unit: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(figure).font(.title2.weight(.bold))
            if !unit.isEmpty { Text(unit).font(.footnote.weight(.semibold)) }
        }
        .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
    }
}

struct ProgNote: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(Theme.secondary)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

/* A slim round bar: the planned length pale, the done part solid. */
struct ProgBar: View {
    let done: Double
    let planned: Double
    let colour: Color
    var body: some View {
        GeometryReader { geo in
            let top = max(planned, done, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(colour.opacity(0.22)).frame(width: geo.size.width * CGFloat(planned / top))
                if done > 0 { Capsule().fill(colour).frame(width: max(6, geo.size.width * CGFloat(done / top))) }
            }
        }
        .frame(height: 7)
    }
}

/* The cards on Progress, from the hook in ProgressView. Each draws nothing while it has nothing to say. */
struct ProgressRound28: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var diary = Diary.shared

    var body: some View {
        if let mapping = store.mapping {
            let plan = store.displayed
            MonthReviewCard(plan: plan, mapping: mapping, today: store.today, feel: diary.feel,
                            zones: store.zones, tests: store.tests)
            SteadyWeeksCard(plan: plan, today: store.today)
            PersonalBestsCard(plan: plan, mapping: mapping, today: store.today)
            TestHistoryCard(tests: store.tests)
        }
    }
}

#if DEBUG
/*
 * A picture of the new cards, DEBUG only: AMSWS_MONTH_REVIEW, AMSWS_BESTS,
 * AMSWS_TESTS_CARD, AMSWS_STEADY each show their card, AMSWS_REPORT the page
 * that says what is in the PDF. They use the plan that is open (the UI tests'
 * invented one, with AMSWS_FILE and AMSWS_TODAY); a month with no morning
 * answers and a store with no tests get invented ones.
 */
struct ProgressRound28Debug: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var diary = Diary.shared
    private let env = ProcessInfo.processInfo.environment

    var body: some View {
        if env["AMSWS_MONTH_REVIEW"] != nil || env["AMSWS_BESTS"] != nil || env["AMSWS_TESTS_CARD"] != nil
            || env["AMSWS_STEADY"] != nil || env["AMSWS_REPORT"] != nil, let mapping = store.mapping {
            let plan = store.displayed
            let tests = store.tests.isEmpty ? Self.sampleTests : store.tests
            ZStack {
                Theme.bg.ignoresSafeArea()
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if env["AMSWS_REPORT"] != nil {
                                MonthReportPage(month: MonthReview.months(plan, today: store.today, includingCurrent: true).last ?? PlanOverview.month(of: store.today),
                                                make: {}, cancel: {})
                            }
                            if env["AMSWS_MONTH_REVIEW"] != nil {
                                MonthReviewCard(plan: plan, mapping: mapping, today: store.today, feel: sampleFeel(plan),
                                                zones: store.zones, tests: tests, includingCurrent: true)
                            }
                            if env["AMSWS_STEADY"] != nil { SteadyWeeksCard(plan: plan, today: store.today, always: true) }
                            if env["AMSWS_BESTS"] != nil { PersonalBestsCard(plan: plan, mapping: mapping, today: store.today) }
                            if env["AMSWS_TESTS_CARD"] != nil { TestHistoryCard(tests: tests) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }

    static let sampleTests = [
        TestResult(name: "Test 1", week: "W1", dates: "14 Sep–16 Sep 2026", lthr: 160, ftp: 200, css: 112, weight: 72),
        TestResult(name: "Test 2", week: "W6", dates: "26 Oct–28 Oct 2026", lthr: 160, ftp: 212, css: 108, weight: 71),
        TestResult(name: "Test 3", week: "W11", dates: "30 Nov–02 Dec 2026", lthr: 160, ftp: 212, css: 108, weight: 71)
    ]

    /* The month's mornings, invented, when none was answered. */
    private func sampleFeel(_ plan: [Workout]) -> FeelLog {
        guard diary.feel.days.isEmpty, let month = MonthReview.months(plan, today: store.today, includingCurrent: true).last else { return diary.feel }
        var log = FeelLog()
        let words: [Feel] = [.good, .ok, .good, .tired, .great, .good, .ok, .bad, .good, .ok]
        for (i, f) in words.enumerated() { log.set(f, on: PlanView.addDays(PlanOverview.firstDay(month), i + 8)) }
        return log
    }
}
#endif
