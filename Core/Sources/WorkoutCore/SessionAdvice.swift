import Foundation

/*
 * Three small, general habits shown on a session's page. Pure rules, no screen:
 *   - a fuel line on a planned session over 90 minutes,
 *   - a protein line after strength,
 *   - the steps of an interval session, to build once in Garmin Connect.
 *
 * None of it is advice about the person. The lines are common sport habits and
 * carry no number about him. The interval reader would rather give nothing than
 * a wrong workout: a text it cannot read into steps with confidence gives nil.
 */

public struct IntervalStep: Equatable {
    public enum Kind: String, Equatable { case warmup, work, recovery, cooldown }
    public let kind: Kind
    /* Whole minutes; nil where the plan gives none (a recovery "until ready"). */
    public let minutes: Int?
    /* "Z3", "90-95% FTP", "jog", "easy": the words the plan used. */
    public let target: String
    /* True for the steps that sit inside the repeat. */
    public let inRepeat: Bool
    /* A cool-down that runs until the planned time is up (recovery length not given): that total, in minutes. */
    public let untilMinutes: Int?

    public init(kind: Kind, minutes: Int?, target: String, inRepeat: Bool, untilMinutes: Int? = nil) {
        self.kind = kind; self.minutes = minutes; self.target = target; self.inRepeat = inRepeat
        self.untilMinutes = untilMinutes
    }
}

public struct IntervalPlan: Equatable {
    public let sport: String
    public let repeats: Int
    public let steps: [IntervalStep]
}

public enum SessionAdvice {
    // MARK: Fuel and protein

    public static let fuelText = "Over 90 minutes: eat and drink as you go \u{2014} about 30\u{2013}60 g of carbohydrate an hour."
    public static let proteinText = "After strength: a meal or snack with 20\u{2013}30 g of protein within an hour or two."

    /* Longer than 90 minutes, on any day with a session: 90 exactly gives nothing. */
    public static func fuelLine(seconds: Double?, sport: String) -> String? {
        guard sport != "rest", let s = seconds, s > 90 * 60 else { return nil }
        return fuelText
    }

    public static func proteinLine(sport: String) -> String? {
        sport == "strength" ? proteinText : nil
    }

    public static func fuelLine(for w: Workout, _ mapping: Mapping) -> String? {
        fuelLine(seconds: Plan.plannedSeconds(w, mapping), sport: w.discipline.id)
    }

    public static func proteinLine(for w: Workout) -> String? { proteinLine(sport: w.discipline.id) }

    // MARK: Interval steps

    public static func intervalSteps(for w: Workout, _ mapping: Mapping) -> IntervalPlan? {
        let minutes = Plan.plannedSeconds(w, mapping).map { Int(($0 / 60).rounded()) }
        for text in [w.planned.description, w.title] where !text.isEmpty {
            if let p = intervalSteps(text: text, sport: w.discipline.id, totalMinutes: minutes) { return p }
        }
        return nil
    }

    private static func normalised(_ s: String) -> String {
        String(s.map { c -> Character in
            switch c {
            case "\u{00D7}": return "x"
            case "\u{2013}", "\u{2014}", "\u{2212}": return "-"
            default: return c
            }
        })
    }

    private static let simple: NSRegularExpression = try! NSRegularExpression(pattern:
        #"^(?:(?!(?:(?!\bwith\b)[a-z0-9 .+/])*\d+\s*min)[a-z0-9 .+/]{0,40}?\bwith\s+|(\d+)\s*min\s+easy\s*\+\s*)?(\d+)\s*x\s*(\d+)\s*min(?:utes)?\s+(?:at|@)\s+([^,;(]+?)(?:\s*,\s*(?:(\d+)\s*min\s*(easy|jog|walk|rest|recovery)(?:\s+between)?|(easy|jog)\s+(?:between|recoveries)))?\s*$"#,
        options: [.caseInsensitive])

    private static let overUnder: NSRegularExpression = try! NSRegularExpression(pattern:
        #"^(\d+)\s*x\s*\(\s*(\d+)\s*min\s+([^/)]+?)\s*/\s*(\d+)\s*min\s+([^)]+?)\s*\)\s*$"#,
        options: [.caseInsensitive])

    /*
     * Reads "3x8 min at Z3, 2 min jog" and its close relatives. Only run and bike,
     * only repeats counted in minutes with one fixed number of times. A repeat of
     * short efforts (under 10 minutes) needs its recovery named; long blocks may
     * go without. Anything else (ranges, seconds, distances, extra clauses) is nil.
     */
    public static func intervalSteps(text: String, sport: String, totalMinutes: Int?) -> IntervalPlan? {
        guard sport == "run" || sport == "bike" else { return nil }
        var original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A short label before a colon ("Cruise intervals:") is not part of the steps.
        if let colon = original.firstIndex(of: ":") {
            let label = original[..<colon]
            if label.split(separator: " ").count <= 5, !label.lowercased().contains("x") && !label.contains("\u{00D7}") {
                original = String(original[original.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        let norm = normalised(original)
        // Two sequences in one text ("... then ...") is more than this reader understands.
        if " \(norm.lowercased()) ".contains(" then ") { return nil }
        let ns = norm as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r).trimmingCharacters(in: .whitespaces)
        }
        let easyWord = sport == "run" ? "easy running" : "easy riding"

        var warm: Int?
        var reps = 0
        var inside: [IntervalStep] = []

        if let m = simple.firstMatch(in: norm, range: whole) {
            warm = group(m, 1).flatMap { Int($0) }
            guard let r = group(m, 2).flatMap({ Int($0) }), let w = group(m, 3).flatMap({ Int($0) }),
                  let target = group(m, 4), !target.isEmpty, plainTarget(target) else { return nil }
            reps = r
            inside.append(IntervalStep(kind: .work, minutes: w, target: target, inRepeat: true))
            if let rm = group(m, 5).flatMap({ Int($0) }), let word = group(m, 6) {
                inside.append(IntervalStep(kind: .recovery, minutes: rm, target: recoveryWord(word, sport), inRepeat: true))
            } else if let word = group(m, 7) {
                inside.append(IntervalStep(kind: .recovery, minutes: nil, target: recoveryWord(word, sport), inRepeat: true))
            } else {
                // No recovery named: short efforts are unreadable, and long blocks would run back to back.
                return nil
            }
        } else if let m = overUnder.firstMatch(in: norm, range: whole) {
            guard let r = group(m, 1).flatMap({ Int($0) }), let a = group(m, 2).flatMap({ Int($0) }),
                  let at = group(m, 3), let b = group(m, 4).flatMap({ Int($0) }), let bt = group(m, 5),
                  plainTarget(at), plainTarget(bt) else { return nil }
            reps = r
            inside = [IntervalStep(kind: .work, minutes: a, target: at, inRepeat: true),
                      IntervalStep(kind: .work, minutes: b, target: bt, inRepeat: true)]
        } else {
            return nil
        }
        guard (2...20).contains(reps), inside.allSatisfy({ ($0.minutes ?? 1) >= 1 && ($0.minutes ?? 1) <= 120 }) else { return nil }

        // Warm-up and cool-down. A warm-up named in the text is used as written; otherwise 15 minutes
        // (10 when the session is shorter than 45). The cool-down is what the planned time leaves.
        if let total = totalMinutes, total < reps * inside.reduce(0, { $0 + ($1.minutes ?? 0) }) + 10 { return nil }
        let recoveryKnown = inside.allSatisfy { $0.minutes != nil }
        let repeated = reps * inside.reduce(0) { $0 + ($1.minutes ?? 0) }
        var warmMinutes = warm ?? ((totalMinutes ?? 0) >= 45 ? 15 : 10)
        var steps: [IntervalStep] = []
        var cool: IntervalStep
        if recoveryKnown, let total = totalMinutes {
            var left = total - warmMinutes - repeated
            if left < 5, warm == nil, warmMinutes > 10 {
                warmMinutes = 10
                left = total - warmMinutes - repeated
            }
            guard left >= 5 else { return nil }
            cool = IntervalStep(kind: .cooldown, minutes: left, target: easyWord, inRepeat: false)
        } else if let total = totalMinutes {
            cool = IntervalStep(kind: .cooldown, minutes: nil, target: easyWord, inRepeat: false, untilMinutes: total)
        } else {
            cool = IntervalStep(kind: .cooldown, minutes: 5, target: easyWord, inRepeat: false)
        }
        // A very long easy start is a long ride with blocks in it, not a session to build by hand.
        guard warmMinutes <= 45 else { return nil }
        steps.append(IntervalStep(kind: .warmup, minutes: warmMinutes, target: easyWord, inRepeat: false))
        steps += inside
        steps.append(cool)
        return IntervalPlan(sport: sport, repeats: reps, steps: steps)
    }

    /* A target is a few plain words ("Z3-low Z4", "90-95% FTP"), not a sentence. */
    private static func plainTarget(_ t: String) -> Bool {
        let l = " " + t.lowercased() + " "
        return t.split(separator: " ").count <= 5 && ![" and ", " then ", " followed ", " + ", " of "].contains { l.contains($0) }
    }

    private static func recoveryWord(_ w: String, _ sport: String) -> String {
        switch w.lowercased() {
        case "jog": return sport == "run" ? "jog" : "easy"
        case "walk": return "walk"
        case "rest": return "rest"
        default: return "easy"
        }
    }

    // MARK: The Garmin Connect steps

    public static let garminTemplateLine = "Saved there, it stays in your Workouts list: copy it for next week and send it to your watch."

    private static func minutesText(_ m: Int?) -> String { m.map { "\($0) min" } ?? "until you are ready (press Lap)" }

    private static func stepLine(_ s: IntervalStep) -> String {
        switch s.kind {
        case .warmup: return "Warm-up: \(minutesText(s.minutes)), \(s.target)."
        case .cooldown:
            if let until = s.untilMinutes { return "Cool-down: \(s.target) until the \(until) minutes are up." }
            return "Cool-down: \(minutesText(s.minutes)), \(s.target)."
        case .work: return "Work: \(minutesText(s.minutes)) at \(s.target)."
        case .recovery:
            return s.minutes == nil ? "Recovery: \(s.target), \(minutesText(nil))." : "Recovery: \(s.minutes!) min \(s.target)."
        }
    }

    /* The numbered lines, one per thing to tap or enter. */
    public static func garminLines(for plan: IntervalPlan) -> [String] {
        var raw: [String] = [
            "Open Garmin Connect on your phone. Tap More, then Training & Planning, then Workouts, then Create a Workout.",
            "Choose \(plan.sport == "run" ? "Running" : "Cycling") as the sport.",
        ]
        for s in plan.steps where s.kind == .warmup { raw.append("Add a step. " + stepLine(s)) }
        raw.append("Add a repeat: \(plan.repeats) times.")
        for s in plan.steps where s.inRepeat { raw.append("Inside the repeat, add a step. " + stepLine(s)) }
        for s in plan.steps where s.kind == .cooldown { raw.append("After the repeat, add a step. " + stepLine(s)) }
        raw.append("Name it and tap Save.")
        return raw.enumerated().map { "\($0.offset + 1). \($0.element)" }
    }

    /* The plain text the Copy button puts on the clipboard. */
    public static func garminText(for plan: IntervalPlan) -> String {
        (["Build it like this in Garmin Connect"] + garminLines(for: plan) + [garminTemplateLine]).joined(separator: "\n")
    }

    public static func garminText(for w: Workout, _ mapping: Mapping) -> String? {
        intervalSteps(for: w, mapping).map(garminText(for:))
    }
}
