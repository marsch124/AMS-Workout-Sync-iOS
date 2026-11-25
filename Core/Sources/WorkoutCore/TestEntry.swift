import Foundation

/*
 * A test result typed into the app: the boxes as text, read and checked here
 * so the page only shows the answer. A box left empty means "not tested this
 * time"; at least one number is needed. Whatever cannot be read, or is out of
 * a sensible range, is refused with one plain sentence.
 */
public struct TestEntryFields: Equatable {
    public var lthr = ""
    public var ftp = ""
    /* Swim pace per 100 m, typed as m:ss. */
    public var swim = ""
    public var weight = ""
    public var notes = ""
    /* First and last day of the test, as yyyy-MM-dd. */
    public var firstDay = ""
    public var lastDay = ""

    public init(lthr: String = "", ftp: String = "", swim: String = "", weight: String = "",
                notes: String = "", firstDay: String = "", lastDay: String = "") {
        self.lthr = lthr; self.ftp = ftp; self.swim = swim; self.weight = weight
        self.notes = notes; self.firstDay = firstDay; self.lastDay = lastDay
    }
}

public enum TestEntry {
    public static let pulseRange = 80.0...220.0
    public static let ftpRange = 50.0...500.0
    public static let swimRange = 60.0...240.0
    public static let weightRange = 35.0...150.0

    /* "1:50" → 110 seconds; nil when it is not minutes:seconds. */
    public static func parseSwim(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let m = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let s = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              parts[1].trimmingCharacters(in: .whitespaces).count == 2,
              m >= 0, s >= 0, s < 60 else { return nil }
        return Double(m * 60 + s)
    }

    /* 110 → "1:50". */
    public static func swimText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):" + (total % 60 < 10 ? "0" : "") + "\(total % 60)"
    }

    /* A number as typed, a comma allowed for the point; nil when empty or not a finite number. */
    static func number(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let x = Double(t), x.isFinite else { return nil }
        return x
    }

    /* "02 Nov–04 Nov 2026", as the plan writes a test's days. */
    public static func datesText(first: String, last: String) -> String? {
        guard let a = parts(first), let b = parts(last) else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        func day(_ p: (Int, Int, Int)) -> String { String(format: "%02d", p.2) + " " + months[p.1 - 1] }
        if first == last { return day(a) + " \(a.0)" }
        if a.0 == b.0 { return day(a) + "–" + day(b) + " \(b.0)" }
        return day(a) + " \(a.0)–" + day(b) + " \(b.0)"
    }

    private static func parts(_ key: String) -> (Int, Int, Int)? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        return (p[0], p[1], p[2])
    }

    /* The boxes filled from a test, the way the last one's numbers were. Notes and days are not carried over. */
    public static func sameAs(_ test: TestResult, into fields: TestEntryFields = TestEntryFields()) -> TestEntryFields {
        var f = fields
        f.lthr = test.lthr.map(jsNumberString) ?? ""
        f.ftp = test.ftp.map(jsNumberString) ?? ""
        f.swim = test.css.map(swimText) ?? ""
        f.weight = test.weight.map(jsNumberString) ?? ""
        return f
    }

    /* The last test that has numbers, the one the zones follow. */
    public static func last(of tests: [TestResult]) -> TestResult? { tests.last { $0.hasNumbers } }

    /*
     * The new test, or the one sentence saying what is wrong. A block of the
     * plan still waiting for its numbers is filled in; otherwise a new
     * "Test N" is added after the others.
     */
    public static func make(_ f: TestEntryFields, existing: [TestResult]) -> Result<TestResult, TestEntryProblem> {
        func read(_ text: String, _ range: ClosedRange<Double>, _ what: String, _ unit: String) -> Result<Double?, TestEntryProblem> {
            if text.trimmingCharacters(in: .whitespaces).isEmpty { return .success(nil) }
            guard let x = number(text), range.contains(x) else {
                return .failure(TestEntryProblem("\(what) needs a number from \(jsNumberString(range.lowerBound)) to \(jsNumberString(range.upperBound)) \(unit)."))
            }
            return .success(x)
        }
        var lthr: Double?, ftp: Double?, css: Double?, weight: Double?
        switch read(f.lthr, pulseRange, "Threshold pulse", "beats a minute") { case .success(let x): lthr = x; case .failure(let p): return .failure(p) }
        switch read(f.ftp, ftpRange, "Bike power (FTP)", "watts") { case .success(let x): ftp = x; case .failure(let p): return .failure(p) }
        if !f.swim.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let s = parseSwim(f.swim), swimRange.contains(s) else {
                return .failure(TestEntryProblem("Swim pace needs minutes and seconds between 1:00 and 4:00, like 1:50."))
            }
            css = s
        }
        switch read(f.weight, weightRange, "Weight", "kg") { case .success(let x): weight = x; case .failure(let p): return .failure(p) }
        if lthr == nil && ftp == nil && css == nil && weight == nil {
            return .failure(TestEntryProblem("Enter at least one number: pulse, bike power, swim pace or weight."))
        }
        guard !f.firstDay.isEmpty, !f.lastDay.isEmpty, parts(f.firstDay) != nil, parts(f.lastDay) != nil else {
            return .failure(TestEntryProblem("Choose the day, or the first and last day, of the test."))
        }
        guard f.firstDay <= f.lastDay, let dates = datesText(first: f.firstDay, last: f.lastDay) else {
            return .failure(TestEntryProblem("The last day is before the first day."))
        }
        let notes = f.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target(existing: existing) {
        case .waiting(let waiting):
            return .success(TestResult(name: waiting.name, week: waiting.week, dates: dates, lthr: lthr, ftp: ftp,
                                       css: css, weight: weight, notes: notes))
        case .new(let name):
            return .success(TestResult(name: name, dates: dates, lthr: lthr, ftp: ftp, css: css, weight: weight, notes: notes))
        }
    }

    /* Where a saved test goes: into a block still waiting for numbers, or after the others as a new "Test N". */
    public enum Target: Equatable {
        case waiting(TestResult)
        case new(String)
    }

    public static func target(existing: [TestResult]) -> Target {
        // Only a block after the last one that has numbers is filled; an earlier empty one stays as it is.
        let after = (existing.lastIndex(where: { $0.hasNumbers }) ?? -1) + 1
        if let waiting = existing.dropFirst(after).first(where: { !$0.hasNumbers }) { return .waiting(waiting) }
        var n = existing.count + 1
        while existing.contains(where: { $0.name == "Test \(n)" }) { n += 1 }
        return .new("Test \(n)")
    }

    /* The grey line under the boxes: which test Save makes. Taken from the same rule as make. */
    public static func becomesLine(existing: [TestResult]) -> String {
        switch target(existing: existing) {
        case .waiting(let t): return "Saves as \(t.name)"
        case .new(let name): return "Saves as a new test, \(name)"
        }
    }

    /* "Test 6 \u{2014} not scheduled", without the empty day ", \u{2014}" the sheet leaves behind. */
    public static func cleanLabel(_ t: TestResult) -> String {
        var label = t.label
        for tail in [", \u{2014}", ", -", ", \u{2013}"] where label.hasSuffix(tail) { label.removeLast(tail.count) }
        return label
    }
}

public struct TestEntryProblem: Error, Equatable {
    public let words: String
    public init(_ words: String) { self.words = words }
}
