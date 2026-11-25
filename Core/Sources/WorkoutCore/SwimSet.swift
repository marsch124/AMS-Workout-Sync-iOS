import Foundation

/*
 * A swim set read out of the words a session is written in, one step per row
 * for the pool card (round 28, pick 24).
 *
 * Sets are written in many ways: "4x50 drill, then 6x50 smooth", "4 × 100 m
 * rest 20 s Z3", "200 easy", "Warm-up: 200 easy" on one line and the next, or
 * "8x50 drills + 6x100 easy". The reading is tolerant and never throws a word
 * away: a piece it cannot read becomes a row of its own, shown exactly as it
 * was written (only its edges trimmed). Rows hold whole pieces, so nothing is
 * ever cut in the middle.
 */

public struct SwimStep: Equatable, Sendable {
    /* The row as the pool card shows it: "4 × 100 m · rest 20 s · Z3". */
    public var line: String
    /* The section heading it sits under ("Warm-up", "Main set"), when the text had one. */
    public var heading: String?
    /* Metres this row swims in all (reps × length); 0 when the row holds no distance. */
    public var metres: Int
    /* False for a piece the reading could not make sense of: `line` is then the original words. */
    public var understood: Bool

    public init(line: String, heading: String? = nil, metres: Int = 0, understood: Bool = true) {
        self.line = line; self.heading = heading; self.metres = metres; self.understood = understood
    }
}

public struct SwimSet: Equatable, Sendable {
    public var steps: [SwimStep]
    public var totalMetres: Int { steps.reduce(0) { $0 + $1.metres } }
    /* True when at least one row holds a distance: only then is it worth a pool card of its own. */
    public var hasDistance: Bool { totalMetres > 0 }

    public init(steps: [SwimStep]) { self.steps = steps }

    /* "1,500 m" — the whole set's distance, the way the card's top line writes it. */
    public static func metresText(_ metres: Int) -> String {
        let digits = String(metres)
        var out = ""
        for (i, c) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return String(out.reversed()) + " m"
    }

    // MARK: reading

    /* A session's sections (heading, text) in order. The heading "Session" is the plan's word for "no heading". */
    public static func parse(sections: [(heading: String, text: String)]) -> SwimSet {
        var steps: [SwimStep] = []
        for section in sections {
            let heading = clean(section.heading)
            let isPlain = heading.isEmpty || normal(heading) == "session"
            steps += read(section.text, heading: isPlain ? nil : heading)
        }
        return SwimSet(steps: steps)
    }

    public static func parse(_ text: String) -> SwimSet {
        SwimSet(steps: read(text, heading: nil))
    }

    // MARK: pieces

    private static let headingWords: [String: String] = [
        "warm up": "Warm-up", "warmup": "Warm-up", "warm": "Warm-up", "prep": "Warm-up",
        "main": "Main set", "main set": "Main set", "mainset": "Main set", "set": "Main set", "intervals": "Main set",
        "cool down": "Cool-down", "cooldown": "Cool-down", "cool": "Cool-down", "warm down": "Cool-down",
        "technique": "Technique", "drills": "Technique", "drill": "Technique", "skills": "Technique",
        "pull": "Pull set", "kick": "Kick set"
    ]

    private static func read(_ text: String, heading startHeading: String?) -> [SwimStep] {
        var heading = startHeading
        var steps: [SwimStep] = []
        for raw in pieces(of: text) {
            var piece = raw
            // "Warm-up: 200 easy" — a known heading word before a colon.
            if let colon = piece.firstIndex(of: ":") {
                let before = clean(String(piece[..<colon]))
                let after = clean(String(piece[piece.index(after: colon)...]))
                if let name = headingWords[normal(before)] {
                    heading = name
                    if after.isEmpty { continue }
                    piece = after
                } else if !after.isEmpty, !before.isEmpty, !before.contains(where: \.isNumber), before.count <= 40 {
                    // "Easy technique: 4x50 drill": the words before the colon stay, as a row, never dropped.
                    steps.append(SwimStep(line: before, heading: heading, understood: false))
                    piece = after
                }
            } else if let name = headingWords[normal(piece)] {
                heading = name
                continue
            }
            if let step = readStep(piece, heading: heading) {
                steps.append(step)
            } else if let addition = readAddition(piece), let last = steps.last, last.understood, last.metres > 0 {
                steps[steps.count - 1] = attach(addition, to: last)
            } else {
                steps.append(SwimStep(line: piece, heading: heading, understood: false))
            }
        }
        return steps
    }

    /* The text cut into pieces at line ends, bullets, semicolons, commas, "+" and "then". */
    static func pieces(of text: String) -> [String] {
        var s = text.replacingOccurrences(of: "\r", with: "\n")
        for bullet in ["\u{2022}", "\u{25CF}", "\u{25E6}", "\u{2023}"] { s = s.replacingOccurrences(of: bullet, with: "\n") }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var out: [String] = []
        for line in lines {
            var current = ""
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            var pending: [String] = []
            func flush() {
                let piece = clean(current)
                if !piece.isEmpty { pending.append(piece) }
                current = ""
            }
            var i = 0
            while i < words.count {
                let w = words[i]
                let lower = w.lowercased()
                if lower == "then" || lower == "+" || lower == "&" || lower == "and" && startsNumber(words, i + 1) {
                    flush(); i += 1; continue
                }
                var word = w
                var cutAfter = false
                if word.hasSuffix(";") || word.hasSuffix(",") { word.removeLast(); cutAfter = true }
                if word.hasPrefix("+") && word.count > 1 { flush(); word.removeFirst() }
                // A comma inside "1,500" is not a cut: only a comma at a word's end is.
                if !word.isEmpty { current += (current.isEmpty ? "" : " ") + word }
                if cutAfter { flush() }
                i += 1
            }
            flush()
            // "+" glued to its neighbours ("8x50+6x100").
            for p in pending { out += splitGluedPlus(p) }
        }
        return out
    }

    private static func startsNumber(_ words: [String], _ i: Int) -> Bool {
        i < words.count && (words[i].first?.isNumber ?? false)
    }

    private static func splitGluedPlus(_ piece: String) -> [String] {
        guard piece.contains("+") else { return [piece] }
        return piece.split(separator: "+").map { clean(String($0)) }.filter { !$0.isEmpty }
    }

    // MARK: one step

    private static let timeUnits: Set<String> = ["min", "mins", "minute", "minutes", "sec", "secs", "second", "seconds", "s", "h", "hr", "hrs", "hour", "hours"]

    private static func readStep(_ piece: String, heading: String?) -> SwimStep? {
        let t = piece.replacingOccurrences(of: "\u{00D7}", with: "x").replacingOccurrences(of: "\u{2715}", with: "x")
        let chars = Array(t)
        var i = 0
        func skipSpaces() { while i < chars.count, chars[i] == " " { i += 1 } }
        func number() -> Int? {
            let start = i
            var digits = ""
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { digits.append(c); i += 1 }
                else if c == ",", i + 1 < chars.count, chars[i + 1].isNumber, !digits.isEmpty, i - start >= 1 { i += 1 }
                else { break }
            }
            return Int(digits)
        }
        skipSpaces()
        guard let first = number() else { return nil }
        var reps = 1
        var length = first
        skipSpaces()
        var hasReps = false
        if i < chars.count, chars[i] == "x" || chars[i] == "X" || chars[i] == "*" {
            // "4x100": the next thing must be a number, else this is not a rep count.
            let save = i
            i += 1; skipSpaces()
            if let second = number() { reps = first; length = second; hasReps = true } else { i = save }
        }
        skipSpaces()
        // The unit: m, metres, meters, km, yd, y.
        var unitMetres = 1.0
        var sawUnit = false
        let rest0 = String(chars[i...]).lowercased()
        for (word, factor) in [("kilometres", 1000.0), ("kilometers", 1000.0), ("metres", 1.0), ("meters", 1.0), ("metre", 1.0), ("meter", 1.0), ("km", 1000.0), ("yds", 0.9144), ("yd", 0.9144), ("m", 1.0)] {
            if rest0.hasPrefix(word) {
                let after = rest0.dropFirst(word.count).first
                if after == nil || !(after!.isLetter) {
                    unitMetres = factor; sawUnit = true; i += word.count
                    break
                }
            }
        }
        var remainder = clean(String(chars[min(i, chars.count)...]))
        let firstWord = remainder.split(separator: " ").first.map { String($0).lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        if !sawUnit {
            if timeUnits.contains(firstWord) { return nil }                      // "10 min easy": a time, not a distance
            if !hasReps && length < 25 { return nil }                            // "6 lengths", "3 rounds": not a plain distance
        }

        let (rest, remainderWithoutExtras) = extras(of: remainder)
        remainder = remainderWithoutExtras

        let each = Int((Double(length) * unitMetres).rounded())
        let total = each * reps
        var parts: [String] = []
        var head = hasReps ? "\(reps) \u{00D7} \(each) m" : "\(each) m"
        if !remainder.isEmpty { head += " " + remainder }
        parts.append(head)
        if let r = rest { parts.append("rest " + r) }
        if let z = zone(in: piece) { parts.append(z) }
        return SwimStep(line: parts.joined(separator: " \u{00B7} "), heading: heading, metres: total, understood: true)
    }

    /* Rest and zone pulled out of what follows the distance, so the row reads "… · rest 20 s · Z3". */
    private static func extras(of text: String) -> (String?, String) {
        var s = text
        var rest: String?
        let restPatterns = [
            #"(?i)(?:with\s+|w/\s*|@\s*)?\brest(?:\s+of)?\s*[:=]?\s*(\d+)\s*(seconds|second|secs|sec|s|minutes|minute|mins|min)?\b"#,
            #"(?i)\b(\d+)\s*(seconds|second|secs|sec|s|minutes|minute|mins|min)\s+(?:rest|recovery|break)\b"#,
            #"(?i)\br\s?(\d+)\s*(s|sec|secs)?\b(?=\s|$|,|;)"#
        ]
        for pattern in restPatterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                let n = ns.substring(with: m.range(at: 1))
                var unit = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)).lowercased() : "s"
                unit = unit.hasPrefix("m") ? "min" : "s"
                rest = n + " " + unit
                s = ns.replacingCharacters(in: m.range, with: " ")
                break
            }
        }
        // The zone is shown as its own part, so it comes out of the words too.
        if let re = try? NSRegularExpression(pattern: #"(?i)(?:@|at|in)?\s*\bZ[1-5](?:\s*[-\u2013]\s*Z?[1-5])?\b"#) {
            let ns = s as NSString
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }
        s = s.replacingOccurrences(of: "@", with: " ")
        return (rest, clean(s))
    }

    private static func zone(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(?i)\bZ([1-5])(?:\s*[-\u2013]\s*Z?([1-5]))?\b"#) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let a = ns.substring(with: m.range(at: 1))
        if m.range(at: 2).location != NSNotFound { return "Z\(a)\u{2013}Z\(ns.substring(with: m.range(at: 2)))" }
        return "Z" + a
    }

    // MARK: a piece that only adds to the row before it

    private struct Addition { var rest: String?; var zone: String? }

    /* "rest 20s", "Z3", "@ Z3 rest 15 s": nothing to swim in it, only something to say about the row before. */
    private static func readAddition(_ piece: String) -> Addition? {
        let (rest, left) = extras(of: piece)
        let z = zone(in: piece)
        guard rest != nil || z != nil, left.isEmpty || normal(left) == "rest" else { return nil }
        return Addition(rest: rest, zone: z)
    }

    private static func attach(_ a: Addition, to step: SwimStep) -> SwimStep {
        var s = step
        if let r = a.rest, !s.line.contains("rest ") { s.line += " \u{00B7} rest " + r }
        if let z = a.zone, !s.line.contains(" Z") { s.line += " \u{00B7} " + z }
        return s
    }

    // MARK: small helpers

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-\u{2013}\u{2014}.,;:")))
    }

    private static func normal(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").joined(separator: " ")
    }
}
