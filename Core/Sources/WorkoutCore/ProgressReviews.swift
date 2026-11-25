import Foundation

/*
 * Round 28, the Progress lane: a month looked back on, the personal bests,
 * the history of the tests, the weeks in a row with the plan followed, and the
 * facts of the month report. All of it worked out from what the app already
 * holds (the plan with what was logged, the tests, how he felt each morning);
 * nothing is stored and nothing is judged. "Plan followed" is always
 * PlanOverview.followed, the figure the Plan page shows, so the numbers agree.
 */

// MARK: - 32 Month in review

public enum MonthReview {

    public struct Longest: Equatable {
        public let key: String, dayKey: String, sport: String, title: String, seconds: Double
    }

    public struct FeelCount: Equatable {
        public let feel: Feel
        public let count: Int
    }

    public struct Facts: Equatable {
        public let month: String
        public let hours: PlanOverview.Hours
        public let sessionsPlanned: Int
        public let sessionsDone: Int
        public let sports: [PlanOverview.SportHours]
        public let longest: Longest?
        public let followed: PlanOverview.Followed
        /* All five words, in order, with how many mornings each was the answer. */
        public let feelings: [FeelCount]
        public var feelAnswered: Int { feelings.reduce(0) { $0 + $1.count } }
    }

    /*
     * The months that are over, oldest first: from the month of the first
     * session in the plan to the month before today's. `includingCurrent`
     * adds today's month (for a picture only).
     */
    public static func months(_ plan: [Workout], today: String, includingCurrent: Bool = false) -> [String] {
        guard let first = plan.filter({ $0.discipline.id != "rest" && !$0.dayKey.isEmpty }).map(\.dayKey).min() else { return [] }
        let last = includingCurrent ? PlanOverview.month(of: today) : PlanOverview.adding(-1, to: PlanOverview.month(of: today))
        guard PlanOverview.month(of: first) <= last else { return [] }
        return PlanOverview.months(from: first, to: PlanOverview.firstDay(last))
    }

    /* Done = recorded and not missed; a rest day is no session. */
    static func isDone(_ w: Workout) -> Bool { w.logged && !w.missed }

    public static func seconds(_ w: Workout, _ mapping: Mapping) -> Double {
        Stats.actualSeconds(w, mapping) ?? Plan.plannedSeconds(w, mapping) ?? 0
    }

    public static func facts(_ plan: [Workout], _ mapping: Mapping, month: String, today: String, feel: FeelLog) -> Facts {
        let from = PlanOverview.firstDay(month), to = PlanOverview.lastDay(month)
        let inMonth = plan.filter { $0.dayKey >= from && $0.dayKey <= to && $0.discipline.id != "rest" }
        var longest: Longest?
        for w in inMonth where isDone(w) {
            let s = seconds(w, mapping)
            if s > (longest?.seconds ?? 0) {
                longest = Longest(key: w.key, dayKey: w.dayKey, sport: w.discipline.label, title: w.title, seconds: s)
            }
        }
        let feelings = Feel.allCases.map { f in
            FeelCount(feel: f, count: feel.days.filter { $0.key >= from && $0.key <= to && $0.value == f.rawValue }.count)
        }
        return Facts(month: month,
                     hours: PlanOverview.hours(plan, mapping, from: from, to: to),
                     sessionsPlanned: inMonth.count, sessionsDone: inMonth.filter(isDone).count,
                     sports: PlanOverview.bySport(plan, mapping, from: from, to: to),
                     longest: longest,
                     followed: PlanOverview.followed(plan, from: from, to: to, today: today),
                     feelings: feelings)
    }

    /* "November 2026" for "2026-11". */
    public static func name(_ month: String) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let p = month.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2, (1...12).contains(p[1]) else { return month }
        return "\(names[p[1] - 1]) \(p[0])"
    }

    /* One closing line of facts: no praise, no exclamation mark. `day` writes a day key as the app writes days. */
    public static func closing(_ f: Facts, day: (String) -> String) -> String {
        var line = "\(f.sessionsDone) of \(f.sessionsPlanned) sessions done, \(formatDuration(f.hours.done)) of \(formatDuration(f.hours.planned)) planned."
        if let l = f.longest { line += " Longest: \(l.sport), \(day(l.dayKey)), \(formatDuration(l.seconds))." }
        return line
    }
}

// MARK: - 36 Steady weeks

public enum SteadyWeeks {
    /* A week counts as followed from this whole per cent of "Plan followed" up. */
    public static let threshold = 90

    public struct Square: Equatable, Identifiable {
        public var id: String { start }
        public let start: String
        public let followed: Bool
        public let isNow: Bool
    }

    /* True or false once something was due in the week; nil while nothing was. */
    public static func weekFollowed(_ plan: [Workout], start: String, today: String) -> Bool? {
        PlanOverview.followed(plan, from: start, to: PlanView.addDays(start, 6), today: today).percent.map { $0 >= threshold }
    }

    /* The last `count` weeks, oldest first, this week last. */
    public static func squares(_ plan: [Workout], today: String, count: Int = 12) -> [Square] {
        let now = PlanView.weekStart(today)
        return Stats.recentWeekStarts(count, today: today).map {
            Square(start: $0, followed: weekFollowed(plan, start: $0, today: today) ?? false, isNow: $0 == now)
        }
    }

    /*
     * Weeks in a row, counted back from the last finished week. This week
     * adds one once it is followed; while it is not (yet), it neither adds nor
     * breaks the row.
     */
    public static func row(_ plan: [Workout], today: String) -> Int {
        let now = PlanView.weekStart(today)
        var count = weekFollowed(plan, start: now, today: today) == true ? 1 : 0
        guard let first = firstWeek(plan) else { return count }
        var week = PlanView.addDays(now, -7)
        while week >= first, weekFollowed(plan, start: week, today: today) == true {
            count += 1
            week = PlanView.addDays(week, -7)
        }
        return count
    }

    /* The longest row there has been, and the Monday of its last week. The earliest wins a tie. */
    public static func longest(_ plan: [Workout], today: String) -> (weeks: Int, lastWeek: String)? {
        guard let first = firstWeek(plan) else { return nil }
        let now = PlanView.weekStart(today)
        var best: (weeks: Int, lastWeek: String)?
        var run = 0
        var week = first
        while week <= now {
            if weekFollowed(plan, start: week, today: today) == true {
                run += 1
                if run > (best?.weeks ?? 0) { best = (run, week) }
            } else { run = 0 }
            week = PlanView.addDays(week, 7)
        }
        return best
    }

    static func firstWeek(_ plan: [Workout]) -> String? {
        plan.filter { $0.discipline.id != "rest" && !$0.dayKey.isEmpty }.map(\.dayKey).min().map(PlanView.weekStart)
    }
}

// MARK: - 33 Personal bests

public enum PersonalBests {
    public enum Kind: String, CaseIterable {
        case ride, run, swim, week, row
        public var title: String {
            switch self {
            case .ride: return "Longest ride"
            case .run: return "Longest run"
            case .swim: return "Longest swim"
            case .week: return "Biggest week"
            case .row: return "Longest row of weeks"
            }
        }
    }

    public struct Best: Equatable, Identifiable {
        public var id: String { kind.rawValue }
        public let kind: Kind
        /* The session to open, for the three longest sessions. */
        public let key: String?
        /* The day of a session, or the Monday of a week. */
        public let dayKey: String
        public let seconds: Double
        /* Weeks, for the row. */
        public let weeks: Int
        /* What that session covered, in km, when it was logged. */
        public let km: Double?
        /* A session that covered more ground than the longest in time, when there is one. */
        public let farther: Farther?
    }

    public struct Farther: Equatable {
        public let key: String, dayKey: String, km: Double
    }

    /* Only from logged sessions, never missed ones. The earliest wins a tie. */
    public static func all(_ plan: [Workout], _ mapping: Mapping, today: String) -> [Best] {
        var out: [Best] = []
        for (kind, sport) in [(Kind.ride, "bike"), (.run, "run"), (.swim, "swim")] {
            let mine = plan.filter { $0.discipline.id == sport && MonthReview.isDone($0) }
                .sorted { $0.dayKey != $1.dayKey ? $0.dayKey < $1.dayKey : $0.key < $1.key }
            var longest: (w: Workout, s: Double)?
            var farthest: (w: Workout, km: Double)?
            for w in mine {
                let s = MonthReview.seconds(w, mapping)
                if s > (longest?.s ?? 0) { longest = (w, s) }
                let km = Stats.actualsOf(w, mapping).km
                if km > (farthest?.km ?? 0) { farthest = (w, km) }
            }
            guard let l = longest else { continue }
            let km = Stats.actualsOf(l.w, mapping).km
            var farther: Farther?
            if let f = farthest, f.w.key != l.w.key { farther = Farther(key: f.w.key, dayKey: f.w.dayKey, km: f.km) }
            out.append(Best(kind: kind, key: l.w.key, dayKey: l.w.dayKey, seconds: l.s, weeks: 0,
                            km: km > 0 ? km : nil, farther: farther))
        }
        // The biggest week, by hours done.
        var byWeek: [String: Double] = [:]
        for w in plan where MonthReview.isDone(w) && w.discipline.id != "rest" && !w.dayKey.isEmpty {
            byWeek[PlanView.weekStart(w.dayKey), default: 0] += MonthReview.seconds(w, mapping)
        }
        if let top = byWeek.filter({ $0.value > 0 }).min(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
            out.append(Best(kind: .week, key: nil, dayKey: top.key, seconds: top.value, weeks: 0, km: nil, farther: nil))
        }
        if let row = SteadyWeeks.longest(plan, today: today) {
            out.append(Best(kind: .row, key: nil, dayKey: row.lastWeek, seconds: 0, weeks: row.weeks, km: nil, farther: nil))
        }
        return out
    }
}

// MARK: - 34 Test history

public enum TestHistory {
    public enum Measure: String, CaseIterable {
        case pulse, power, swim
        public var title: String {
            switch self {
            case .pulse: return "Threshold pulse"
            case .power: return "Bike power (FTP)"
            case .swim: return "Swim pace"
            }
        }
        public var unit: String {
            switch self {
            case .pulse: return "bpm"
            case .power: return "W"
            case .swim: return "per 100 m"
            }
        }
        func value(_ t: TestResult) -> Double? {
            switch self {
            case .pulse: return t.lthr
            case .power: return t.ftp
            case .swim: return t.css
            }
        }
        public func text(_ v: Double) -> String {
            self == .swim ? TestEntry.swimText(v) : jsNumberString(v.rounded())
        }
    }

    public struct Dot: Equatable, Identifiable {
        public var id: String { test }
        public let test: String
        /* "02 Nov", or the test's name when the plan gave it no day. */
        public let label: String
        public let value: Double
    }

    public struct Series: Equatable, Identifiable {
        public var id: String { measure.rawValue }
        public let measure: Measure
        public let dots: [Dot]
        public var newest: Dot? { dots.last }
        /* The grey line: what the newest value stands beside, said calmly. */
        public let line: String
    }

    /* "02 Nov–04 Nov 2026" → "02 Nov". */
    public static func dayLabel(_ dates: String) -> String? {
        let first = dates.split(whereSeparator: { "–-".contains($0) }).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let words = first.split(separator: " ")
        guard words.count >= 2, Int(words[0]) != nil else { return nil }
        return words[0] + " " + words[1]
    }

    /* Only the measures with at least one value; tests without a number in a measure are left out of it. */
    public static func series(_ tests: [TestResult]) -> [Series] {
        Measure.allCases.compactMap { m in
            let dots = tests.compactMap { t -> Dot? in
                m.value(t).map { Dot(test: t.name, label: dayLabel(t.dates) ?? t.name, value: $0) }
            }
            guard !dots.isEmpty else { return nil }
            return Series(measure: m, dots: dots, line: line(m, dots))
        }
    }

    static func line(_ m: Measure, _ dots: [Dot]) -> String {
        guard let newest = dots.last else { return "" }
        if dots.count == 1 { return "First value, \(newest.test)" }
        // Equal results are shown as equal: the test the same value began at.
        var since = dots.count - 1
        while since > 0, dots[since - 1].value == newest.value { since -= 1 }
        if since < dots.count - 1 { return "Steady since \(dots[since].test)" }
        let before = dots[dots.count - 2]
        return "Was \(m.text(before.value)) at \(before.test)"
    }
}

// MARK: - 38 Report as PDF

public enum MonthReport {
    public struct WeekRow: Equatable, Identifiable {
        public var id: String { start }
        /* First and last day of the part of the week that lies in the month. */
        public let start: String, end: String
        public let sports: [PlanOverview.SportHours]
        public let hours: PlanOverview.Hours
    }

    public struct Line: Equatable, Identifiable {
        public var id: String { key }
        public let key: String, dayKey: String, sport: String, title: String
        public let planned: Double?
        public let done: Double?
        public let missed: Bool
        /* How hard, 1 to 10, when it was written down. */
        public let hard: Int?
    }

    public static func weeks(_ plan: [Workout], _ mapping: Mapping, month: String) -> [WeekRow] {
        let from = PlanOverview.firstDay(month), to = PlanOverview.lastDay(month)
        var out: [WeekRow] = []
        var monday = PlanView.weekStart(from)
        while monday <= to {
            let a = max(monday, from), b = min(PlanView.addDays(monday, 6), to)
            out.append(WeekRow(start: a, end: b, sports: PlanOverview.bySport(plan, mapping, from: a, to: b),
                               hours: PlanOverview.hours(plan, mapping, from: a, to: b)))
            monday = PlanView.addDays(monday, 7)
        }
        return out
    }

    public static func lines(_ plan: [Workout], _ mapping: Mapping, month: String) -> [Line] {
        let from = PlanOverview.firstDay(month), to = PlanOverview.lastDay(month)
        return plan.filter { $0.dayKey >= from && $0.dayKey <= to && $0.discipline.id != "rest" }
            .enumerated().sorted { $0.element.dayKey != $1.element.dayKey ? $0.element.dayKey < $1.element.dayKey : $0.offset < $1.offset }
            .map(\.element).map { w in
                let done = MonthReview.isDone(w)
                let rpe = done ? Int(Stats.actualsOf(w, mapping).rpe.rounded()) : 0
                return Line(key: w.key, dayKey: w.dayKey, sport: w.discipline.label, title: w.title,
                            planned: Plan.plannedSeconds(w, mapping), done: done ? MonthReview.seconds(w, mapping) : nil,
                            missed: w.missed, hard: (1...10).contains(rpe) ? rpe : nil)
            }
    }

    /* Every day of the month with the word he answered, or none. */
    public static func feelDays(_ feel: FeelLog, month: String) -> [(day: String, feel: Feel?)] {
        let from = PlanOverview.firstDay(month), to = PlanOverview.lastDay(month)
        var out: [(String, Feel?)] = []
        var d = from
        while d <= to { out.append((d, feel.answer(on: d))); d = PlanView.addDays(d, 1) }
        return out
    }

    /* The words on the page that says what is in the report, before it is made. */
    public static let contents: [String] = [
        "The month's facts: hours and sessions done of planned, hours per sport, the longest session, plan followed.",
        "A table of the weeks: planned and done hours for each sport.",
        "Your test values and your zones.",
        "How you felt each morning, as the five words.",
        "The sessions of the month: day, sport, title, planned, done, how hard."
    ]
}
