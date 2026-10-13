import Foundation

/*
 * What a session cost, and what the costs add up to.
 *
 * The hours on Progress treat an easy hour and a brutal hour as the same
 * thing, which is the one place his plan could be kept to the letter and
 * still not be trained. Every platform that answers this turns a session
 * into a single number: TrainingPeaks from power, pace and heart rate.
 *
 * Here it is worked out from what his own sheet already holds — the time,
 * the average heart rate against his LTHR, failing that the effort he typed,
 * failing that the zone the plan asked for. The shape is the usual one:
 *
 *     cost = hours x intensity^2 x 100
 *
 * so one hour at threshold is 100. Squaring is what makes an hour hard
 * count for much more than an hour easy.
 *
 * It is an estimate and says which of the three it came from, because an
 * estimate that cannot say where it came from invites more trust than it
 * has earned. Heart rate reads low in water, so a swim's cost is modest.
 */
public enum Effort {

    public enum Source: String, Equatable { case heartRate, effort, planned, none }

    public struct Cost: Equatable {
        public let score: Double
        public let source: Source
        public init(score: Double, source: Source) { self.score = score; self.source = source }
    }

    /* Heart rate against the threshold heart rate, kept inside what a human does. */
    static func intensity(hr: Double, lthr: Double) -> Double? {
        guard hr > 30, lthr > 60 else { return nil }
        return min(1.15, max(0.40, hr / lthr))
    }

    /* The 1-to-10 he types. 7 is around threshold, which is where the curve puts it. */
    static func intensity(rpe: Double) -> Double? {
        guard rpe >= 1, rpe <= 10 else { return nil }
        return min(1.15, max(0.40, 0.45 + rpe * 0.065))
    }

    /* "Z2", "Z1-Z2", "Z4-Z5" as the plan writes them; the middle of a range. */
    static func intensity(zone: String) -> Double? {
        let table: [Int: Double] = [1: 0.60, 2: 0.70, 3: 0.82, 4: 0.92, 5: 1.05]
        let digits = zone.uppercased().split(separator: "Z").compactMap { part -> Int? in
            guard let first = part.first, first.isNumber, let n = Int(String(first)) else { return nil }
            return (1...5).contains(n) ? n : nil
        }
        guard !digits.isEmpty else { return nil }
        let values = digits.compactMap { table[$0] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public static func cost(minutes: Double, avgHR: Double, rpe: Double,
                            lthr: Double, plannedZone: String) -> Cost {
        guard minutes > 0 else { return Cost(score: 0, source: .none) }
        let hours = minutes / 60
        if let i = intensity(hr: avgHR, lthr: lthr) {
            return Cost(score: hours * i * i * 100, source: .heartRate)
        }
        if let i = intensity(rpe: rpe) {
            return Cost(score: hours * i * i * 100, source: .effort)
        }
        if let i = intensity(zone: plannedZone) {
            return Cost(score: hours * i * i * 100, source: .planned)
        }
        return Cost(score: 0, source: .none)
    }

    // MARK: fitness, fatigue, freshness

    public struct Form: Equatable, Identifiable {
        public var id: String { day }
        public let day: String
        /* Six weeks of training, slow to build and slow to lose. */
        public let fitness: Double
        /* The last week, quick to rise and quick to fall. */
        public let fatigue: Double
        /* What is left of the one after the other: under zero is carrying
           fatigue, over zero is fresh. */
        public var freshness: Double { fitness - fatigue }
        public init(day: String, fitness: Double, fatigue: Double) {
            self.day = day; self.fitness = fitness; self.fatigue = fatigue
        }
    }

    /*
     * The two running averages every training platform draws, over every day
     * from the first to the last — rest days included, because a rest day is
     * the point at which fatigue falls and fitness barely moves.
     */
    public static func form(dailyCost: [String: Double], from: String, to: String,
                            fitnessDays: Int = 42, fatigueDays: Int = 7) -> [Form] {
        guard let start = parseDayKey(from), let end = parseDayKey(to), start <= end else { return [] }
        var out: [Form] = []
        var fitness = 0.0, fatigue = 0.0
        var day = start
        while day <= end {
            let key = dayKey(day) ?? ""
            let cost = dailyCost[key] ?? 0
            fitness += (cost - fitness) / Double(max(1, fitnessDays))
            fatigue += (cost - fatigue) / Double(max(1, fatigueDays))
            out.append(Form(day: key, fitness: fitness, fatigue: fatigue))
            day = day.addingTimeInterval(86400)
        }
        return out
    }

    /* The word for where a freshness figure puts him, in his own language. */
    public static func standing(freshness: Double) -> String {
        switch freshness {
        case ..<(-25): return "Deep in it"
        case ..<(-10): return "Building"
        case ..<(5): return "Holding"
        case ..<(20): return "Fresh"
        default: return "Very fresh"
        }
    }
}
