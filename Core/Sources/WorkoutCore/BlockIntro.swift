import Foundation

/*
 * Block intro (round 30, pick 18): at the start of each block of the plan, what
 * it is for, what will feel different and one thing to watch. The pure part:
 * the texts, which block a day is in, and for how many days the card shows.
 * The block names come from the plan's own phase names ("Base 2 \u{2014} Aerobic
 * Development"), read the way the season bars read them.
 */

public enum BlockKind: String, Codable, Sendable, CaseIterable {
    case base, build, peak, taper, raceWeek, postSeason, easyWeek
}

public struct BlockIntroText: Equatable, Sendable {
    public let forIt: String
    public let different: String
    public let watch: String
}

/* A block of the plan: its kind, the name shown ("Build 1") and its first and last day. */
public struct BlockSpan: Equatable, Sendable {
    public let kind: BlockKind
    public let name: String
    public let first: String
    public let last: String
    public init(kind: BlockKind, name: String, first: String, last: String) {
        self.kind = kind; self.name = name; self.first = first; self.last = last
    }
}

/* One plan week as the block reading needs it. */
public struct BlockWeek: Equatable, Sendable {
    public let monday: String
    public let phase: String
    public let isEasy: Bool
    public init(monday: String, phase: String, isEasy: Bool) { self.monday = monday; self.phase = phase; self.isEasy = isEasy }
}

public enum BlockIntro {
    /* The card shows on the first three days of a block. */
    public static let showDays = 3

    public static func shelfKey(first: String) -> String { "coach/blockintro/" + first }

    /* "Base 2 \u{2014} Aerobic Development" is "Base 2". */
    public static func shortName(_ phase: String) -> String {
        var t = phase.trimmingCharacters(in: .whitespaces)
        for cut in [" \u{2014} ", " \u{2013} ", " - ", ": ", " ("] {
            if let r = t.range(of: cut), t.distance(from: t.startIndex, to: r.lowerBound) >= 2 { t = String(t[..<r.lowerBound]) }
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? phase : t
    }

    /* The kind a phase name means; nil for a name the table does not know. */
    public static func kind(ofPhase phase: String) -> BlockKind? {
        let n = shortName(phase).lowercased()
        if n.hasPrefix("base") { return .base }
        if n.hasPrefix("build") { return .build }
        if n.hasPrefix("peak") { return .peak }
        if n.hasPrefix("taper") { return .taper }
        if n.hasPrefix("race") { return .raceWeek }
        if n.hasPrefix("post") { return .postSeason }
        return nil
    }

    public static func text(_ kind: BlockKind) -> BlockIntroText {
        switch kind {
        case .base:
            return BlockIntroText(forIt: "Building an easy, steady engine and good habits.",
                                  different: "Sessions are mostly easy and a little longer; it can feel too gentle.",
                                  watch: "Do not chase pace; finish each session feeling you could do a little more.")
        case .build:
            return BlockIntroText(forIt: "Adding harder work on top of the base you have built.",
                                  different: "A few sessions are firmer and the long ones get longer.",
                                  watch: "Keep the easy days easy so the hard days can be good.")
        case .peak:
            return BlockIntroText(forIt: "Practising the race effort and the race routine.",
                                  different: "The biggest weeks of the plan, with sessions that look like race day.",
                                  watch: "Fuel and sleep the way you will on race day.")
        case .taper:
            return BlockIntroText(forIt: "Letting the work you have done settle in before the race.",
                                  different: "Fewer minutes, the same sharpness; the legs can feel restless.",
                                  watch: "Resist adding extra sessions.")
        case .raceWeek:
            return BlockIntroText(forIt: "Arriving at the start line fresh and ready.",
                                  different: "Short, easy sessions, with time for kit, food and travel.",
                                  watch: "Check kit and times early, and keep things simple.")
        case .postSeason:
            return BlockIntroText(forIt: "Resting and enjoying movement without a plan to follow.",
                                  different: "Fewer sessions and no targets.",
                                  watch: "Let the appetite for training come back by itself.")
        case .easyWeek:
            return BlockIntroText(forIt: "Letting the last weeks of work settle in.",
                                  different: "Shorter sessions and a lighter week.",
                                  watch: "Let it be easy; it is part of the plan, not a day lost.")
        }
    }

    /*
     * The blocks of the plan, in order: each run of weeks with the same phase
     * name, a lone easy week inside a phase, and the week of the race. A week
     * that starts a phase is never also an easy-week block, and the race week
     * takes the place of whatever phase it is in for its own days.
     */
    public static func blocks(weeks: [BlockWeek], raceDay: String?) -> [BlockSpan] {
        let sorted = weeks.sorted { $0.monday < $1.monday }
        var out: [BlockSpan] = []
        var previousPhase: String?
        for w in sorted {
            let phase = w.phase.trimmingCharacters(in: .whitespaces)
            let starts = phase != previousPhase
            previousPhase = phase
            let end = PlanView.addDays(w.monday, 6)
            if let raceDay, raceDay >= w.monday, raceDay <= end {
                out.append(BlockSpan(kind: .raceWeek, name: "Race week", first: w.monday, last: end))
                continue
            }
            if starts, let kind = kind(ofPhase: phase) {
                out.append(BlockSpan(kind: kind, name: shortName(phase), first: w.monday, last: end))
            } else if w.isEasy {
                out.append(BlockSpan(kind: .easyWeek, name: "Easy week", first: w.monday, last: end))
            }
        }
        return out
    }

    /* The block that starts at or before `day` and was the last to start: the one a day is in. */
    public static func block(on day: String, weeks: [BlockWeek], raceDay: String?) -> BlockSpan? {
        let all = blocks(weeks: weeks, raceDay: raceDay)
        let phaseOf = weeks.sorted { $0.monday < $1.monday }
        // The day's week decides: race week and easy week for their own week, else the phase it is in.
        if let b = all.first(where: { ($0.kind == .raceWeek || $0.kind == .easyWeek) && day >= $0.first && day <= $0.last }) { return b }
        guard let week = phaseOf.last(where: { $0.monday <= day }), let kind = kind(ofPhase: week.phase) else { return nil }
        let name = shortName(week.phase)
        // A phase's first day is the Monday of its first week in the unbroken run of that name.
        var start = week.monday
        for w in phaseOf.reversed() where w.monday <= week.monday {
            if shortName(w.phase) == name { start = w.monday } else { break }
        }
        return BlockSpan(kind: kind, name: name, first: start, last: PlanView.addDays(week.monday, 6))
    }

    /* How many days into the block a day is (0 on its first day), or nil before it. */
    public static func dayInBlock(_ day: String, _ block: BlockSpan) -> Int? {
        day >= block.first ? Stats.daysBetween(block.first, day) : nil
    }

    /* The card shows on the first three days of a block, until it is put away. */
    public static func isShowing(on day: String, block: BlockSpan, seen: Bool) -> Bool {
        guard !seen, let n = dayInBlock(day, block) else { return false }
        return n < showDays
    }
}
