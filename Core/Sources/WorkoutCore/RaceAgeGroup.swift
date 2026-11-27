import Foundation

/*
 * Round 30, pick 19 (race-plan lane): where he would gain most. His likely time
 * per leg (the forecast's middle) against the middle of his age group and the
 * top third of past results on the same course. Calm: it says what is, never
 * judges. The "biggest gain" is the swim, bike or run part that is furthest
 * behind the middle of the group; if none is behind, no part is marked.
 */
public struct LegGap: Equatable, Sendable {
    public let leg: RaceLeg
    public let likely: Int
    public let middle: Int
    public let top: Int
    /* Positive: slower than the middle (a gain to find). */
    public var behindMiddle: Int { likely - middle }
    public var behindTop: Int { likely - top }
}

public struct RaceComparison: Equatable, Sendable {
    public let gaps: [LegGap]
    public let biggest: RaceLeg?
    public let bracket: String

    /* Nil when the course has no past results for his age group or the forecast lacks a part. */
    public static func make(_ f: RaceForecast, course: RaceCourse, bracket: AgeBracket) -> RaceComparison? {
        guard let group = course.ageGroup(bracket) else { return nil }
        let legs: [RaceLeg] = [.swim, .bike, .run]
        var gaps: [LegGap] = []
        for l in legs {
            guard let mid = f.leg(l)?.mid else { return nil }
            gaps.append(LegGap(leg: l, likely: mid, middle: group.middle.seconds(l), top: group.topThird.seconds(l)))
        }
        let worst = gaps.max { $0.behindMiddle < $1.behindMiddle }
        let biggest = (worst?.behindMiddle ?? 0) > 60 ? worst?.leg : nil
        // The sources give T1 and T2 only together: one "Changeovers" row, never the biggest gain.
        if let a = f.leg(.t1)?.mid, let b = f.leg(.t2)?.mid {
            gaps.append(LegGap(leg: .t1, likely: a + b, middle: group.middle.t1 + group.middle.t2, top: group.topThird.t1 + group.topThird.t2))
        }
        return RaceComparison(gaps: gaps, biggest: biggest, bracket: bracket.label)
    }

    /* "14 min", or "1h 05m" when over an hour. */
    public static func amount(_ seconds: Int) -> String {
        let s = abs(seconds)
        return s >= 3600 ? formatDuration(Double(s)) : "\(max(1, Int((Double(s) / 60).rounded()))) min"
    }

    /* "Bike: 14 min behind the middle of your age group — the biggest gain" */
    public func line(_ g: LegGap) -> String {
        let name = g.leg == .t1 ? "Changeovers" : g.leg.word
        let d = g.behindMiddle
        var text: String
        if abs(d) < 60 { text = "\(name): level with the middle of your age group" }
        else if d > 0 { text = "\(name): \(Self.amount(d)) behind the middle of your age group" }
        else { text = "\(name): \(Self.amount(d)) ahead of the middle of your age group" }
        if biggest == g.leg { text += " \u{2014} the biggest gain" }
        return text
    }

    /* The grey line under it: against the fastest quarter. */
    public func topLine(_ g: LegGap) -> String {
        let d = g.behindTop
        if abs(d) < 60 { return "Level with the fastest quarter" }
        return d > 0 ? "\(Self.amount(d)) from the fastest quarter" : "\(Self.amount(d)) inside the fastest quarter"
    }
}

/* His own pick of age group (shelf `raceplan/agegroup`); without it the age group comes from Garmin. */
public struct AgeGroupChoice: Codable, Equatable, Sendable {
    public var label: String
    public init(label: String) { self.label = label }
}
