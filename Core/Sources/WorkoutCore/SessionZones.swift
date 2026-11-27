import Foundation

/*
 * Zones that keep up (round 30, his pick 3): "New zones offered between tests
 * when your sessions show you got stronger. Uses your run power too."
 *
 * From the last 6 weeks of Garmin sessions, each run, ride and pool swim gives
 * at most one estimate, worked out from its laps (Garmin's own lap averages,
 * from the recorded file or the split list):
 *   - threshold pulse (run and bike): the best steady stretch of whole laps
 *     lasting 20 to 30 minutes, about 95 % of its average pulse;
 *   - run threshold power (from the watch or foot pod's power): the best such
 *     stretch by power, about 95 % of its average power — counted only when the
 *     stretch was a threshold effort (its pulse at least 96 % of the threshold
 *     pulse in use), so an easy run never sets power zones;
 *   - swim threshold pace (pool only): the fastest lap of 400 m or more swum
 *     without a stop, plus 3 seconds per 100 m.
 * A new value is offered only when it is clearly above the one in use (pulse
 * 3 beats or more, power or pace 2 % or more) and at least two sessions show
 * it; the offer is the second best of them, so two sessions always support it.
 * Zones are never lowered: a lower estimate shows nothing.
 *
 * Pure: the app hands in the laps and the numbers in use; nothing here reads
 * the network, a clock or a file.
 */
public enum SessionZones {

    // MARK: the numbers (judgement, may be tuned)

    public static let windowShortest = 20.0 * 60
    public static let windowLongest = 30.0 * 60
    public static let pulseFactor = 0.95
    public static let powerFactor = 0.95
    /* "Steady": within the stretch, the laps' average pulse differs by at most this … */
    public static let pulseSpread = 15.0
    /* … and their power by at most this factor. */
    public static let powerSpread = 1.25
    /* A power stretch counts only at threshold effort: its pulse at least this share of the threshold pulse in use. */
    public static let powerEffort = 0.96
    public static let swimShortest = 400.0
    public static let swimAdd = 3.0
    public static let pulseMargin = 3.0
    public static let powerMargin = 0.02
    public static let paceMargin = 0.02
    public static let lookBackDays = 42
    public static let sessionsNeeded = 2
    /*
     * Round 30 safety: a session more than this far beyond the number in use is a glitch (a pool
     * length set wrong on the watch, a strap that slipped, a power meter gone astray), not fitness:
     * it is left out. Run power seen for the first time must lie within `firstPowerW`.
     */
    public static let glitch = 0.10
    public static let firstPowerW = 80.0...600.0
    /* The entry it records in the test list, and the mark in its notes. */
    public static let entryName = "Your sessions"
    public static let mark = "From your sessions"

    // MARK: one session

    public struct Sample: Codable, Equatable, Sendable {
        public var activityId: Int
        public var day: String
        /* "run", "bike" or "swim". */
        public var sport: String
        /* This session's estimate of the threshold pulse. */
        public var pulse: Double?
        /* Run only: this session's estimate of the run threshold power, and the average pulse of the stretch it came from. */
        public var power: Double?
        public var powerPulse: Double?
        /* Pool only: this session's estimate of the threshold pace, seconds per 100 m. */
        public var swimPace: Double?

        public init(activityId: Int, day: String, sport: String, pulse: Double? = nil, power: Double? = nil,
                    powerPulse: Double? = nil, swimPace: Double? = nil) {
            self.activityId = activityId; self.day = day; self.sport = sport; self.pulse = pulse; self.power = power
            self.powerPulse = powerPulse; self.swimPace = swimPace
        }

        public var isEmpty: Bool { pulse == nil && power == nil && swimPace == nil }
    }

    /* The sport this reads a Garmin activity as, or nil (swims only in a pool). */
    public static func sport(ofGarmin typeKey: String) -> String? {
        switch GarminActivity.family(ofGarmin: typeKey) {
        case "run": return "run"
        case "bike": return "bike"
        case "swim":
            let t = typeKey.lowercased()
            return t.contains("lap_swimming") || t.contains("pool") ? "swim" : nil
        default: return nil
        }
    }

    /*
     * The best steady stretch of whole laps lasting 20 to 30 minutes, by `value`
     * (time-weighted), with its average pulse. Every lap of it must have the value
     * (and a pulse) and a length in seconds.
     */
    static func bestStretch(_ laps: [GarminLap], value: (GarminLap) -> Double?, spreadOK: ([Double]) -> Bool) -> (value: Double, pulse: Double?)? {
        var best: (value: Double, pulse: Double?)?
        for i in laps.indices {
            var seconds = 0.0, sum = 0.0, pulseSum = 0.0, pulseSeconds = 0.0
            var values: [Double] = []
            var j = i
            while j < laps.count, seconds < windowShortest {
                guard let s = laps[j].seconds, s > 0, let v = value(laps[j]) else { break }
                seconds += s; sum += v * s; values.append(v)
                if let hr = laps[j].avgHr { pulseSum += hr * s; pulseSeconds += s }
                j += 1
            }
            guard seconds >= windowShortest, seconds <= windowLongest, spreadOK(values) else { continue }
            let avg = sum / seconds
            if best == nil || avg > best!.value {
                best = (avg, pulseSeconds >= seconds - 1e-6 ? pulseSum / pulseSeconds : nil)
            }
        }
        return best
    }

    /*
     * One session's estimates from its laps. `seconds` is the activity's own
     * length: laps that add up to much more than it are summaries, not laps,
     * and are not read.
     */
    public static func sample(activityId: Int, day: String, typeKey: String, seconds: Double, laps: [GarminLap]) -> Sample? {
        guard let sport = sport(ofGarmin: typeKey), !laps.isEmpty else { return nil }
        let total = laps.compactMap(\.seconds).reduce(0, +)
        if seconds > 0, total > seconds * 1.1 { return nil }
        var s = Sample(activityId: activityId, day: day, sport: sport)
        switch sport {
        case "run", "bike":
            if let p = bestStretch(laps, value: { $0.avgHr }, spreadOK: { ($0.max() ?? 0) - ($0.min() ?? 0) <= pulseSpread }) {
                s.pulse = p.value * pulseFactor
            }
            if sport == "run",
               let p = bestStretch(laps, value: { $0.avgHr == nil ? nil : $0.powerW },
                                   spreadOK: { v in (v.min() ?? 0) > 0 && (v.max() ?? 0) <= (v.min() ?? 0) * powerSpread }) {
                s.power = p.value * powerFactor
                s.powerPulse = p.pulse
            }
        case "swim":
            let paces = laps.compactMap { l -> Double? in
                guard let m = l.metres, m >= swimShortest, let t = l.seconds, t > 0 else { return nil }
                return t / m * 100
            }
            if let fastest = paces.min() { s.swimPace = fastest + swimAdd }
        default: break
        }
        return s.isEmpty ? nil : s
    }

    // MARK: the offer

    public enum Measure: String, Codable, Equatable, Sendable, CaseIterable {
        case pulse, runPower, swim

        public var title: String {
            switch self {
            case .pulse: return "Threshold pulse"
            case .runPower: return "Run power"
            case .swim: return "Swim pace"
            }
        }
        public var unit: String {
            switch self {
            case .pulse: return "bpm"
            case .runPower: return "W"
            case .swim: return "per 100 m"
            }
        }
        public func text(_ v: Double) -> String { self == .swim ? TestEntry.swimText(v) : jsNumberString(v.rounded()) }
    }

    /* The numbers the zones follow now. */
    public struct InUse: Codable, Equatable, Sendable {
        public var lthr: Double?
        public var css: Double?
        public var runPower: Double?
        public init(lthr: Double? = nil, css: Double? = nil, runPower: Double? = nil) { self.lthr = lthr; self.css = css; self.runPower = runPower }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String { measure.rawValue }
        public let measure: Measure
        /* nil: none in use yet (run power the first time). */
        public let old: Double?
        public let new: Double
        /* The sessions that showed it, newest first. */
        public let sessions: [Sample]

        /* "160 → 164" or "new · 265". */
        public var figure: String { (old.map(measure.text) ?? "none yet") + " \u{2192} " + measure.text(new) }
    }

    public struct Proposal: Equatable, Sendable {
        public let rows: [Row]
        public func row(_ m: Measure) -> Row? { rows.first { $0.measure == m } }
    }

    /* What the sessions of the last 6 weeks point to, or nil when nothing is clearly above what is in use. */
    public static func proposal(_ samples: [Sample], inUse: InUse, today: String) -> Proposal? {
        let from = PlanView.addDays(today, -lookBackDays)
        let recent = samples.filter { $0.day >= from && $0.day <= today }
        var rows: [Row] = []
        func row(_ m: Measure, _ old: Double?, _ hits: [(Sample, Double)], higherIsMore: Bool) {
            guard hits.count >= sessionsNeeded else { return }
            let sorted = hits.sorted { higherIsMore ? $0.1 > $1.1 : $0.1 < $1.1 }
            let value = sorted[sessionsNeeded - 1].1.rounded()
            if let old, higherIsMore ? value <= old : value >= old { return }
            rows.append(Row(measure: m, old: old, new: value, sessions: sorted.map(\.0).sorted { $0.day > $1.day }))
        }
        if let lthr = inUse.lthr {
            let hits = recent.compactMap { s -> (Sample, Double)? in
                guard s.sport != "swim", let p = s.pulse, p >= lthr + pulseMargin, p <= lthr * (1 + glitch) else { return nil }
                return (s, p)
            }
            row(.pulse, lthr, hits, higherIsMore: true)
            let powerHits = recent.compactMap { s -> (Sample, Double)? in
                guard s.sport == "run", let w = s.power, let hr = s.powerPulse, hr >= lthr * powerEffort else { return nil }
                if let old = inUse.runPower, w < old * (1 + powerMargin) || w > old * (1 + glitch) { return nil }
                if inUse.runPower == nil, !firstPowerW.contains(w) { return nil }
                return (s, w)
            }
            row(.runPower, inUse.runPower, powerHits, higherIsMore: true)
        }
        if let css = inUse.css {
            let hits = recent.compactMap { s -> (Sample, Double)? in
                guard s.sport == "swim", let p = s.swimPace, p <= css * (1 - paceMargin), p >= css * (1 - glitch) else { return nil }
                return (s, p)
            }
            row(.swim, css, hits, higherIsMore: false)
        }
        return rows.isEmpty ? nil : Proposal(rows: rows)
    }

    // MARK: "Keep mine"

    /* What he said "Keep mine" to: that offer stays away until a session shows clearly more, or 6 weeks pass. */
    public struct Kept: Codable, Equatable, Sendable {
        public var day: String
        public var lthr: Double?
        public var css: Double?
        public var runPower: Double?

        public init(day: String, lthr: Double? = nil, css: Double? = nil, runPower: Double? = nil) {
            self.day = day; self.lthr = lthr; self.css = css; self.runPower = runPower
        }

        public init(_ p: Proposal, day: String) {
            self.init(day: day, lthr: p.row(.pulse)?.new, css: p.row(.swim)?.new, runPower: p.row(.runPower)?.new)
        }
    }

    /* The offer as it may be shown after a "Keep mine": only the rows clearly beyond what he kept. */
    public static func shown(_ p: Proposal?, kept: Kept?, today: String) -> Proposal? {
        guard let p else { return nil }
        guard let kept, kept.day >= PlanView.addDays(today, -lookBackDays) else { return p }
        let rows = p.rows.filter { r in
            switch r.measure {
            case .pulse: return kept.lthr.map { r.new >= $0 + pulseMargin } ?? true
            case .runPower: return kept.runPower.map { r.new >= $0 * (1 + powerMargin) } ?? true
            case .swim: return kept.css.map { r.new <= $0 * (1 - paceMargin) } ?? true
            }
        }
        return rows.isEmpty ? nil : Proposal(rows: rows)
    }

    // MARK: "Use the new zones"

    /* A name no test has had: "Your sessions", then "Your sessions 2" … (`used` holds names taken back by an Undo). */
    public static func freshName(_ tests: [TestResult], used: [String] = []) -> String {
        let taken = Set(tests.map(\.name) + used)
        if !taken.contains(entryName) { return entryName }
        var n = 2
        while taken.contains("\(entryName) \(n)") { n += 1 }
        return "\(entryName) \(n)"
    }

    /*
     * The test entry that carries the new pulse and swim pace, marked "From your
     * sessions" — nil when the offer holds only run power (which is not a test
     * number; it lives beside the zones).
     */
    public static func entry(_ p: Proposal, tests: [TestResult], today: String, used: [String] = []) -> TestResult? {
        let pulse = p.row(.pulse)?.new, css = p.row(.swim)?.new
        guard pulse != nil || css != nil else { return nil }
        var notes = mark
        if let w = p.row(.runPower)?.new { notes += " \u{00B7} run power \(jsNumberString(w)) W" }
        return TestResult(name: freshName(tests, used: used), dates: TestEntry.datesText(first: today, last: today) ?? "",
                          lthr: pulse, css: css, notes: notes)
    }

    /*
     * The list with the entry put right after the last test that has numbers,
     * so the plan's own test blocks still to come are filled in as before and
     * the zones follow the entry until the next test.
     */
    public static func inserting(_ entry: TestResult, into tests: [TestResult]) -> [TestResult] {
        var out = tests.filter { $0.name != entry.name }
        let at = (out.lastIndex(where: { $0.hasNumbers }) ?? -1) + 1
        out.insert(entry, at: at)
        return out
    }

    /* The list without the entries taken back (by name, and only entries marked "From your sessions"). */
    public static func removing(_ names: [String], from tests: [TestResult]) -> [TestResult] {
        tests.filter { !(names.contains($0.name) && $0.notes.hasPrefix(mark)) }
    }

    /* "Tue 3 Nov run · Sat 14 Nov ride" — at most three. */
    public static func sourcesLine(_ sessions: [Sample], dayText: (String) -> String) -> String {
        let word = ["run": "run", "bike": "ride", "swim": "swim"]
        let shown = sessions.prefix(3).map { dayText($0.day) + " " + (word[$0.sport] ?? $0.sport) }
        let more = sessions.count > 3 ? " and \(sessions.count - 3) more" : ""
        return "From " + shown.joined(separator: " \u{00B7} ") + more
    }
}

/* Run power zones from the run threshold power: Coggan-style bands as adapted for running power (Jim Vance's percentages). */
public enum RunPowerZones {
    public struct Band: Equatable, Sendable {
        public let zone: Int
        public let label: String
        public let low: Double?
        public let high: Double?
    }

    public static let bands: [Band] = [
        Band(zone: 1, label: "Z1 \u{2014} Recovery", low: nil, high: 0.80),
        Band(zone: 2, label: "Z2 \u{2014} Endurance", low: 0.81, high: 0.88),
        Band(zone: 3, label: "Z3 \u{2014} Tempo", low: 0.89, high: 0.95),
        Band(zone: 4, label: "Z4 \u{2014} Threshold", low: 0.96, high: 1.05),
        Band(zone: 5, label: "Z5 \u{2014} Above threshold", low: 1.06, high: nil),
    ]

    static func watts(_ x: Double) -> String { jsNumberString(x.rounded(.toNearestOrAwayFromZero)) }

    /* The five rows, "Z2 — Endurance" · "211–229 W". */
    public static func rows(_ threshold: Double) -> [ZoneRow] {
        bands.map { b in ZoneRow(label: b.label, value: range(b.low, b.high, threshold)) }
    }

    static func range(_ low: Double?, _ high: Double?, _ t: Double) -> String {
        switch (low, high) {
        case let (l?, h?): return watts(t * l) + "\u{2013}" + watts(t * h) + " W"
        case let (nil, h?): return "up to " + watts(t * h) + " W"
        case let (l?, nil): return "from " + watts(t * l) + " W"
        default: return ""
        }
    }

    /* The power the intensity names ("Z2" → "211–229 W", "Z1–Z2" → "up to 229 W"), or nil when it names no zone 1–5. */
    public static func target(intensity: String, threshold: Double) -> String? {
        let zs = Zones.zones(in: intensity).filter { (1...5).contains($0) }
        guard let lo = zs.min(), let hi = zs.max(), threshold > 0 else { return nil }
        return range(bands[lo - 1].low, bands[hi - 1].high, threshold)
    }
}

/* The run threshold power in use, on the shelf ("tuning/run-power"): it follows him to every device. */
public struct RunPowerSetting: Codable, Equatable, Sendable {
    public var watts: Double
    public var day: String

    public init(watts: Double, day: String) { self.watts = watts; self.day = day }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        watts = try c.decode(Double.self, forKey: .watts)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
    }

    enum CodingKeys: String, CodingKey { case watts, day }
}

/* "Use the new zones", kept for its one Undo ("tuning/zones-taken"). */
public struct ZonesTaken: Codable, Equatable, Sendable {
    public var day: String
    /* The test entry it recorded (nil when the offer held only run power). */
    public var entryName: String?
    /* The run power in use before (nil: none). */
    public var runPowerBefore: RunPowerSetting?
    public var tookRunPower: Bool
    /* The rows as he saw them, for the line under "Changed". */
    public var lines: [String]

    public init(day: String, entryName: String?, runPowerBefore: RunPowerSetting?, tookRunPower: Bool, lines: [String]) {
        self.day = day; self.entryName = entryName; self.runPowerBefore = runPowerBefore; self.tookRunPower = tookRunPower
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        entryName = try c.decodeIfPresent(String.self, forKey: .entryName)
        runPowerBefore = try c.decodeIfPresent(RunPowerSetting.self, forKey: .runPowerBefore)
        tookRunPower = try c.decodeIfPresent(Bool.self, forKey: .tookRunPower) ?? false
        lines = try c.decodeIfPresent([String].self, forKey: .lines) ?? []
    }

    enum CodingKeys: String, CodingKey { case day, entryName, runPowerBefore, tookRunPower, lines }
}
