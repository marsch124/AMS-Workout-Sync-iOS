import Foundation

/*
 * Apple Health lives on the iPhone. The Mac has no Health at all and the iPad
 * only what Health's own iCloud brought, so the iPhone writes what it read
 * into `health-from-iphone.json`, and the iPad and Mac show it — always with
 * where it came from and when ("from iPhone, as of 07:12").
 *
 * Written by the iPhone only and never merged: the newest `writtenAt` wins.
 * Read forgivingly — every field may be missing, and fields a newer app
 * added are passed over — because a Mac with an older build must still show
 * what it can.
 */
public struct HealthShare: Codable, Equatable {
    public static let format = 1

    public var format: Int = HealthShare.format
    /* When the iPhone last asked Health. */
    public var writtenAt: Date
    /* Day key → that morning's numbers; the last 14 days. */
    public var mornings: [String: MorningShare]
    /* Health workouts of the last 14 days, for the log form. */
    public var workouts: [WorkoutShare]
    /* The workouts the Load card draws (eight weeks). */
    public var found: [Load.Found]

    public init(writtenAt: Date, mornings: [String: MorningShare] = [:], workouts: [WorkoutShare] = [], found: [Load.Found] = []) {
        self.writtenAt = writtenAt; self.mornings = mornings; self.workouts = workouts; self.found = found
    }

    enum CodingKeys: String, CodingKey { case format, writtenAt, mornings, workouts, found }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(Int.self, forKey: .format)) ?? 1
        writtenAt = (try? c.decode(Date.self, forKey: .writtenAt)) ?? Date(timeIntervalSince1970: 0)
        mornings = (try? c.decode([String: MorningShare].self, forKey: .mornings)) ?? [:]
        // One workout that cannot be read loses only itself.
        workouts = HealthShare.tolerant(c, .workouts)
        found = HealthShare.tolerant(c, .found)
    }

    private struct Maybe<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    private static func tolerant<T: Decodable>(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [T] {
        ((try? c.decode([Maybe<T>].self, forKey: key)) ?? []).compactMap(\.value)
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decoded(_ data: Data) throws -> HealthShare {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return try d.decode(HealthShare.self, from: data)
    }

    /* The file and its conflict copies: the one the iPhone wrote last. */
    public static func newest(_ shares: [HealthShare]) -> HealthShare? {
        shares.max { $0.writtenAt != $1.writtenAt ? $0.writtenAt < $1.writtenAt
                                                  : (try? $0.encoded().count) ?? 0 < (try? $1.encoded().count) ?? 0 }
    }

    /* Older than 18 hours: shown grey, and no longer "as of". */
    public func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(writtenAt) > 18 * 3600 }

    /*
     * "from iPhone, as of 07:12" — or, once it is older than 18 hours,
     * "from iPhone, yesterday 07:12" (or the day, further back).
     */
    public func asOfWords(now: Date = Date(), calendar: Calendar = .current) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_GB")
        clock.timeZone = calendar.timeZone
        clock.dateFormat = "HH:mm"
        let time = clock.string(from: writtenAt)
        guard isStale(now: now) else { return "from iPhone, as of " + time }
        if calendar.isDate(writtenAt, inSameDayAs: now) { return "from iPhone, earlier today " + time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(writtenAt, inSameDayAs: yesterday) {
            return "from iPhone, yesterday " + time
        }
        clock.dateFormat = "d MMM HH:mm"
        return "from iPhone, " + clock.string(from: writtenAt)
    }

    /* The newest morning there is, on or before `day`. */
    public func morning(onOrBefore day: String) -> (day: String, morning: MorningShare)? {
        mornings.filter { $0.key <= day }.max { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /* Keeps the last `days` mornings and workouts, counting back from `today`. */
    public func trimmed(today: String, days: Int = 14) -> HealthShare {
        let first = PlanView.addDays(today, -(days - 1))
        var out = self
        out.mornings = mornings.filter { $0.key >= first }
        out.workouts = workouts.filter { $0.dayKey >= first }
        return out
    }
}

/* One morning's numbers, as the iPhone read them. */
public struct MorningShare: Codable, Equatable, Sendable {
    public var readAt: Date
    public var restingHR: Double?
    public var restingHRNormal: Double?
    public var hrv: Double?
    public var hrvNormal: Double?
    public var sleepHours: Double?
    public var restingDays: Int
    public var hrvDays: Int

    public init(readAt: Date, restingHR: Double? = nil, restingHRNormal: Double? = nil, hrv: Double? = nil,
                hrvNormal: Double? = nil, sleepHours: Double? = nil, restingDays: Int = 0, hrvDays: Int = 0) {
        self.readAt = readAt; self.restingHR = restingHR; self.restingHRNormal = restingHRNormal
        self.hrv = hrv; self.hrvNormal = hrvNormal; self.sleepHours = sleepHours
        self.restingDays = restingDays; self.hrvDays = hrvDays
    }

    enum CodingKeys: String, CodingKey { case readAt, restingHR, restingHRNormal, hrv, hrvNormal, sleepHours, restingDays, hrvDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        readAt = (try? c.decode(Date.self, forKey: .readAt)) ?? Date(timeIntervalSince1970: 0)
        restingHR = try? c.decode(Double.self, forKey: .restingHR)
        restingHRNormal = try? c.decode(Double.self, forKey: .restingHRNormal)
        hrv = try? c.decode(Double.self, forKey: .hrv)
        hrvNormal = try? c.decode(Double.self, forKey: .hrvNormal)
        sleepHours = try? c.decode(Double.self, forKey: .sleepHours)
        restingDays = (try? c.decode(Int.self, forKey: .restingDays)) ?? 0
        hrvDays = (try? c.decode(Int.self, forKey: .hrvDays)) ?? 0
    }

    public var isEmpty: Bool { restingHR == nil && hrv == nil && sleepHours == nil }
}

/* One Health workout, as the log form offers it. */
public struct WorkoutShare: Codable, Equatable, Sendable {
    public var id: String
    public var dayKey: String
    public var sport: String
    public var typeName: String
    public var start: Date
    public var seconds: Double
    public var movingSeconds: Double?
    public var metres: Double?
    public var avgHr: Double?
    public var source: String

    public init(id: String, dayKey: String, sport: String, typeName: String, start: Date, seconds: Double,
                movingSeconds: Double? = nil, metres: Double? = nil, avgHr: Double? = nil, source: String) {
        self.id = id; self.dayKey = dayKey; self.sport = sport; self.typeName = typeName; self.start = start
        self.seconds = seconds; self.movingSeconds = movingSeconds; self.metres = metres; self.avgHr = avgHr; self.source = source
    }

    enum CodingKeys: String, CodingKey { case id, dayKey, sport, typeName, start, seconds, movingSeconds, metres, avgHr, source }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        sport = (try? c.decode(String.self, forKey: .sport)) ?? "other"
        typeName = (try? c.decode(String.self, forKey: .typeName)) ?? "Workout"
        start = (try? c.decode(Date.self, forKey: .start)) ?? Date(timeIntervalSince1970: 0)
        seconds = (try? c.decode(Double.self, forKey: .seconds)) ?? 0
        movingSeconds = try? c.decode(Double.self, forKey: .movingSeconds)
        metres = try? c.decode(Double.self, forKey: .metres)
        avgHr = try? c.decode(Double.self, forKey: .avgHr)
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
    }
}
