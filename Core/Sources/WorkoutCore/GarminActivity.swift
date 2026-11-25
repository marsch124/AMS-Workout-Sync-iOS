import Foundation

/*
 * One finished session as Garmin holds it: which Garmin activity belongs to a
 * done session, its route, its pulse curve, its laps, and the time in each
 * pulse zone. Shown only — nothing here reaches the plan.
 *
 * Pure part: no network, no key. The app hands in what Garmin answered (read
 * as JSON, or the recorded file's bytes) and these functions forgive anything
 * missing: a field that is absent, a number that is a string, an answer one
 * level deeper than expected, or garbage gives "nothing", never a crash.
 *
 * The app never works out a pace itself (his rule): a lap carries only
 * Garmin's own average speed and average power, as Garmin wrote them.
 */

/* One entry of Garmin's list of activities: the summary numbers, nothing else. */
public struct GarminActivitySummary: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    /* Garmin's own type word: "running", "lap_swimming", "indoor_cycling" … */
    public var typeKey: String
    /* The day the activity started, in his own clock ("2026-11-25"). */
    public var day: String
    public var startGMT: Date?
    public var seconds: Double
    public var metres: Double?
    public var avgHr: Double?
    public var maxHr: Double?
    /* Seconds in pulse zones 1…5, as Garmin counted them. */
    public var zoneSeconds: [Double]

    public init(id: Int, name: String = "", typeKey: String, day: String, startGMT: Date? = nil, seconds: Double,
                metres: Double? = nil, avgHr: Double? = nil, maxHr: Double? = nil, zoneSeconds: [Double] = []) {
        self.id = id
        self.name = name
        self.typeKey = typeKey
        self.day = day
        self.startGMT = startGMT
        self.seconds = seconds
        self.metres = metres
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.zoneSeconds = zoneSeconds
    }
}

/* One lap, with Garmin's own words for it. */
public struct GarminLap: Codable, Equatable {
    public var number: Int
    public var metres: Double?
    public var seconds: Double?
    public var avgHr: Double?
    /* Garmin's own average speed for the lap, in metres a second. Never a pace worked out here. */
    public var speedMps: Double?
    public var powerW: Double?

    public init(number: Int, metres: Double? = nil, seconds: Double? = nil, avgHr: Double? = nil,
                speedMps: Double? = nil, powerW: Double? = nil) {
        self.number = number
        self.metres = metres
        self.seconds = seconds
        self.avgHr = avgHr
        self.speedMps = speedMps
        self.powerW = powerW
    }
}

public struct GarminCoordinate: Codable, Equatable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

/* What the recorded file held, thinned out for the screen. */
public struct GarminRecording: Codable, Equatable {
    public var track: [GarminCoordinate]
    /* Beats a minute, one value per slice of the session, oldest first. */
    public var pulse: [Int]
    public var laps: [GarminLap]
    public init(track: [GarminCoordinate] = [], pulse: [Int] = [], laps: [GarminLap] = []) {
        self.track = track
        self.pulse = pulse
        self.laps = laps
    }
    public var isEmpty: Bool { track.isEmpty && pulse.isEmpty && laps.isEmpty }
}

/* What the app keeps on the phone per activity: numbers only. */
public struct GarminActivityDetail: Codable, Equatable {
    public var activityId: Int
    public var typeKey: String
    public var avgHr: Double?
    public var maxHr: Double?
    public var recording: GarminRecording
    public init(activityId: Int, typeKey: String, avgHr: Double?, maxHr: Double?, recording: GarminRecording) {
        self.activityId = activityId
        self.typeKey = typeKey
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.recording = recording
    }

    /* Indoor and pool sessions have no map, whatever the file says. */
    public var hasMap: Bool { GarminActivity.isOutdoor(typeKey) && recording.track.count >= 2 }
}

public enum GarminActivity {
    public static let maxTrack = 220
    public static let maxPulse = 150

    // MARK: forgiving reading

    static func number(_ any: Any?) -> Double? { GarminMorning.number(any) }

    /* The "activities" answer: a bare list, or one wrapped a level down. */
    public static func summaries(_ json: Any?) -> [GarminActivitySummary] {
        GarminMorning.list(json, inside: ["activities", "activityList"]).compactMap { a in
            guard let idNumber = number(a["activityId"]) else { return nil }
            let type: String = {
                if let t = a["activityType"] as? [String: Any], let k = t["typeKey"] as? String { return k }
                return (a["activityType"] as? String) ?? ""
            }()
            let start = GarminMorning.parseGMT(a["startTimeGMT"] as? String)
            // The day he lived it: the local start stamp ("2026-11-25 07:12:00"), else the GMT one.
            let local = (a["startTimeLocal"] as? String).map { String($0.prefix(10)) }
            let day = local.flatMap { $0.count == 10 ? $0 : nil } ?? start.map { GarminMorning.dayKey($0) } ?? ""
            guard !day.isEmpty else { return nil }
            let zones = (1...5).map { max(0, number(a["hrTimeInZone_\($0)"]) ?? 0) }
            return GarminActivitySummary(id: Int(idNumber), name: (a["activityName"] as? String) ?? "", typeKey: type,
                                         day: day, startGMT: start, seconds: max(0, number(a["duration"]) ?? 0),
                                         metres: number(a["distance"]).flatMap { $0 > 0 ? $0 : nil },
                                         avgHr: number(a["averageHR"]).flatMap { $0 > 0 ? $0 : nil },
                                         maxHr: number(a["maxHR"]).flatMap { $0 > 0 ? $0 : nil },
                                         zoneSeconds: zones)
        }
    }

    /* Outdoor sessions can have a map; pool, indoor, treadmill and virtual ones never. */
    public static func isOutdoor(_ typeKey: String) -> Bool {
        let t = typeKey.lowercased()
        for word in ["indoor", "pool", "treadmill", "virtual", "lap_swimming", "strength", "yoga", "cardio", "trainer"] where t.contains(word) { return false }
        return true
    }

    /* The sport family a Garmin type word belongs to, in the app's own discipline words. Nil when it fits none. */
    public static func family(ofGarmin typeKey: String) -> String? {
        let t = typeKey.lowercased()
        if t.contains("swim") { return "swim" }
        if t.contains("cycl") || t.contains("bik") || t.contains("ride") { return "bike" }
        if t.contains("run") { return "run" }
        if t.contains("strength") { return "strength" }
        return nil
    }

    // MARK: which activity is this session

    /*
     * The Garmin activity of one done session: same day, same sport family,
     * then the nearest start time (when it is known) or the closest length.
     * "Brick" and "other" sessions match any family. A session with no known
     * length and several candidates is not guessed at. A candidate more than
     * 40 percent away from the logged length is not the same session.
     */
    public static func match(day: String, sport: String, seconds: Double?, start: Date? = nil,
                             among list: [GarminActivitySummary]) -> GarminActivitySummary? {
        let anySport = sport == "brick" || sport == "other"
        let candidates = list.filter { $0.day == day && (anySport || family(ofGarmin: $0.typeKey) == sport) }
        if candidates.isEmpty { return nil }
        if let start, candidates.contains(where: { $0.startGMT != nil }) {
            let dated = candidates.compactMap { c in c.startGMT.map { (c, abs($0.timeIntervalSince(start))) } }
            if let best = dated.min(by: { $0.1 < $1.1 }), best.1 <= 3 * 3600 { return best.0 }
        }
        guard let seconds, seconds > 0 else { return candidates.count == 1 ? candidates[0] : nil }
        guard let best = candidates.min(by: { abs($0.seconds - seconds) < abs($1.seconds - seconds) }) else { return nil }
        return abs(best.seconds - seconds) <= 0.4 * seconds ? best : nil
    }

    // MARK: laps from the detail answer

    /*
     * The laps in /activity-service/activity/{id}: "splitSummaries" (each a
     * SplitSummaryDTO) or, in the other shape Garmin's own site uses, "lapDTOs".
     * Where the splits say what kind they are, only the laps are kept.
     */
    public static func laps(detail json: Any?) -> [GarminLap] {
        guard let root = json as? [String: Any] else { return [] }
        var items = GarminMorning.list(root["splitSummaries"] as Any, inside: [])
        if items.isEmpty { items = GarminMorning.list(root["lapDTOs"] as Any, inside: []) }
        let lapOnly = items.filter { (($0["splitType"] as? String) ?? "").uppercased().contains("LAP") }
        if !lapOnly.isEmpty { items = lapOnly }
        var out: [GarminLap] = []
        for item in items {
            let metres = number(item["distance"]).flatMap { $0 > 0 ? $0 : nil }
            let seconds = (number(item["duration"]) ?? number(item["movingDuration"])).flatMap { $0 > 0 ? $0 : nil }
            if metres == nil && seconds == nil { continue }
            out.append(GarminLap(number: out.count + 1, metres: metres, seconds: seconds,
                                 avgHr: number(item["averageHR"]).flatMap { $0 > 0 ? $0 : nil },
                                 speedMps: number(item["averageSpeed"]).flatMap { $0 > 0 ? $0 : nil },
                                 powerW: number(item["averagePower"]).flatMap { $0 > 0 ? $0 : nil }))
        }
        return out
    }

    /* Thin a list to at most n values by taking slice averages (pulse) or every k-th (track). */
    static func thinned<T>(_ values: [T], to n: Int) -> [T] {
        guard values.count > n, n > 1 else { return values }
        let step = Double(values.count - 1) / Double(n - 1)
        return (0..<n).map { values[min(values.count - 1, Int((Double($0) * step).rounded()))] }
    }

    static func averaged(_ values: [Int], to n: Int) -> [Int] {
        guard values.count > n, n > 0 else { return values }
        let size = Double(values.count) / Double(n)
        return (0..<n).map { i in
            let lo = Int(Double(i) * size), hi = max(lo + 1, min(values.count, Int(Double(i + 1) * size)))
            let slice = values[lo..<hi]
            return Int((Double(slice.reduce(0, +)) / Double(slice.count)).rounded())
        }
    }
}

// MARK: - the recorded file (FIT)

/*
 * Garmin's download is a zip holding one .FIT file (or, tolerated, the bare
 * file). Only three kinds of message are read: records (position and pulse),
 * laps, and nothing else. Anything odd stops the read and keeps what was
 * already found.
 */
public enum GarminFit {

    public static func recording(fromDownload data: Data) -> GarminRecording {
        var bytes = data
        if data.count > 4, data[data.startIndex] == 0x50, data[data.startIndex + 1] == 0x4B,
           let zip = try? ZipArchive(data: data),
           let name = zip.entries.map({ $0.name }).first(where: { $0.lowercased().hasSuffix(".fit") }),
           let inner = try? zip.bytes(name) {
            bytes = inner
        }
        return parse(bytes)
    }

    private struct Field { var num: Int; var size: Int }
    private struct Definition { var big: Bool; var global: Int; var fields: [Field]; var devSize: Int }

    public static func parse(_ data: Data) -> GarminRecording {
        let b = [UInt8](data)
        guard b.count > 14, b[8] == 0x2E, b[9] == 0x46, b[10] == 0x49, b[11] == 0x54 else { return GarminRecording() }   // ".FIT"
        let headerSize = Int(b[0])
        let dataSize = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
        let end = min(b.count, headerSize + dataSize)
        var pos = headerSize
        var defs: [Int: Definition] = [:]
        var coords: [GarminCoordinate] = []
        var pulse: [Int] = []
        var laps: [GarminLap] = []

        func uint(_ at: Int, _ size: Int, big: Bool) -> UInt64? {
            guard size > 0, size <= 8, at + size <= b.count else { return nil }
            var v: UInt64 = 0
            for i in 0..<size {
                let byte = UInt64(b[big ? at + i : at + size - 1 - i])
                v = v << 8 | byte
            }
            return v
        }
        func invalid(_ v: UInt64, _ size: Int) -> Bool { v == (size >= 8 ? UInt64.max : (UInt64(1) << UInt64(size * 8)) - 1) }

        /* Moves past one data message's bytes; nil when the file ends first. */
        func consume(_ def: Definition, _ pos: inout Int) -> Int? {
            let size = def.fields.reduce(0) { $0 + $1.size } + def.devSize
            guard pos + size <= end else { return nil }
            let start = pos
            pos += size
            return start
        }

        while pos < end {
            let header = b[pos]; pos += 1
            if header & 0x80 != 0 {
                // A compressed-timestamp data message: its definition is the local type in bits 5-6.
                guard let def = defs[Int(header >> 5) & 0x3], let used = consume(def, &pos) else { break }
                _ = used
                continue
            }
            let local = Int(header & 0x0F)
            if header & 0x40 != 0 {
                guard pos + 5 <= end else { break }
                let big = b[pos + 1] == 1
                let global = Int(uint(pos + 2, 2, big: big) ?? 0)
                let count = Int(b[pos + 4])
                pos += 5
                guard pos + count * 3 <= end else { break }
                var fields: [Field] = []
                for i in 0..<count { fields.append(Field(num: Int(b[pos + i * 3]), size: Int(b[pos + i * 3 + 1]))) }
                pos += count * 3
                var dev = 0
                if header & 0x20 != 0 {
                    guard pos < end else { break }
                    let n = Int(b[pos]); pos += 1
                    guard pos + n * 3 <= end else { break }
                    for i in 0..<n { dev += Int(b[pos + i * 3 + 1]) }
                    pos += n * 3
                }
                defs[local] = Definition(big: big, global: global, fields: fields, devSize: dev)
            } else {
                guard let def = defs[local], let start = consume(def, &pos) else { break }
                var at = start
                var lat: Int64?, lon: Int64?, hr: Int?
                var lapSeconds: Double?, lapElapsed: Double?, lapMetres: Double?, lapHr: Int?, lapSpeed: Double?, lapPower: Double?
                for f in def.fields {
                    defer { at += f.size }
                    guard let v = uint(at, f.size, big: def.big), !invalid(v, f.size) else { continue }
                    if def.global == 20 {
                        switch f.num {
                        case 0 where f.size == 4 && v != 0x7FFFFFFF: lat = Int64(Int32(bitPattern: UInt32(v)))
                        case 1 where f.size == 4 && v != 0x7FFFFFFF: lon = Int64(Int32(bitPattern: UInt32(v)))
                        case 3 where f.size == 1: hr = Int(v)
                        default: break
                        }
                    } else if def.global == 19 {
                        switch f.num {
                        case 7: lapElapsed = Double(v) / 1000
                        case 8: lapSeconds = Double(v) / 1000
                        case 9: lapMetres = Double(v) / 100
                        case 13 where lapSpeed == nil: lapSpeed = Double(v) / 1000
                        case 110: lapSpeed = Double(v) / 1000
                        case 15: lapHr = Int(v)
                        case 19: lapPower = Double(v)
                        default: break
                        }
                    }
                }
                if def.global == 20 {
                    if let lat, let lon {
                        let k = 180.0 / 2147483648.0
                        coords.append(GarminCoordinate(lat: Double(lat) * k, lon: Double(lon) * k))
                    }
                    if let hr, hr > 30, hr < 250 { pulse.append(hr) }
                } else if def.global == 19 {
                    let secs = lapSeconds ?? lapElapsed
                    if secs != nil || lapMetres != nil {
                        laps.append(GarminLap(number: laps.count + 1, metres: lapMetres.flatMap { $0 > 0 ? $0 : nil },
                                              seconds: secs.flatMap { $0 > 0 ? $0 : nil }, avgHr: lapHr.flatMap { $0 > 30 ? Double($0) : nil },
                                              speedMps: lapSpeed.flatMap { $0 > 0 ? $0 : nil }, powerW: lapPower.flatMap { $0 > 0 ? $0 : nil }))
                    }
                }
            }
        }

        return GarminRecording(track: GarminActivity.thinned(coords, to: GarminActivity.maxTrack),
                               pulse: GarminActivity.averaged(pulse, to: GarminActivity.maxPulse), laps: laps)
    }
}

// MARK: - the same session last time

public enum LastTime {
    /* What the rule needs to know about one session. */
    public struct Entry: Equatable {
        public var key: String, dayKey: String, sport: String, title: String, row: Int
        public var done: Bool
        public init(key: String, dayKey: String, sport: String, title: String, row: Int = 0, done: Bool = true) {
            self.key = key; self.dayKey = dayKey; self.sport = sport; self.title = title; self.row = row; self.done = done
        }
    }

    static func normalised(_ title: String) -> String {
        title.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }

    /* "The same kind": the same sport and the same title, ignoring case, spacing and punctuation. */
    public static func sameKind(_ a: Entry, _ b: Entry) -> Bool {
        a.sport == b.sport && !a.sport.isEmpty && normalised(a.title) == normalised(b.title)
    }

    /* The most recent EARLIER done session of the same kind (an earlier day; or earlier in the sheet on the same day). */
    public static func previous(of now: Entry, among all: [Entry]) -> Entry? {
        all.filter { $0.key != now.key && $0.done && sameKind($0, now) && ($0.dayKey < now.dayKey || ($0.dayKey == now.dayKey && $0.row < now.row)) }
            .max { ($0.dayKey, $0.row) < ($1.dayKey, $1.row) }
    }

    public struct Figures: Equatable {
        public var minutes: Double, km: Double, hr: Double, rpe: Double
        public init(minutes: Double, km: Double, hr: Double, rpe: Double) { self.minutes = minutes; self.km = km; self.hr = hr; self.rpe = rpe }
    }

    public struct Row: Equatable {
        public let name: String
        public let now: String
        public let last: String
    }

    /* One row per figure either session has (a zero means "not recorded"); no row when neither has it. */
    public static func rows(now: Figures, last: Figures) -> [Row] {
        func km(_ v: Double) -> String { v > 0 ? jsNumberString((v * 10).rounded() / 10) + " km" : "—" }
        func time(_ v: Double) -> String { v > 0 ? formatDuration(v * 60) : "—" }
        func beats(_ v: Double) -> String { v > 0 ? "\(Int(v.rounded()))" : "—" }
        func hard(_ v: Double) -> String { v > 0 ? "\(Int(v.rounded())) of 10" : "—" }
        let all: [(String, Double, Double, (Double) -> String)] = [
            ("Length", now.minutes, last.minutes, time), ("Distance", now.km, last.km, km),
            ("Average pulse", now.hr, last.hr, beats), ("How hard", now.rpe, last.rpe, hard),
        ]
        return all.filter { $0.1 > 0 || $0.2 > 0 }.map { Row(name: $0.0, now: $0.3($0.1), last: $0.3($0.2)) }
    }
}

// MARK: - time in zones, this week and last

public enum GarminZoneWeeks {
    public struct Result: Codable, Equatable {
        public var thisWeek: [Double]   // seconds in Z1…Z5
        public var lastWeek: [Double]
        public init(thisWeek: [Double], lastWeek: [Double]) { self.thisWeek = thisWeek; self.lastWeek = lastWeek }
        public var any: Bool { thisWeek.contains { $0 > 0 } || lastWeek.contains { $0 > 0 } }
    }

    /* Zones summed over the activities of the week that starts on weekStart (a Monday) and the one before. */
    public static func build(_ list: [GarminActivitySummary], weekStart: String) -> Result {
        let lastStart = GarminMorning.addDays(weekStart, -7)
        let nextStart = GarminMorning.addDays(weekStart, 7)
        var this = [Double](repeating: 0, count: 5), last = this
        for a in list where a.zoneSeconds.count == 5 {
            if a.day >= weekStart && a.day < nextStart { for i in 0..<5 { this[i] += a.zoneSeconds[i] } }
            else if a.day >= lastStart && a.day < weekStart { for i in 0..<5 { last[i] += a.zoneSeconds[i] } }
        }
        return Result(thisWeek: this, lastWeek: last)
    }

    /*
     * The plan's own words for the week: "The plan asks for mostly Z1–Z2 this
     * week". Each planned session spreads its length over the zones its
     * intensity names; the zones that together hold at least 60 percent of
     * the planned time, taken from the heaviest down, give the range. Nothing
     * when no session names a zone.
     */
    public static func planLine(sessions: [(intensity: String, seconds: Double)]) -> String? {
        var weight = [Int: Double]()
        for s in sessions {
            let zones = Zones.zones(in: s.intensity).filter { (1...5).contains($0) }
            guard !zones.isEmpty else { continue }
            let each = max(s.seconds, 60) / Double(zones.count)
            for z in zones { weight[z, default: 0] += each }
        }
        let total = weight.values.reduce(0, +)
        guard total > 0 else { return nil }
        var chosen: [Int] = [], held = 0.0
        for (z, w) in weight.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
            chosen.append(z); held += w
            if held / total >= 0.6 { break }
        }
        guard let lo = chosen.min(), let hi = chosen.max() else { return nil }
        let range = lo == hi ? "Z\(lo)" : "Z\(lo)–Z\(hi)"
        return "The plan asks for mostly \(range) this week"
    }
}
