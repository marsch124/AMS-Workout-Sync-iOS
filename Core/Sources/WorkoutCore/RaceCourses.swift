import Foundation

/*
 * Round 30 (race-plan lane): what is public about a race course, in one place.
 * Every figure here is a public fact about a course or past public results,
 * never one of his own numbers. A race whose name says Jönköping gets that
 * course; any other race gets a plain flat 70.3 course.
 *
 * The Jönköping figures come from round-30/facts/jonkoping.md; [unsure] marks a figure whose
 * source is thin. Nothing here is ever shown as his.
 */

/* What a stretch of course is like. Drives the target: easier on a climb, steady on the flat. */
public enum CourseKind: String, Codable, Sendable {
    case flat, rolling, climb, descent, turns

    public var word: String {
        switch self {
        case .flat: return "Flat"
        case .rolling: return "Rolling"
        case .climb: return "Climb"
        case .descent: return "Downhill"
        case .turns: return "Turns"
        }
    }
}

public struct CourseSection: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(fromKm)-\(toKm)" }
    public var fromKm: Double
    public var toKm: Double
    public var kind: CourseKind
    public var note: String
    public var lengthKm: Double { max(0, toKm - fromKm) }
    public init(_ fromKm: Double, _ toKm: Double, _ kind: CourseKind, _ note: String = "") {
        self.fromKm = fromKm; self.toKm = toKm; self.kind = kind; self.note = note
    }
}

/* Times for the five parts, in seconds. */
public struct LegTimes: Codable, Equatable, Sendable {
    public var swim: Int, t1: Int, bike: Int, t2: Int, run: Int
    public init(swim: Int, t1: Int, bike: Int, t2: Int, run: Int) {
        self.swim = swim; self.t1 = t1; self.bike = bike; self.t2 = t2; self.run = run
    }
    public func seconds(_ leg: RaceLeg) -> Int {
        switch leg { case .swim: return swim; case .t1: return t1; case .bike: return bike; case .t2: return t2; case .run: return run }
    }
}

/* A five-year age group, as triathlon results are cut: 45–49. */
public struct AgeBracket: Codable, Equatable, Hashable, Sendable {
    public var lo: Int
    public var hi: Int
    public init(lo: Int, hi: Int) { self.lo = lo; self.hi = hi }
    public var label: String { hi >= 99 ? "\(lo)+" : "\(lo)\u{2013}\(hi)" }
    /* 18–24, 25–29 … 70–74, 75+. */
    public static let all: [AgeBracket] =
        [AgeBracket(lo: 18, hi: 24)] + stride(from: 25, through: 70, by: 5).map { AgeBracket(lo: $0, hi: $0 + 4) } + [AgeBracket(lo: 75, hi: 99)]
    public static func containing(age: Int) -> AgeBracket? { all.first { age >= $0.lo && age <= $0.hi } }
    public static func from(label: String) -> AgeBracket? { all.first { $0.label == label } }

    /*
     * The age group he races in: the age on 31 December of the race year (the
     * federation's rule [unsure for this event]). From his age today it is that
     * many years on, counted by calendar year.
     */
    public static func atRace(ageNow: Int, thisYear: Int, raceYear: Int) -> AgeBracket? {
        containing(age: ageNow + max(0, raceYear - thisYear))
    }
}

public struct CourseAgeGroup: Codable, Equatable, Sendable {
    public var bracket: String
    /* The middle of the group's past finishers and the faster quarter (25th percentile), per part; `topThird` keeps its old name. */
    public var middle: LegTimes
    public var topThird: LegTimes
    public init(bracket: String, middle: LegTimes, topThird: LegTimes) { self.bracket = bracket; self.middle = middle; self.topThird = topThird }
}

public struct RaceCourse: Codable, Equatable, Sendable {
    public var name: String
    public var swimMetres: Int
    public var bikeKm: Double
    public var runKm: Double
    /* Total climbing in metres. */
    public var bikeClimbM: Double
    public var runClimbM: Double
    /* Typical time for the change-overs on this course, seconds. */
    public var t1: Int
    public var t2: Int
    /* A typical July afternoon, degrees Celsius. */
    public var julyTempC: Double
    public var bike: [CourseSection]
    public var run: [CourseSection]
    public var ageGroups: [CourseAgeGroup]
    /* Where the figures come from, for the small print. */
    public var source: String
    public var isPlaceholder: Bool

    /* Only the start of the first climb and the aid stations are public: the sections are a rough split. */
    public var sectionsApproximate: Bool { name.contains("Jönköping") }

    public func ageGroup(_ b: AgeBracket) -> CourseAgeGroup? { ageGroups.first { $0.bracket == b.label } }

    /* The course for a race named so; Jönköping by name, else a plain flat one. Case and accents do not matter. */
    public static func forRace(title: String) -> RaceCourse {
        let t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return t.contains("jonkoping") ? jonkoping : flatDefault
    }

    public static let flatDefault = RaceCourse(
        name: "Flat 70.3 course", swimMetres: 1900, bikeKm: 90, runKm: 21.1, bikeClimbM: 0, runClimbM: 0,
        t1: 240, t2: 120, julyTempC: 18,
        bike: [CourseSection(0, 30, .flat), CourseSection(30, 60, .flat), CourseSection(60, 90, .flat)],
        run: [CourseSection(0, 7, .flat, "Lap 1"), CourseSection(7, 14, .flat, "Lap 2"), CourseSection(14, 21.1, .flat, "Lap 3")],
        ageGroups: [], source: "A plain flat half-distance course; no past results.", isPlaceholder: false)

    /*
     * IRONMAN 70.3 Jönköping, from round-30/facts/jonkoping.md (public sources, 27 Nov 2026).
     * Used: 1.9 km swim (lake; venue disagreed between sources [unsure]), 90 km one-loop bike,
     * ~820 m climbing (sources say 450–870 m; 819 m from a route file [unsure]), 21.1 km run in two
     * loops, ~150 m climbing [unsure], July day high 22 °C (21 and 23.3 °C in two sources).
     * Bike sections are APPROXIMATE: only the aid stations (21, 39, 58, 79 km [unsure]) and the
     * first climb (about 2.1 km, 94 m [unsure]) are known; the rest "rolling with technical
     * descents" [unsure]. Change-overs: the sources give only T1+T2 together, about 13 min for the
     * middle of the age groups (derived [unsure]); 7m30s + 5m is used here. Age-group figures:
     * men, mean over the 2019, 2022 and 2023 editions of the median and of the faster quarter
     * (25th percentile) of finishers [derived from finisher lists]; changeovers are T1+T2 together
     * (held in `t1`, with `t2` zero). The sources hold no women's results.
     */
    public static let jonkoping = RaceCourse(
        name: "IRONMAN 70.3 Jönköping", swimMetres: 1900, bikeKm: 90, runKm: 21.1, bikeClimbM: 820, runClimbM: 150,
        t1: 450, t2: 300, julyTempC: 22,
        bike: [CourseSection(0, 21, .climb, "Starts with the first climb, about 2 km"),
               CourseSection(21, 39, .rolling, "Rolling"),
               CourseSection(39, 58, .rolling, "Rolling"),
               CourseSection(58, 79, .turns, "Technical descents"),
               CourseSection(79, 90, .rolling, "Rolling back towards the city")],
        run: [CourseSection(0, 10.55, .flat, "Loop 1: city centre and the beaches"), CourseSection(10.55, 21.1, .flat, "Loop 2: finish in the city centre")],
        ageGroups: [
            ag("45\u{2013}49", [2510, 750, 10200, 0, 7250], [2220, 620, 9560, 0, 6430]),
            ag("50\u{2013}54", [2490, 780, 10370, 0, 7350], [2220, 620, 9600, 0, 6610]),
            ag("55\u{2013}59", [2560, 800, 10400, 0, 7590], [2260, 660, 9920, 0, 6870]),
            ag("60\u{2013}64", [2680, 870, 10940, 0, 7980], [2310, 720, 10220, 0, 7200]),
            ag("65\u{2013}69", [3040, 920, 11520, 0, 8640], [2640, 820, 11050, 0, 7580]),
        ],
        source: "Public pages and finisher lists, 2019, 2022 and 2023; bike sections approximate.", isPlaceholder: false)

    private static func ag(_ b: String, _ m: [Int], _ t: [Int]) -> CourseAgeGroup {
        CourseAgeGroup(bracket: b, middle: LegTimes(swim: m[0], t1: m[1], bike: m[2], t2: m[3], run: m[4]),
                       topThird: LegTimes(swim: t[0], t1: t[1], bike: t[2], t2: t[3], run: t[4]))
    }
}
