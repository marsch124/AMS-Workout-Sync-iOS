import Foundation

/*
 * Stop sign and "I'm ill", the same on all his devices (2.3).
 *
 * Only the iPhone makes suggestion cards, but he may tap Stop sign or
 * "I'm ill" on the iPad or the Mac. Those taps live in each device's
 * suggestions.json; this small file, `pause.json` beside the plan in the
 * app's iCloud folder, carries them to the other devices. It is never part
 * of the plan document or its merge.
 *
 * Two parts, each with its own stamp: the stop sign (stopSignSince,
 * doctorSeenOn) and the illness (illSince, illness, symptomFreeSince,
 * stillNotRight). When two devices differ, per part:
 *   - the newest stamp wins, EXCEPT that
 *   - a part that is on (paused, or ill) is never lifted by an "all clear"
 *     unless that all clear ended this very pause or a later one (`lifts` is
 *     the stamp of the pause it ended, and must be at least the pause's own
 *     stamp). An older all clear, or one made on a device that never saw this
 *     pause, never lifts it.
 * A part never touched has stamp 0 (a device from before 2.3 sharing).
 */
public struct PauseStamp: Codable, Equatable, Sendable {
    /* When this part last changed (milliseconds since 1970 in the file). */
    public var at: Date
    /* For an all clear only: the stamp of the pause it ended. */
    public var lifts: Date?

    public init(at: Date, lifts: Date? = nil) { self.at = at; self.lifts = lifts }

    public static let never = PauseStamp(at: Date(timeIntervalSince1970: 0))
}

public struct PauseShare: Codable, Equatable, Sendable {
    public static let format = 1

    public var format: Int = PauseShare.format
    public var health: RBHealthTaps
    public var stop: PauseStamp
    public var ill: PauseStamp

    public init(health: RBHealthTaps = RBHealthTaps(), stop: PauseStamp = .never, ill: PauseStamp = .never) {
        self.health = health; self.stop = stop; self.ill = ill
    }

    enum CodingKeys: String, CodingKey { case format, health, stop, ill }

    /* Strict, like the taps themselves: a file that cannot be read is never taken for "all clear". */
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? 1
        health = try c.decode(RBHealthTaps.self, forKey: .health)
        stop = try c.decodeIfPresent(PauseStamp.self, forKey: .stop) ?? .never
        ill = try c.decodeIfPresent(PauseStamp.self, forKey: .ill) ?? .never
    }

    // MARK: on or off

    /* The stop sign part is on: tapped, and no doctor seen since. */
    public static func stopOn(_ h: RBHealthTaps) -> Bool {
        guard let s = h.stopSignSince else { return false }
        return (h.doctorSeenOn ?? "") < s
    }

    /* The illness part is on: he said he was ill and has not taken it back (the steps run out by the calendar). */
    public static func illOn(_ h: RBHealthTaps) -> Bool { h.illSince != nil }

    // MARK: joining

    /* Which of two versions of one part stands. True: `a`. */
    static func keepsFirst(aOn: Bool, a: PauseStamp, bOn: Bool, b: PauseStamp) -> Bool {
        switch (aOn, bOn) {
        case (true, false):
            // b may lift a only if b ended this very pause (or a later one) and is not older.
            guard let lifted = b.lifts, lifted >= a.at, b.at >= a.at else { return true }
            return false
        case (false, true):
            guard let lifted = a.lifts, lifted >= b.at, a.at >= b.at else { return false }
            return true
        default:
            return a.at >= b.at
        }
    }

    /* The two joined: per part, by the rule above. */
    public static func join(_ a: PauseShare, _ b: PauseShare) -> PauseShare {
        var out = PauseShare()
        if keepsFirst(aOn: stopOn(a.health), a: a.stop, bOn: stopOn(b.health), b: b.stop) {
            out.health.stopSignSince = a.health.stopSignSince; out.health.doctorSeenOn = a.health.doctorSeenOn; out.stop = a.stop
        } else {
            out.health.stopSignSince = b.health.stopSignSince; out.health.doctorSeenOn = b.health.doctorSeenOn; out.stop = b.stop
        }
        let first = keepsFirst(aOn: illOn(a.health), a: a.ill, bOn: illOn(b.health), b: b.ill)
        let w = first ? a : b, o = first ? b : a
        out.health.illSince = w.health.illSince
        out.health.illness = w.health.illness
        out.health.symptomFreeSince = w.health.symptomFreeSince
        out.health.stillNotRight = w.health.stillNotRight
        out.ill = w.ill
        // The same illness on both: a "Still not right" tapped on either is kept (it only adds easy days).
        if w.health.illSince != nil, w.health.illSince == o.health.illSince {
            out.health.stillNotRight = Array(Set(w.health.stillNotRight + o.health.stillNotRight)).sorted()
        }
        return out
    }

    /* This device's version joined with every version found in iCloud (the file and any conflict copies). */
    public static func join(local: PauseShare, cloud: [PauseShare]) -> PauseShare {
        cloud.reduce(local) { join($0, $1) }
    }

    // MARK: a tap on this device

    /* The stamps after a tap here moved the taps from `old` to `new`, at `now`. */
    public static func stamped(_ was: PauseShare, to new: RBHealthTaps, now: Date) -> PauseShare {
        var out = was
        out.health = new
        let o = was.health
        if o.stopSignSince != new.stopSignSince || o.doctorSeenOn != new.doctorSeenOn {
            let lifting = stopOn(o) && !stopOn(new)
            out.stop = PauseStamp(at: max(now, was.stop.at), lifts: lifting ? was.stop.at : nil)
        }
        if o.illSince != new.illSince || o.illness != new.illness || o.symptomFreeSince != new.symptomFreeSince
            || o.stillNotRight != new.stillNotRight {
            let lifting = illOn(o) && !illOn(new)
            out.ill = PauseStamp(at: max(now, was.ill.at), lifts: lifting ? was.ill.at : nil)
        }
        return out
    }

    // MARK: the file

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decoded(_ data: Data) throws -> PauseShare {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return try d.decode(PauseShare.self, from: data)
    }
}
