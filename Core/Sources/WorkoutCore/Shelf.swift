import Foundation

/*
 * The shelf (round 28): small things that must follow him between his
 * iPhone, iPad and Mac and have no place in the plan — favourite sessions, an
 * "away" period, extra facts logged with a session, his shoes and bikes, the
 * race page's ticks. It is one file, `shelf.json`, kept on each device and met
 * in the app's iCloud folder beside the plan; it is never part of `PlanBook`
 * or `BookMerge`.
 *
 * A dictionary from a key ("favourites", "session/<key>/niggle", …) to an
 * entry: the value (as JSON text), when it was set (whole milliseconds), on
 * which device, and whether it was taken away. When two shelves meet, per key
 * the newest stamp wins; the same stamp: the larger device id; then the larger
 * entry as written — so every device makes the same choice whichever way round
 * they meet (commutative, associative, idempotent). A removal is an entry too
 * (a tombstone), so a device that still has the old value cannot bring it back.
 *
 * Kept, never dropped: an entry this build cannot read (a newer build's) stays
 * in the file as it was written, and fields a newer build adds to an entry or
 * to the file are written back untouched. A newer build may add fields and
 * raise `format`, but must keep `stamp` (ms) and `device` on every entry and
 * `value` as JSON text; anything else needs a new file name.
 */
public struct ShelfDoc: Equatable, Sendable {
    public static let currentFormat = 1
    /* The largest value one entry may hold (its JSON text). */
    public static let maxValueBytes = 64 * 1024
    /* The longest key. */
    public static let maxKeyLength = 200

    public enum Problem: Error, Equatable {
        case badKey
        case tooLarge(Int)
        case notEncodable
    }

    public var format: Int = ShelfDoc.currentFormat
    public var entries: [String: ShelfEntry] = [:]
    /* Entries this build could not read: kept exactly, by key. */
    public var unreadable: [String: ShelfJSON] = [:]
    /* Fields at the top of the file this build does not know: kept. */
    public var extra: [String: ShelfJSON] = [:]

    public init() {}

    // MARK: the typed front

    /* The value for a key, or nil when there is none, it was taken away, or it does not read as `T`. */
    public func get<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let e = entries[key], !e.removed, let text = e.value else { return nil }
        return try? ShelfDoc.valueDecoder.decode(T.self, from: Data(text.utf8))
    }

    /* True when the key holds a value (not taken away). */
    public func has(_ key: String) -> Bool {
        guard let e = entries[key] else { return false }
        return !e.removed && e.value != nil
    }

    /* The keys holding a value, beginning with `prefix`, sorted. */
    public func keys(prefix: String = "") -> [String] {
        entries.filter { $0.key.hasPrefix(prefix) && !$0.value.removed && $0.value.value != nil }.map(\.key).sorted()
    }

    public mutating func set<T: Encodable>(_ value: T, for key: String, device: String, now: Date = Date()) throws {
        guard Self.validKey(key) else { throw Problem.badKey }
        guard let data = try? Self.valueEncoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            throw Problem.notEncodable
        }
        guard data.count <= Self.maxValueBytes else { throw Problem.tooLarge(data.count) }
        entries[key] = ShelfEntry(value: text, stampMs: next(key, now: now), device: device, removed: false)
        unreadable[key] = nil
    }

    /* Takes a key away on every device: a tombstone with a new stamp, even for a key not seen here yet (another device may hold it). Already taken away: nothing happens. */
    public mutating func remove(_ key: String, device: String, now: Date = Date()) {
        guard Self.validKey(key), entries[key]?.removed != true else { return }
        entries[key] = ShelfEntry(value: nil, stampMs: next(key, now: now), device: device, removed: true)
        unreadable[key] = nil
    }

    public static func validKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= maxKeyLength && !key.contains("\n")
    }

    /* A stamp that never goes backwards for one key, even with the clock set back. */
    private func next(_ key: String, now: Date) -> Int64 {
        var m = ShelfEntry.ms(now)
        if let old = entries[key]?.stampMs { m = max(m, old + 1) }
        if let raw = unreadable[key], let old = raw.stampMs { m = max(m, old + 1) }
        return m
    }

    /* How values are written: keys sorted, dates in whole milliseconds since 1970. */
    public static var valueEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    public static var valueDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }

    // MARK: two shelves met in one

    public static func merge(_ a: ShelfDoc, _ b: ShelfDoc) -> ShelfDoc {
        var out = ShelfDoc()
        out.format = max(a.format, b.format)
        for key in Set(a.entries.keys).union(b.entries.keys) {
            switch (a.entries[key], b.entries[key]) {
            case let (x?, y?): out.entries[key] = ShelfEntry.wins(x, over: y) ? x : y
            case let (x?, nil): out.entries[key] = x
            case let (nil, y?): out.entries[key] = y
            default: break
            }
        }
        // An entry nobody here can read stands until a readable one for its key arrives with a later stamp.
        for key in Set(a.unreadable.keys).union(b.unreadable.keys) {
            let raw: ShelfJSON
            switch (a.unreadable[key], b.unreadable[key]) {
            case let (x?, y?): raw = ShelfJSON.larger(x, y)
            case let (x?, nil): raw = x
            case let (nil, y?): raw = y
            default: continue
            }
            if let e = out.entries[key], e.stampMs > (raw.stampMs ?? Int64.min) { continue }
            out.entries[key] = nil
            out.unreadable[key] = raw
        }
        for key in Set(a.extra.keys).union(b.extra.keys) {
            switch (a.extra[key], b.extra[key]) {
            case let (x?, y?): out.extra[key] = ShelfJSON.larger(x, y)
            case let (x?, nil): out.extra[key] = x
            case let (nil, y?): out.extra[key] = y
            default: break
            }
        }
        return out
    }

    public static func merge(_ docs: [ShelfDoc]) -> ShelfDoc {
        docs.reduce(ShelfDoc()) { merge($0, $1) }
    }

    /*
     * One meeting: this device's shelf with the iCloud file and its conflict
     * copies. An empty `cloud` is "nothing there yet", never "everything gone".
     */
    public static func join(local: ShelfDoc, cloud: [ShelfDoc], cloudFileThere: Bool)
        -> (doc: ShelfDoc, changesLocal: Bool, changesCloud: Bool) {
        let mine = merge([local])
        let joined = merge([mine] + cloud)
        let theirs = cloudFileThere ? cloud.first.map { merge([$0]) } : nil
        return (joined, joined != mine, theirs == nil || joined != theirs || cloud.count > 1)
    }

    // MARK: the file

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }

    public static func decoded(_ data: Data) throws -> ShelfDoc {
        try JSONDecoder().decode(ShelfDoc.self, from: data)
    }
}

extension ShelfDoc: Codable {
    /*
     * Read forgivingly, key by key: a missing part is empty, an entry that
     * cannot be read is kept as it is. Only a file that is not a JSON object
     * at all fails (the app then keeps it aside and starts empty).
     */
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ShelfCodingKey.self)
        for key in c.allKeys {
            switch key.stringValue {
            case "format":
                format = try c.decode(Int.self, forKey: key)
            case "entries":
                // Not an object: the whole file is unreadable (kept aside by the app), never half-read.
                let inner = try c.nestedContainer(keyedBy: ShelfCodingKey.self, forKey: key)
                for k in inner.allKeys {
                    if let e = try? inner.decode(ShelfEntry.self, forKey: k) {
                        entries[k.stringValue] = e
                    } else {
                        unreadable[k.stringValue] = try inner.decode(ShelfJSON.self, forKey: k)
                    }
                }
            default:
                extra[key.stringValue] = try c.decode(ShelfJSON.self, forKey: key)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ShelfCodingKey.self)
        for (k, v) in extra where k != "format" && k != "entries" { try c.encode(v, forKey: ShelfCodingKey(k)) }
        try c.encode(format, forKey: ShelfCodingKey("format"))
        var inner = c.nestedContainer(keyedBy: ShelfCodingKey.self, forKey: ShelfCodingKey("entries"))
        for (k, v) in unreadable { try inner.encode(v, forKey: ShelfCodingKey(k)) }
        for (k, v) in entries { try inner.encode(v, forKey: ShelfCodingKey(k)) }
    }
}

/* One key's entry on the shelf. */
public struct ShelfEntry: Equatable, Sendable {
    /* The value as JSON text; nil for a removal. */
    public var value: String?
    /* When it was set, in whole milliseconds since 1970. */
    public var stampMs: Int64
    public var device: String
    public var removed: Bool
    /* Fields a newer build added to the entry: written back untouched. */
    public var extra: [String: ShelfJSON] = [:]

    public init(value: String?, stampMs: Int64, device: String, removed: Bool, extra: [String: ShelfJSON] = [:]) {
        self.value = value; self.stampMs = stampMs; self.device = device; self.removed = removed; self.extra = extra
    }

    public var stamp: Date { Date(timeIntervalSince1970: Double(stampMs) / 1000) }

    public static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }

    /* The total order of the merge: stamp, then device id, then the entry as written. */
    static func wins(_ x: ShelfEntry, over y: ShelfEntry) -> Bool {
        if x.stampMs != y.stampMs { return x.stampMs > y.stampMs }
        if x.device != y.device { return x.device > y.device }
        return x.canonical.lexicographicallyPrecedes(y.canonical) == false
    }

    var canonical: Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)) ?? Data()
    }
}

extension ShelfEntry: Codable {
    /* Strict on the four known fields (a wrong type: the whole entry is kept unread); anything else kept in `extra`. */
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ShelfCodingKey.self)
        stampMs = try c.decode(Int64.self, forKey: ShelfCodingKey("stamp"))
        device = try c.decodeIfPresent(String.self, forKey: ShelfCodingKey("device")) ?? ""
        removed = try c.decodeIfPresent(Bool.self, forKey: ShelfCodingKey("removed")) ?? false
        value = try c.decodeIfPresent(String.self, forKey: ShelfCodingKey("value"))
        for key in c.allKeys where !["stamp", "device", "removed", "value"].contains(key.stringValue) {
            extra[key.stringValue] = try c.decode(ShelfJSON.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ShelfCodingKey.self)
        for (k, v) in extra { try c.encode(v, forKey: ShelfCodingKey(k)) }
        try c.encode(stampMs, forKey: ShelfCodingKey("stamp"))
        try c.encode(device, forKey: ShelfCodingKey("device"))
        try c.encode(removed, forKey: ShelfCodingKey("removed"))
        if let value { try c.encode(value, forKey: ShelfCodingKey("value")) }
    }
}

/* Any JSON, kept as it was read (used for what this build does not understand). */
public enum ShelfJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([ShelfJSON])
    case object([String: ShelfJSON])

    public init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: ShelfCodingKey.self) {
            var o: [String: ShelfJSON] = [:]
            for k in c.allKeys { o[k.stringValue] = try c.decode(ShelfJSON.self, forKey: k) }
            self = .object(o)
            return
        }
        if var a = try? decoder.unkeyedContainer() {
            var out: [ShelfJSON] = []
            while !a.isAtEnd { out.append(try a.decode(ShelfJSON.self)) }
            self = .array(out)
            return
        }
        let s = try decoder.singleValueContainer()
        if s.decodeNil() { self = .null }
        else if let b = try? s.decode(Bool.self) { self = .bool(b) }
        else if let i = try? s.decode(Int64.self) { self = .int(i) }
        else if let d = try? s.decode(Double.self) { self = .double(d) }
        else { self = .string(try s.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let o):
            var c = encoder.container(keyedBy: ShelfCodingKey.self)
            for (k, v) in o { try c.encode(v, forKey: ShelfCodingKey(k)) }
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for v in a { try c.encode(v) }
        case .null:
            var s = encoder.singleValueContainer(); try s.encodeNil()
        case .bool(let b):
            var s = encoder.singleValueContainer(); try s.encode(b)
        case .int(let i):
            var s = encoder.singleValueContainer(); try s.encode(i)
        case .double(let d):
            var s = encoder.singleValueContainer(); try s.encode(d)
        case .string(let t):
            var s = encoder.singleValueContainer(); try s.encode(t)
        }
    }

    /* The `stamp` of an entry kept unread, when it has one in whole milliseconds. */
    var stampMs: Int64? {
        guard case .object(let o) = self else { return nil }
        switch o["stamp"] {
        case .int(let i)?: return i
        case .double(let d)?: return Int64(d)
        default: return nil
        }
    }

    var canonical: Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)) ?? Data()
    }

    /* Of two, the one every device picks: the later stamp, then the larger as written. */
    static func larger(_ x: ShelfJSON, _ y: ShelfJSON) -> ShelfJSON {
        let sx = x.stampMs ?? Int64.min, sy = y.stampMs ?? Int64.min
        if sx != sy { return sx > sy ? x : y }
        return x.canonical.lexicographicallyPrecedes(y.canonical) ? y : x
    }
}

private struct ShelfCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
