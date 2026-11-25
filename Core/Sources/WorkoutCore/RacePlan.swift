import Foundation

/*
 * The race page's rules (round 28, pick 25). Pure: nothing here reads the plan
 * or draws. The app NEVER works out a pace, a speed or a prediction: it only
 * adds up the times he typed, and divides his own grams by his own hours.
 *
 * Kept on the shelf, one key each, under `race/<race day>/…`:
 *   pacing    -> RacePacing      his five target times and the leg lines
 *   fuel      -> RaceFuel        his fuel rows, in his order
 *   checklist -> RaceChecklist   the kit list and what is packed
 * Every type decodes an older or newer value without failing (new fields have defaults).
 */

public enum RaceKeys {
    /* The race is named by its day ("2027-07-11"), which is what the plan holds. */
    public static func pacing(_ raceDay: String) -> String { "race/\(raceDay)/pacing" }
    public static func fuel(_ raceDay: String) -> String { "race/\(raceDay)/fuel" }
    public static func checklist(_ raceDay: String) -> String { "race/\(raceDay)/checklist" }
}

// MARK: - the five parts of the day

public enum RaceLeg: String, CaseIterable, Sendable {
    case swim, t1, bike, t2, run

    public var word: String {
        switch self {
        case .swim: return "Swim"
        case .t1: return "T1"
        case .bike: return "Bike"
        case .t2: return "T2"
        case .run: return "Run"
        }
    }

    /* A change-over is typed as minutes and seconds, a leg as hours and minutes. */
    public var isChangeOver: Bool { self == .t1 || self == .t2 }
}

public struct RacePacing: Codable, Equatable, Sendable {
    /* Seconds he typed, per part; nil = not typed. */
    public var swim: Int?
    public var t1: Int?
    public var bike: Int?
    public var t2: Int?
    public var run: Int?
    /* "pulse Z2", "power 150–160 W", "by feel" — his own words. */
    public var swimNote: String
    public var bikeNote: String
    public var runNote: String

    public init(swim: Int? = nil, t1: Int? = nil, bike: Int? = nil, t2: Int? = nil, run: Int? = nil,
                swimNote: String = "", bikeNote: String = "", runNote: String = "") {
        self.swim = swim; self.t1 = t1; self.bike = bike; self.t2 = t2; self.run = run
        self.swimNote = swimNote; self.bikeNote = bikeNote; self.runNote = runNote
    }

    private enum Key: String, CodingKey { case swim, t1, bike, t2, run, swimNote, bikeNote, runNote }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func secs(_ k: Key) -> Int? {
            guard let n = try? c.decodeIfPresent(Int.self, forKey: k), n > 0 else { return nil }
            return n
        }
        swim = secs(.swim); t1 = secs(.t1); bike = secs(.bike); t2 = secs(.t2); run = secs(.run)
        swimNote = (try? c.decodeIfPresent(String.self, forKey: .swimNote)) ?? ""
        bikeNote = (try? c.decodeIfPresent(String.self, forKey: .bikeNote)) ?? ""
        runNote = (try? c.decodeIfPresent(String.self, forKey: .runNote)) ?? ""
    }

    public func seconds(_ leg: RaceLeg) -> Int? {
        switch leg {
        case .swim: return swim
        case .t1: return t1
        case .bike: return bike
        case .t2: return t2
        case .run: return run
        }
    }

    public mutating func set(_ leg: RaceLeg, _ value: Int?) {
        let v = (value ?? 0) > 0 ? value : nil
        switch leg {
        case .swim: swim = v
        case .t1: t1 = v
        case .bike: bike = v
        case .t2: t2 = v
        case .run: run = v
        }
    }

    public func note(_ leg: RaceLeg) -> String {
        switch leg {
        case .swim: return swimNote
        case .bike: return bikeNote
        case .run: return runNote
        default: return ""
        }
    }

    public mutating func setNote(_ leg: RaceLeg, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch leg {
        case .swim: swimNote = t
        case .bike: bikeNote = t
        case .run: runNote = t
        default: break
        }
    }

    public var isEmpty: Bool { RaceLeg.allCases.allSatisfy { seconds($0) == nil } && swimNote.isEmpty && bikeNote.isEmpty && runNote.isEmpty }

    /* The five times added up — only the ones he typed — and how many that was. */
    public struct Finish: Equatable, Sendable {
        public let seconds: Int
        public let typed: Int
        public var complete: Bool { typed == RaceLeg.allCases.count }
    }

    public var finish: Finish? {
        let typed = RaceLeg.allCases.compactMap { seconds($0) }
        guard !typed.isEmpty else { return nil }
        return Finish(seconds: typed.reduce(0, +), typed: typed.count)
    }

    /* "1h 10m", "4m 30s" — a change-over keeps its seconds, a leg shows hours and minutes. */
    public static func words(_ seconds: Int, changeOver: Bool) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if changeOver {
            if h > 0 { return "\(h)h\u{00A0}" + String(format: "%02dm", m) }
            if m > 0 { return s > 0 ? "\(m)m\u{00A0}" + String(format: "%02ds", s) : "\(m)m" }
            return "\(s)s"
        }
        if h > 0 { return "\(h)h\u{00A0}" + String(format: "%02dm", m) }
        return "\(m)m"
    }

    /*
     * What he typed into a time box, in seconds; nil when it is empty or not a time.
     * A leg: "1:10" or "1h 10m" or "70" (minutes) -> hours and minutes.
     * A change-over: "4:30" or "4m 30s" or "5" (minutes) -> minutes and seconds.
     */
    public static func parse(_ text: String, changeOver: Bool) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        if t.contains(":") {
            let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.allSatisfy({ $0 != nil }), parts.count <= 3 else { return nil }
            let n = parts.compactMap { $0 }
            if n.contains(where: { $0 < 0 }) { return nil }
            let total: Int
            switch n.count {
            case 3: total = n[0] * 3600 + n[1] * 60 + n[2]
            default: total = changeOver ? n[0] * 60 + n[1] : n[0] * 3600 + n[1] * 60
            }
            return total > 0 ? total : nil
        }
        // Words: "1h 10m", "4m 30s", "90 min", or a bare number (minutes).
        var total = 0.0
        var number = ""
        var unit = ""
        var any = false
        func flush() -> Bool {
            if number.isEmpty { return unit.isEmpty }
            guard let v = Double(number), v >= 0 else { return false }
            switch unit.first {
            case "h": total += v * 3600
            case "s": total += v
            case "m", nil: total += v * 60
            default: return false
            }
            if !unit.isEmpty, !["h", "hr", "hrs", "hour", "hours", "m", "min", "mins", "minute", "minutes", "s", "sec", "secs", "second", "seconds"].contains(unit) { return false }
            number = ""; unit = ""; any = true
            return true
        }
        for ch in t {
            if ch.isNumber || ch == "." {
                if !unit.isEmpty { if !flush() { return nil } }
                number.append(ch)
            } else if ch.isLetter {
                if number.isEmpty { return nil }
                unit.append(ch)
            } else if ch == " " {
                continue
            } else {
                return nil
            }
        }
        if !flush() { return nil }
        guard any else { return nil }
        let r = Int(total.rounded())
        return r > 0 ? r : nil
    }
}

// MARK: - the race, by its name

public enum RaceKind {
    /* The distances in words, when the plan's race names its kind ("half", "70.3", "olympic", "sprint", "full"). Else nil. */
    public static func distances(fromTitle title: String) -> [RaceLeg: String]? {
        let t = title.lowercased()
        func make(_ swim: String, _ bike: String, _ run: String) -> [RaceLeg: String] { [.swim: swim, .bike: bike, .run: run] }
        if t.contains("70.3") || t.contains("half") { return make("1.9 km", "90 km", "21.1 km") }
        if t.contains("sprint") { return make("750 m", "20 km", "5 km") }
        if t.contains("olympic") || t.contains("standard distance") { return make("1.5 km", "40 km", "10 km") }
        if t.contains("full distance") || t.contains("iron distance") || t.contains("140.6") || t.contains("ironman") {
            return make("3.8 km", "180 km", "42.2 km")
        }
        return nil
    }
}

// MARK: - the countdown

public struct RaceCountdown: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case ahead, raceWeek, today, done }
    public let phase: Phase
    /* The big figure: "228 days", "5 days", "Today", "Done". */
    public let figure: String
    /* Beside it: "32 weeks and 4 days"; nil in race week, today and after. */
    public let beside: String?

    /* `doneDate` is how the app writes his race day ("Sun 11 Jul"); only used afterwards. */
    public static func make(days: Int, doneDate: String) -> RaceCountdown {
        if days < 0 { return RaceCountdown(phase: .done, figure: "Done \u{00B7} " + doneDate, beside: nil) }
        if days == 0 { return RaceCountdown(phase: .today, figure: "Today", beside: nil) }
        let unit = days == 1 ? "1 day" : "\(days) days"
        if days <= 7 { return RaceCountdown(phase: .raceWeek, figure: unit, beside: nil) }
        let w = days / 7, d = days % 7
        var s = w == 1 ? "1 week" : "\(w) weeks"
        if d > 0 { s += " and " + (d == 1 ? "1 day" : "\(d) days") }
        return RaceCountdown(phase: .ahead, figure: unit, beside: s)
    }
}

// MARK: - fuel

public enum RaceFuelLeg: String, Codable, CaseIterable, Sendable {
    case before, bike, run

    public var word: String {
        switch self {
        case .before: return "Before"
        case .bike: return "Bike"
        case .run: return "Run"
        }
    }
}

public struct RaceFuelRow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var leg: RaceFuelLeg
    /* "every 20 min" */
    public var when: String
    /* "1 gel" */
    public var what: String
    /* Grams of carbohydrate for the whole row over its leg, as he types it. */
    public var carbs: Int

    public init(id: String = UUID().uuidString, leg: RaceFuelLeg = .bike, when: String = "", what: String = "", carbs: Int = 0) {
        self.id = id; self.leg = leg; self.when = when; self.what = what; self.carbs = carbs
    }

    private enum Key: String, CodingKey { case id, leg, when, what, carbs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        leg = (try? c.decodeIfPresent(RaceFuelLeg.self, forKey: .leg)) ?? .bike
        when = (try? c.decodeIfPresent(String.self, forKey: .when)) ?? ""
        what = (try? c.decodeIfPresent(String.self, forKey: .what)) ?? ""
        carbs = max(0, (try? c.decodeIfPresent(Int.self, forKey: .carbs)) ?? 0)
    }
}

public struct RaceFuel: Codable, Equatable, Sendable {
    public var rows: [RaceFuelRow]

    public init(rows: [RaceFuelRow] = []) { self.rows = rows }

    private enum Key: String, CodingKey { case rows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        rows = (try? c.decodeIfPresent([RaceFuelRow].self, forKey: .rows)) ?? []
    }

    /* Grams of carbohydrate on one leg: the sum of his rows for it. */
    public func grams(_ leg: RaceFuelLeg) -> Int { rows.filter { $0.leg == leg }.reduce(0) { $0 + $1.carbs } }

    public var totalGrams: Int { rows.reduce(0) { $0 + $1.carbs } }

    /*
     * Grams an hour for the bike or the run, from HIS leg time: his grams for that leg
     * divided by his hours for it. Nil when he has typed no time for it or no grams.
     * Rounded to a whole gram.
     */
    public func gramsPerHour(_ leg: RaceFuelLeg, pacing: RacePacing) -> Int? {
        let seconds: Int?
        switch leg {
        case .bike: seconds = pacing.bike
        case .run: seconds = pacing.run
        case .before: seconds = nil
        }
        guard let seconds, seconds > 0 else { return nil }
        let g = grams(leg)
        guard g > 0 else { return nil }
        return Int((Double(g) * 3600 / Double(seconds)).rounded())
    }
}

// MARK: - the kit checklist

public enum RaceKitGroup: String, Codable, CaseIterable, Sendable {
    case before, swim, bike, run, after

    public var word: String {
        switch self {
        case .before: return "Before"
        case .swim: return "Swim"
        case .bike: return "Bike"
        case .run: return "Run"
        case .after: return "After"
        }
    }
}

public struct RaceKitItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var group: RaceKitGroup
    public var name: String
    public var packed: Bool

    public init(id: String = UUID().uuidString, group: RaceKitGroup, name: String, packed: Bool = false) {
        self.id = id; self.group = group; self.name = name; self.packed = packed
    }

    private enum Key: String, CodingKey { case id, group, name, packed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        group = (try? c.decodeIfPresent(RaceKitGroup.self, forKey: .group)) ?? .before
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        packed = (try? c.decodeIfPresent(Bool.self, forKey: .packed)) ?? false
    }
}

public struct RaceChecklist: Codable, Equatable, Sendable {
    /* In his order within each group; the groups themselves are always Before, Swim, Bike, Run, After. */
    public var items: [RaceKitItem]

    public init(items: [RaceKitItem]) { self.items = items }

    private enum Key: String, CodingKey { case items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        items = (try? c.decodeIfPresent([RaceKitItem].self, forKey: .items)) ?? []
    }

    /* The starting list, with fixed ids so two devices that never changed it agree. */
    public static var starting: RaceChecklist {
        func i(_ g: RaceKitGroup, _ n: String) -> RaceKitItem { RaceKitItem(id: "start-\(g.rawValue)-\(n.lowercased().replacingOccurrences(of: " ", with: "-"))", group: g, name: n) }
        return RaceChecklist(items: [
            i(.before, "Race number"), i(.before, "Timing chip"), i(.before, "Sun cream"), i(.before, "Watch charged"),
            i(.swim, "Wetsuit"), i(.swim, "Goggles"), i(.swim, "Swim cap"), i(.swim, "Spare goggles"),
            i(.bike, "Helmet"), i(.bike, "Bike shoes"), i(.bike, "Bottles"), i(.bike, "Gels"), i(.bike, "Sunglasses"),
            i(.run, "Running shoes"), i(.run, "Race belt"), i(.run, "Cap"), i(.run, "Gels for the run"),
            i(.after, "Dry clothes"), i(.after, "Flip-flops"), i(.after, "Towel"), i(.after, "Recovery drink"),
        ])
    }

    /* The items as shown: group by group, his order inside each. */
    public var ordered: [RaceKitItem] {
        RaceKitGroup.allCases.flatMap { g in items.filter { $0.group == g } }
    }

    public var packedCount: Int { items.filter(\.packed).count }

    public func unticked() -> RaceChecklist {
        var c = self
        for i in c.items.indices { c.items[i].packed = false }
        return c
    }

    public func toggled(_ id: String) -> RaceChecklist {
        var c = self
        if let i = c.items.firstIndex(where: { $0.id == id }) { c.items[i].packed.toggle() }
        return c
    }
}

// MARK: - dragging into order

public enum RaceOrder {
    /*
     * The dragged one takes the place of the one it was dropped on; the others
     * close up around it. Works on any list with ids; unknown ids change nothing.
     */
    public static func move<T: Identifiable>(_ items: [T], _ id: T.ID, onto target: T.ID) -> [T] {
        guard id != target, let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target }) else { return items }
        var out = items
        let item = out.remove(at: from)
        out.insert(item, at: to)
        return out
    }
}
