import Foundation

/*
 * The diary as it travels through iCloud: how he felt each morning and how
 * hard a workout from Apple Health was. Every device may answer, so every
 * answer carries its own mark and the newest answer per day (per workout)
 * wins when two devices meet. Nothing is ever taken out — the app has no way
 * to delete an answer, only to give a new one.
 *
 * Keys of the marks: "feel:<day key>" and "answer:<Health workout id>".
 *
 * Since 2.4 a morning answer taken over from another app says which app gave
 * it (`feelFrom`: day → "morning" for Magic Morning), so every device shows
 * "from Magic Morning" and leaves the answer to that app. It follows the
 * day's winning answer; an answer given in this app carries none. An older
 * app version passes the field over.
 *
 * Since 2.10 a morning answer may carry a few words (`notes`: day → comment,
 * mark "note:<day>"), merged like the answer: the newest mark wins, the same
 * mark with two texts keeps the larger. An older app version ignores it.
 */
public struct DiaryDoc: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format: Int = DiaryDoc.currentFormat
    /* Day key → 1…5 (Feel). */
    public var feel: [String: Int]
    /* Health workout id → 1…10. */
    public var answers: [String: Double]
    public var stamps: [String: Date]
    /* Day key → the app that gave the answer, when it was not this one. */
    public var feelFrom: [String: String]
    /* Day key → the few words he added to that morning's answer. */
    public var notes: [String: String]

    public init(feel: [String: Int] = [:], answers: [String: Double] = [:], stamps: [String: Date] = [:],
                feelFrom: [String: String] = [:], notes: [String: String] = [:]) {
        self.feel = feel; self.answers = answers; self.stamps = stamps; self.feelFrom = feelFrom; self.notes = notes
    }

    enum CodingKeys: String, CodingKey { case format, feel, answers, stamps, feelFrom, notes }

    /* Read forgivingly: a field that is missing is empty; fields this app does not know are passed over. */
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(Int.self, forKey: .format)) ?? 1
        feel = try c.decodeIfPresent([String: Int].self, forKey: .feel) ?? [:]
        answers = try c.decodeIfPresent([String: Double].self, forKey: .answers) ?? [:]
        stamps = try c.decodeIfPresent([String: Date].self, forKey: .stamps) ?? [:]
        feelFrom = (try? c.decodeIfPresent([String: String].self, forKey: .feelFrom)) ?? [:]
        notes = (try? c.decodeIfPresent([String: String].self, forKey: .notes)) ?? [:]
    }

    public var isFromNewerApp: Bool { format > DiaryDoc.currentFormat }

    // MARK: on disk

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decoded(_ data: Data) throws -> DiaryDoc {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return try d.decode(DiaryDoc.self, from: data)
    }

    // MARK: answering

    /* A mark that never goes backwards, even with the clock set back. */
    /* Whole milliseconds, the way the file keeps them, so a mark reads back exactly as it was made. */
    private func next(_ key: String, now: Date) -> Date {
        var m = PlanBook.ms(now)
        if let old = stamps[key] { m = max(m, PlanBook.ms(old) + 1) }
        return PlanBook.date(ms: m)
    }

    /* `from`: the other app that gave the answer; nil when he answered in this app. */
    public mutating func setFeel(_ value: Int, on day: String, from: String? = nil, now: Date = Date()) {
        feel[day] = value
        feelFrom[day] = from
        stamps["feel:" + day] = next("feel:" + day, now: now)
    }

    /* The few words with the day's answer; an empty text is "no comment" (and replaces an older one). */
    public mutating func setNote(_ text: String, on day: String, now: Date = Date()) {
        notes[day] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stamps["note:" + day] = next("note:" + day, now: now)
    }

    public mutating func setAnswer(_ value: Double, for id: String, now: Date = Date()) {
        answers[id] = value
        stamps["answer:" + id] = next("answer:" + id, now: now)
    }

    // MARK: two diaries met in one

    /*
     * Per day and per workout, the answer with the later mark; no mark counts as
     * the earliest. The same mark with two different answers: the larger, so
     * every device makes the same choice. Pure: the same either way round.
     */
    public static func merged(_ a: DiaryDoc, _ b: DiaryDoc) -> DiaryDoc {
        var out = DiaryDoc()
        out.format = max(a.format, b.format)
        func pick<V: Comparable>(_ prefix: String, _ x: [String: V], _ y: [String: V]) -> [String: V] {
            var result: [String: V] = [:]
            for key in Set(x.keys).union(y.keys) {
                let sx = a.stamps[prefix + key], sy = b.stamps[prefix + key]
                switch (x[key], y[key]) {
                case let (p?, q?):
                    let tx = sx ?? .distantPast, ty = sy ?? .distantPast
                    result[key] = tx != ty ? (tx > ty ? p : q) : max(p, q)
                case let (p?, nil): result[key] = p
                case let (nil, q?): result[key] = q
                default: break
                }
                let stamp = [sx, sy].compactMap { $0 }.max()
                if let stamp { out.stamps[prefix + key] = stamp }
            }
            return result
        }
        out.feel = pick("feel:", a.feel, b.feel)
        out.answers = pick("answer:", a.answers, b.answers)
        out.notes = pick("note:", a.notes, b.notes)
        // Where the day's answer came from goes with the answer that won; two equal answers keep a known source.
        for (day, value) in out.feel {
            let ta = a.stamps["feel:" + day] ?? .distantPast, tb = b.stamps["feel:" + day] ?? .distantPast
            let fa = a.feel[day] == value ? a.feelFrom[day] : nil, fb = b.feel[day] == value ? b.feelFrom[day] : nil
            let from: String?
            if a.feel[day] == value, b.feel[day] == value {
                from = ta == tb ? (fa ?? fb) : (ta > tb ? fa : fb)
            } else {
                from = a.feel[day] == value ? fa : fb
            }
            if let from { out.feelFrom[day] = from }
        }
        return out
    }

    public static func merged(_ docs: [DiaryDoc]) -> DiaryDoc {
        guard var out = docs.first else { return DiaryDoc() }
        for d in docs.dropFirst() { out = merged(out, d) }
        return docs.count == 1 ? merged(out, out) : out
    }

    /*
     * One meeting: this device's diary with the iCloud file and its conflict
     * copies. An empty `cloud` is "nothing there yet", never "everything gone".
     */
    public static func join(local: DiaryDoc, cloud: [DiaryDoc], cloudFileThere: Bool)
        -> (doc: DiaryDoc, changesLocal: Bool, changesCloud: Bool, newerApp: Bool) {
        if (cloud + [local]).contains(where: \.isFromNewerApp) { return (local, false, false, true) }
        let mine = merged([local])
        let joined = merged([mine] + cloud)
        let theirs = cloudFileThere ? cloud.first.map { merged([$0]) } : nil
        return (joined, joined != mine, theirs == nil || joined != theirs || cloud.count > 1, false)
    }
}
