import Foundation

/*
 * Round 28, lane logextras: four extra facts he can note when he logs a session.
 * They sit on the shelf (`session/<Workout.key>/brick|stomach|niggle|openwater`), never in the plan.
 * Every type decodes tolerantly: a field this build cannot read becomes "nothing", never an error.
 */

public enum LogExtrasKeys {
    public static let prefix = "session/"
    public static func key(_ workoutKey: String, _ fact: String) -> String { "session/\(workoutKey)/\(fact)" }
    /* The session key inside "session/<key>/<fact>"; nil for any other shelf key. */
    public static func workoutKey(from shelfKey: String, fact: String) -> String? {
        let suffix = "/" + fact
        guard shelfKey.hasPrefix(prefix), shelfKey.hasSuffix(suffix), shelfKey.count > prefix.count + suffix.count else { return nil }
        return String(shelfKey.dropFirst(prefix.count).dropLast(suffix.count))
    }
}

// MARK: - 23 Brick log

public struct BrickLog: Codable, Equatable {
    public var bikeSeconds: Int?
    public var changeSeconds: Int?
    public var runSeconds: Int?

    public init(bikeSeconds: Int? = nil, changeSeconds: Int? = nil, runSeconds: Int? = nil) {
        self.bikeSeconds = bikeSeconds; self.changeSeconds = changeSeconds; self.runSeconds = runSeconds
    }

    enum CodingKeys: String, CodingKey { case bikeSeconds, changeSeconds, runSeconds }
    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        bikeSeconds = try? c?.decodeIfPresent(Int.self, forKey: .bikeSeconds)
        changeSeconds = try? c?.decodeIfPresent(Int.self, forKey: .changeSeconds)
        runSeconds = try? c?.decodeIfPresent(Int.self, forKey: .runSeconds)
    }

    public var isEmpty: Bool { bikeSeconds == nil && changeSeconds == nil && runSeconds == nil }

    /* The sum, only when all three are there. */
    public var total: Int? {
        guard let b = bikeSeconds, let c = changeSeconds, let r = runSeconds else { return nil }
        return b + c + r
    }

    /* "Use 1h 52m as the length" — the sum rounded to whole minutes; nil until all three are filled. */
    public var useSumWords: String? {
        guard let t = total, t > 0 else { return nil }
        return "Use \(formatDuration(Double((t + 30) / 60 * 60))) as the length"
    }

    /* The sum as the log's own length box reads it ("1:52"). */
    public var sumAsClock: String? {
        guard let t = total, t > 0 else { return nil }
        let m = (t + 30) / 60
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /* From the three boxes: bike and run as parseDuration reads them (72, 1:12, 1h12), the change-over as minutes:seconds. */
    public static func make(bike: String, change: String, run: String) -> BrickLog? {
        let b = parseDuration(bike).map { Int($0) }
        let c = parseMinutesSeconds(change)
        let r = parseDuration(run).map { Int($0) }
        let log = BrickLog(bikeSeconds: b.flatMap { $0 > 0 ? $0 : nil }, changeSeconds: c, runSeconds: r.flatMap { $0 > 0 ? $0 : nil })
        return log.isEmpty ? nil : log
    }

    /* "1:30" = 1 min 30 s; "2" = 2 min; "45s" = 45 s; empty or nonsense = nil. */
    public static func parseMinutesSeconds(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return nil }
        if t.hasSuffix("s"), let v = Double(t.dropLast().trimmingCharacters(in: .whitespaces)), v >= 0 { return Int(v.rounded()) }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]), m >= 0, (0..<60).contains(s) { return m * 60 + s }
        if parts.count == 1, let m = Double(parts[0]), m >= 0 { return Int((m * 60).rounded()) }
        return nil
    }

    /* The change-over as it is typed: "1:30". */
    public static func minutesSecondsText(_ seconds: Int?) -> String {
        guard let s = seconds else { return "" }
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /* The three figures as the box shows them. */
    public static func lengthText(_ seconds: Int?) -> String { seconds.map { formatDuration(Double($0)) } ?? "" }
}

// MARK: - 29 Stomach OK?

public enum StomachAnswer: String, Codable, CaseIterable, Equatable {
    case fine, soso, upset
    public var word: String {
        switch self { case .fine: return "Fine"; case .soso: return "So-so"; case .upset: return "Upset" }
    }
}

public struct StomachNote: Codable, Equatable {
    public var answer: StomachAnswer?
    public var line: String

    public init(answer: StomachAnswer? = nil, line: String = "") { self.answer = answer; self.line = line }

    enum CodingKeys: String, CodingKey { case answer, line }
    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        let raw = try? c?.decodeIfPresent(String.self, forKey: .answer)
        answer = raw.flatMap { StomachAnswer(rawValue: $0) }
        line = ((try? c?.decodeIfPresent(String.self, forKey: .line)) ?? nil) ?? ""
    }

    public static func make(answer: StomachAnswer?, line: String) -> StomachNote? {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return answer == nil && l.isEmpty ? nil : StomachNote(answer: answer, line: l)
    }

    /* A session of 90 minutes or longer (the planned length, or the length he logged). */
    public static func applies(seconds: Double?) -> Bool { (seconds ?? 0) >= 90 * 60 }
}

public struct FuelTally: Equatable {
    public var sessions = 0, fine = 0, soso = 0, upset = 0

    public init(_ notes: [StomachNote]) {
        for n in notes {
            sessions += 1
            switch n.answer { case .fine?: fine += 1; case .soso?: soso += 1; case .upset?: upset += 1; case nil: break }
        }
    }

    /* "12 long sessions · 9 fine · 2 so-so · 1 upset" — an answer nobody gave is left out. */
    public var headline: String {
        var parts = ["\(sessions) long session" + (sessions == 1 ? "" : "s")]
        if fine > 0 { parts.append("\(fine) fine") }
        if soso > 0 { parts.append("\(soso) so-so") }
        if upset > 0 { parts.append("\(upset) upset") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 30 Niggle note

public struct NiggleNote: Codable, Equatable {
    public var place: String
    /* "left", "right", "both"; nil where it does not apply or he did not say. */
    public var side: String?
    public var line: String

    public init(place: String, side: String? = nil, line: String = "") { self.place = place; self.side = side; self.line = line }

    enum CodingKeys: String, CodingKey { case place, side, line }
    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        place = ((try? c?.decodeIfPresent(String.self, forKey: .place)) ?? nil) ?? "Other"
        side = (try? c?.decodeIfPresent(String.self, forKey: .side)) ?? nil
        line = ((try? c?.decodeIfPresent(String.self, forKey: .line)) ?? nil) ?? ""
    }

    public static let places = ["Neck", "Shoulder", "Back", "Hip", "Thigh", "Knee", "Shin", "Calf", "Achilles", "Foot", "Other"]
    public static let sides = ["left", "right", "both"]
    public static func sideApplies(to place: String) -> Bool { !["Neck", "Back", "Other"].contains(place) }

    /* "left calf", "back" — the place as he would say it. */
    public var placeWords: String {
        let p = place.lowercased()
        if let s = side, NiggleNote.sideApplies(to: place), NiggleNote.sides.contains(s) { return s + " " + p }
        return p
    }

    /* "Niggle: left calf — tight after the hills" */
    public var doneLine: String { "Niggle: " + placeWords + (line.isEmpty ? "" : " — " + line) }

    public static func make(place: String?, side: String?, line: String) -> NiggleNote? {
        guard let place, places.contains(place) else { return nil }
        return NiggleNote(place: place, side: sideApplies(to: place) ? side : nil,
                          line: line.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/* One place with how often and since when — "Left calf · 3 times since Mon 2 Nov". */
public struct NiggleSpot: Equatable {
    public var label: String
    public var count: Int
    public var sinceDay: String
}

public enum NiggleCount {
    /* Each place counted (left and right apart), how often, and the earliest day. Most often first, then the earliest. A notebook, not a diagnosis. */
    public static func spots(_ items: [(day: String, note: NiggleNote)]) -> [NiggleSpot] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var since: [String: String] = [:]
        for i in items {
            let words = i.note.placeWords
            if counts[words] == nil { order.append(words) }
            counts[words, default: 0] += 1
            if let s = since[words] { if i.day < s { since[words] = i.day } } else { since[words] = i.day }
        }
        let out = order.map { w in
            NiggleSpot(label: w.prefix(1).uppercased() + w.dropFirst(), count: counts[w] ?? 0, sinceDay: since[w] ?? "")
        }
        return out.sorted { $0.count != $1.count ? $0.count > $1.count : ($0.sinceDay != $1.sinceDay ? $0.sinceDay < $1.sinceDay : $0.label < $1.label) }
    }

    public static func countWords(_ n: Int) -> String { n == 1 ? "once" : (n == 2 ? "twice" : "\(n) times") }
}

// MARK: - 31 Open-water notes

public struct OpenWaterNote: Codable, Equatable {
    public var wetsuit: Bool?
    public var tempC: Int?
    public var line: String

    public init(wetsuit: Bool? = nil, tempC: Int? = nil, line: String = "") { self.wetsuit = wetsuit; self.tempC = tempC; self.line = line }

    enum CodingKeys: String, CodingKey { case wetsuit, tempC, line }
    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        wetsuit = (try? c?.decodeIfPresent(Bool.self, forKey: .wetsuit)) ?? nil
        tempC = (try? c?.decodeIfPresent(Int.self, forKey: .tempC)) ?? nil
        line = ((try? c?.decodeIfPresent(String.self, forKey: .line)) ?? nil) ?? ""
    }

    /* The switch on is a note in itself, even with nothing else filled in. */
    public static func make(on: Bool, wetsuit: Bool?, temp: String, line: String) -> OpenWaterNote? {
        guard on else { return nil }
        let t = Int(temp.trimmingCharacters(in: .whitespaces))
        return OpenWaterNote(wetsuit: wetsuit, tempC: t.flatMap { (-5...50).contains($0) ? $0 : nil },
                             line: line.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
