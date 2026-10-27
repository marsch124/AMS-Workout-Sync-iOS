import Foundation

/*
 * How long he slept, out of what Apple Health holds for the night.
 *
 * Health does not hold one night as one record. It holds pieces — core, deep,
 * REM, or plain "asleep" — and nothing stops the same stretch arriving twice:
 * Garmin can hand the same night over again on a later sync, a phase can sit
 * inside a plain "asleep" that covers the whole night, and a second device
 * worn to bed writes a night of its own. Adding every piece up counted his
 * 5h 20m as 10h 40m (27 October 2026).
 *
 * So each source's pieces are laid on one timeline and an overlap counts
 * once; a gap where he lay awake stays a gap. Two sources are two opinions of
 * the same night, never two nights, so the one that saw the most sleep is
 * taken whole rather than the two being mixed.
 */
public enum Sleep {

    public struct Span: Equatable {
        public let source: String
        public let start: Date
        public let end: Date

        public init(source: String, start: Date, end: Date) {
            self.source = source
            self.start = start
            self.end = end
        }
    }

    /* Seconds asleep, or nil when nothing was recorded. */
    public static func asleepSeconds(_ spans: [Span]) -> TimeInterval? {
        let bySource = Dictionary(grouping: spans.filter { $0.end > $0.start }, by: \.source)
        let best = bySource.values.map(coveredSeconds).max() ?? 0
        return best > 0 ? best : nil
    }

    /* Time covered by at least one span: overlaps once, gaps not at all. */
    static func coveredSeconds(_ spans: [Span]) -> TimeInterval {
        var total: TimeInterval = 0
        var runStart: Date?
        var runEnd: Date?
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let end = runEnd, span.start <= end {
                runEnd = max(end, span.end)
                continue
            }
            if let start = runStart, let end = runEnd { total += end.timeIntervalSince(start) }
            runStart = span.start
            runEnd = span.end
        }
        if let start = runStart, let end = runEnd { total += end.timeIntervalSince(start) }
        return total
    }
}
