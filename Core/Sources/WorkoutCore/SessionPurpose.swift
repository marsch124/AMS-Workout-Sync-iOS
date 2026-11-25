import Foundation

/*
 * "Why this session?" (round 28, pick 41): one plain line under a planned
 * session's title, worked out by fixed rules — never by a model, never stored.
 *
 * It reuses the rule book's own way of classing a session (`RuleBook.labels`,
 * `RuleBook.zones`, `RuleBook.sessionClass` in RuleBookClassing.swift) so the
 * words here and the Adjustment Guide can never disagree about what is hard,
 * easy, long or a test. What this adds: the sport, how long the session is
 * against the others of its sport, the phase, and easy weeks.
 *
 * A kind the rules cannot name gives no line at all.
 */

public enum PurposeKind: String, CaseIterable, Sendable {
    case race, test, rehearsal, postSeason, taperSharpener, taperEasy, brick, easyWeek
    case strengthHeavy, strengthLight, mobility
    case swimTechnique, swimThreshold, swimAerobic
    case longEndurance, vo2, peakQuality, tempo, threshold, recovery, easyAerobic
}

public struct PurposeInput: Equatable, Sendable {
    /* The discipline id: swim, bike, run, strength, mobility, brick, race, rest … */
    public var sport: String
    public var title: String
    public var intensity: String
    public var plannedMin: Int
    public var phase: String
    public var isKey: Bool
    /* The usual planned minutes of this sport in the plan (its median); nil when not known. */
    public var typicalMin: Int?
    /* The plan's tag for the session's week (easy, test, race …) when known. */
    public var weekTag: RBWeekTag?

    public init(sport: String, title: String, intensity: String = "", plannedMin: Int = 0, phase: String = "",
                isKey: Bool = false, typicalMin: Int? = nil, weekTag: RBWeekTag? = nil) {
        self.sport = sport; self.title = title; self.intensity = intensity; self.plannedMin = plannedMin
        self.phase = phase; self.isKey = isKey; self.typicalMin = typicalMin; self.weekTag = weekTag
    }
}

public enum SessionPurpose {

    /* The median of a list of planned minutes (zero lengths left out); nil for an empty list. */
    public static func typicalMinutes(_ minutes: [Int]) -> Int? {
        let m = minutes.filter { $0 > 0 }.sorted()
        guard !m.isEmpty else { return nil }
        return m[m.count / 2]
    }

    public static func line(_ input: PurposeInput) -> String? {
        kind(input).map { "Why: " + words(for: $0) }
    }

    /* The sentence, without its "Why: ". */
    public static func words(for kind: PurposeKind) -> String {
        switch kind {
        case .race: return "race day \u{2014} everything in the plan points here."
        case .test: return "a test \u{2014} it gives your zones fresh numbers to work from."
        case .rehearsal: return "a race rehearsal \u{2014} practise pacing, food and kit at race effort."
        case .postSeason: return "post-season \u{2014} keeps you moving, with no pressure on the numbers."
        case .taperSharpener: return "a short, sharp one \u{2014} keeps your legs awake while the rest of the week eases off."
        case .taperEasy: return "easy on purpose \u{2014} keeps you loose while you save energy for race day."
        case .brick: return "bike straight into run \u{2014} teaches your legs to run when they are already tired."
        case .easyWeek: return "an easy week \u{2014} time to soak up the work of the weeks before."
        case .strengthHeavy: return "heavy strength \u{2014} builds the power and sturdiness that carry the rest of your training."
        case .strengthLight: return "lighter strength \u{2014} keeps your body sturdy without taking much out of you."
        case .mobility: return "mobility \u{2014} keeps your joints moving freely so the harder days go smoothly."
        case .swimTechnique: return "a technique swim \u{2014} smoother strokes first, distance later."
        case .swimThreshold: return "a hard swim \u{2014} practises holding a fast pace for longer."
        case .swimAerobic: return "an aerobic swim \u{2014} builds your base in the water at a pace you can keep up."
        case .longEndurance: return "builds the aerobic base \u{2014} long and easy on purpose."
        case .vo2: return "short, hard intervals \u{2014} they push up the top end of your effort."
        case .peakQuality: return "race-pace work \u{2014} it sharpens the effort you will use on race day."
        case .tempo: return "a steady, comfortably hard effort \u{2014} builds the pace you can hold for longer."
        case .threshold: return "threshold work \u{2014} raises the effort you can keep going at."
        case .recovery: return "recovery \u{2014} very easy, just to keep the legs moving."
        case .easyAerobic: return "easy aerobic \u{2014} builds your base without costing much."
        }
    }

    public static func kind(_ i: PurposeInput) -> PurposeKind? {
        if i.sport == "mobility" { return .mobility }
        let sport = RBSport(disciplineID: i.sport)
        if sport == .rest || sport == .other { return nil }
        let s = RBSession(id: "purpose", day: "", sport: sport, title: i.title, plannedMin: i.plannedMin,
                          intensity: i.intensity, star: i.isKey, phase: i.phase, originalWeek: 0)
        let l = RuleBook.labels(s)
        let z = RuleBook.zones(i.intensity)
        let cls = RuleBook.sessionClass(s)
        let title = normalise(i.title)
        let phase = normalise(i.phase)

        // The days that matter most name themselves first.
        if l.race { return .race }
        if l.test || title.hasPrefix("test") { return .test }
        if l.sim { return .rehearsal }
        if phase.contains("post") { return .postSeason }

        let endurance = sport == .swim || sport == .bike || sport == .run
        if phase.contains("taper") && endurance {
            return (cls == .hard || cls == .moderate || (z.top ?? 0) >= 3) ? .taperSharpener : .taperEasy
        }
        if l.brick || sport == .brick { return .brick }

        switch sport {
        case .strength:
            return cls == .heavyStrength ? .strengthHeavy : .strengthLight
        default: break
        }
        if title.contains("mobility") || title.contains("stretch") || title.contains("yoga") { return .mobility }

        let easyWeek = i.weekTag == .easy && endurance && cls != .hard

        if sport == .swim {
            if easyWeek { return .easyWeek }
            if title.contains("technique") || title.contains("drill") { return .swimTechnique }
            guard z.top != nil else { return nil }
            if cls == .hard { return .swimThreshold }
            return .swimAerobic
        }

        // Bike and run.
        let longByLength: Bool = {
            guard let typical = i.typicalMin, typical > 0 else { return false }
            return i.plannedMin >= 60 && Double(i.plannedMin) >= Double(typical) * 1.3
        }()
        if (l.long || longByLength) && cls != .hard { return easyWeek ? .easyWeek : .longEndurance }
        if easyWeek { return .easyWeek }

        switch cls {
        case .hard:
            let top = z.top ?? 0
            if top >= 5 { return .vo2 }
            if phase.contains("peak") { return .peakQuality }
            return top == 4 ? .threshold : .tempo
        case .moderate:
            return .tempo
        case .easy:
            if z.top == 1 || title.contains("recovery") { return .recovery }
            return .easyAerobic
        case .other:
            // A key session held to easy zones (the star keeps it out of "easy").
            if let top = z.top, top <= 2 { return .easyAerobic }
            return nil
        case .heavyStrength:
            return nil
        }
    }
}
