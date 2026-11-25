import Foundation

/*
 * Shoes and bikes (round 28, pick 37). Each item is one key on the shelf
 * (`gear/<id>`), so two devices editing two shoes both win. Kilometres are never
 * stored as a running total (a total added on two devices would be wrong): they
 * are the starting figure he typed plus the logged distance of every done session
 * of the kind's sport, on the days the item was in use. Pure; the app hands in the
 * sessions.
 */

public enum GearKind: String, Codable, CaseIterable, Sendable {
    case shoes, bike, other

    public var word: String {
        switch self {
        case .shoes: return "Running shoes"
        case .bike: return "Bike"
        case .other: return "Other"
        }
    }

    /* The plan's sport whose sessions count; Other counts nothing by itself. */
    public var sport: String? {
        switch self {
        case .shoes: return "run"
        case .bike: return "bike"
        case .other: return nil
        }
    }

    /* "14 runs" */
    public func sessionsWord(_ n: Int) -> String {
        switch self {
        case .shoes: return n == 1 ? "1 run" : "\(n) runs"
        case .bike: return n == 1 ? "1 ride" : "\(n) rides"
        case .other: return n == 1 ? "1 session" : "\(n) sessions"
        }
    }
}

/* A stretch of days it was the one in use: `from` counts, `until` (the day it was swapped out) does not. */
public struct GearPeriod: Codable, Equatable, Sendable {
    public var from: String
    public var until: String?

    public init(from: String, until: String? = nil) { self.from = from; self.until = until }

    public func contains(_ day: String) -> Bool { day >= from && (until.map { day < $0 } ?? true) }
}

/* One logged session, as the app reads it from the plan; `km` is nil or 0 when no distance was logged. */
public struct GearSession: Equatable, Sendable {
    public var day: String
    public var sport: String
    public var km: Double?

    public init(day: String, sport: String, km: Double?) { self.day = day; self.sport = sport; self.km = km }
}

public struct GearCount: Equatable, Sendable {
    public var km: Double
    /* Done sessions of its sport while it was in use. */
    public var sessions: Int
    /* Of those, how many logged no distance and so counted nothing. */
    public var withoutDistance: Int
}

public struct GearItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: GearKind
    public var periods: [GearPeriod]
    public var startKm: Double
    public var limitKm: Double?
    public var retired: Bool
    /* Kept when it was retired, so the figure never moves afterwards. */
    public var finalKm: Double?

    public init(id: String = UUID().uuidString, name: String, kind: GearKind, since: String? = nil,
                startKm: Double = 0, limitKm: Double? = nil) {
        self.id = id; self.name = name; self.kind = kind
        self.periods = since.map { [GearPeriod(from: $0)] } ?? []
        self.startKm = startKm; self.limitKm = limitKm
        self.retired = false; self.finalKm = nil
    }

    private enum Key: String, CodingKey { case id, name, kind, periods, startKm, limitKm, retired, finalKm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        kind = (try? c.decodeIfPresent(GearKind.self, forKey: .kind)) ?? .other
        periods = (try? c.decodeIfPresent([GearPeriod].self, forKey: .periods)) ?? []
        startKm = max(0, (try? c.decodeIfPresent(Double.self, forKey: .startKm)) ?? 0)
        if let l = try? c.decodeIfPresent(Double.self, forKey: .limitKm), l > 0 { limitKm = l } else { limitKm = nil }
        retired = (try? c.decodeIfPresent(Bool.self, forKey: .retired)) ?? false
        finalKm = try? c.decodeIfPresent(Double.self, forKey: .finalKm)
    }

    /* The one in use now: not retired, and its last stretch is still open. */
    public var inUse: Bool { !retired && periods.last.map { $0.until == nil } ?? false }

    /* The day its current (or last) stretch began. */
    public var since: String? { periods.last?.from }

    /* Kilometres so far, and what was counted. A retired one shows the figure it was retired with. */
    public func count(_ sessions: [GearSession]) -> GearCount {
        var km = startKm, n = 0, without = 0
        if let sport = kind.sport {
            for s in sessions where s.sport == sport && periods.contains(where: { $0.contains(s.day) }) {
                n += 1
                if let d = s.km, d > 0 { km += d } else { without += 1 }
            }
        }
        if retired, let f = finalKm { km = f }
        return GearCount(km: km, sessions: n, withoutDistance: without)
    }

    /* "14 runs, 3 without a distance"; Other says what it counts. */
    public func countWords(_ c: GearCount) -> String {
        guard kind.sport != nil else { return "Counts only the kilometres you gave it" }
        if c.sessions == 0 { return "No \(kind == .shoes ? "runs" : "rides") logged yet" }
        return c.withoutDistance > 0 ? "\(kind.sessionsWord(c.sessions)), \(c.withoutDistance) without a distance"
                                      : kind.sessionsWord(c.sessions)
    }
}

public enum GearSet {
    /* Puts `id` in use from `day`; the one of the same kind that was in use is put aside that day. Returns the whole list. */
    public static func using(_ id: String, from day: String, in items: [GearItem]) -> [GearItem] {
        guard let target = items.first(where: { $0.id == id }), !target.retired, !target.inUse else { return items }
        return items.map { item in
            var i = item
            if i.id == id {
                i.periods.append(GearPeriod(from: day))
            } else if i.kind == target.kind, i.inUse {
                i = closed(i, on: day)
            }
            return i
        }
    }

    /* Puts one aside from `day` (it stays in the list, in use by none). */
    public static func putAside(_ id: String, on day: String, in items: [GearItem]) -> [GearItem] {
        items.map { $0.id == id && $0.inUse ? closed($0, on: day) : $0 }
    }

    /* Retired: closed that day, its final figure kept. */
    public static func retired(_ id: String, on day: String, in items: [GearItem], sessions: [GearSession]) -> [GearItem] {
        items.map { item in
            guard item.id == id, !item.retired else { return item }
            var i = closed(item, on: day)
            i.finalKm = i.count(sessions).km
            i.retired = true
            return i
        }
    }

    /* A stretch that would hold no day at all (it began the day it ended) is dropped. */
    private static func closed(_ item: GearItem, on day: String) -> GearItem {
        var i = item
        guard var last = i.periods.last, last.until == nil else { return i }
        if last.from >= day { i.periods.removeLast() } else { last.until = day; i.periods[i.periods.count - 1] = last }
        return i
    }
}
