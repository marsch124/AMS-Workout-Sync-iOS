import Foundation

/*
 * Round 30, pick 11 (race-plan lane): course pacing. The bike course and the
 * run cut into sections, each with a pulse range from his threshold pulse
 * (LTHR) and, where he has the numbers, a power range (bike: his FTP; run: the
 * power his steady runs carried from the foot pod). Nothing is a fixed number:
 * change his test and every target moves. Easier on climbs, steady on the flat.
 *
 * Shares of LTHR for the bike: flat 85–90 %, rolling 84–89 %, turns 83–88 %,
 * climb 81–87 %, downhill under 85 %. Shares of FTP (a 70.3 rides about 75–82 %):
 * flat 75–82, rolling 74–80, turns 70–78, climb 72–78, downhill up to 60.
 * Run laps: the first lap 82–88 % (settle after the bike), middle laps 85–90 %,
 * the last lap 87–93 % (open up if it feels good); a climb 3 points lower.
 * Run power: first lap 94–99 % of his steady-run power, middle 97–102, last 99–105.
 */
public struct PacingTarget: Equatable, Sendable, Identifiable {
    public var id: String { section.id }
    public let section: CourseSection
    public let pulseLow: Int?
    public let pulseHigh: Int?
    public let powerLow: Int?
    public let powerHigh: Int?
    /* "easier" on a climb, "steady" on the flat … */
    public let effort: String
}

public enum RaceSectionRules {
    static func w(_ x: Double) -> Int { Int(x.rounded(.toNearestOrAwayFromZero)) }

    static func bikeShares(_ k: CourseKind) -> (hr: (Double, Double), pw: (Double, Double), effort: String) {
        switch k {
        case .flat: return ((0.85, 0.90), (0.75, 0.82), "Steady")
        case .rolling: return ((0.84, 0.89), (0.74, 0.80), "Steady, even on the rises")
        case .turns: return ((0.83, 0.88), (0.70, 0.78), "Smooth through the turns")
        case .climb: return ((0.81, 0.87), (0.72, 0.78), "Easier on the climb")
        case .descent: return ((0.70, 0.85), (0.0, 0.60), "Let it recover")
        }
    }

    public static func bike(_ course: RaceCourse, lthr: Double?, ftp: Double?) -> [PacingTarget] {
        course.bike.map { s in
            let sh = bikeShares(s.kind)
            let hr = lthr.map { (w($0 * sh.hr.0), w($0 * sh.hr.1)) }
            let pw = ftp.map { (w($0 * sh.pw.0), w($0 * sh.pw.1)) }
            return PacingTarget(section: s, pulseLow: hr?.0, pulseHigh: hr?.1, powerLow: pw?.0, powerHigh: pw?.1, effort: sh.effort)
        }
    }

    public static func run(_ course: RaceCourse, lthr: Double?, runPowerW: Double?) -> [PacingTarget] {
        let n = course.run.count
        return course.run.enumerated().map { i, s in
            let first = i == 0, last = i == n - 1 && n > 1
            var hr: (Double, Double) = first ? (0.82, 0.88) : last ? (0.87, 0.93) : (0.85, 0.90)
            var pw: (Double, Double) = first ? (0.94, 0.99) : last ? (0.99, 1.05) : (0.97, 1.02)
            var effort = first ? "Settle in after the bike" : last ? "Open up if it feels good" : "Steady"
            if s.kind == .climb { hr = (hr.0 - 0.03, hr.1 - 0.03); pw = (pw.0 - 0.04, pw.1 - 0.04); effort = "Easier on the climb" }
            return PacingTarget(section: s, pulseLow: lthr.map { w($0 * hr.0) }, pulseHigh: lthr.map { w($0 * hr.1) },
                                powerLow: runPowerW.map { w($0 * pw.0) }, powerHigh: runPowerW.map { w($0 * pw.1) }, effort: effort)
        }
    }
}
