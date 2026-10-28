import Foundation

/*
 * This morning's reading, and his own normal to hold it against.
 *
 * Health holds readings, not days: Garmin can hand the same morning over
 * twice, write a day's resting heart rate again as the day goes on, and a
 * second device adds its own. Averaging every reading let a day held twice
 * count twice, and the normal took in this morning's own reading — so the
 * morning was partly measured against itself (28 October 2026).
 *
 * So each day is one value, the last one written for it. The normal is the
 * average of the days before the morning being shown, at most a fortnight of
 * them, and there is no normal at all until a few days are there to make one:
 * a normal from one or two days would invent a trend out of nothing.
 */
public enum Fortnight {

    public struct Sample: Equatable {
        public let end: Date
        public let value: Double

        public init(end: Date, value: Double) {
            self.end = end
            self.value = value
        }
    }

    public struct Reading: Equatable {
        /* The newest day's value, when that day is today or yesterday. */
        public let latest: Double?
        /* The average of the days before it, once there are enough of them. */
        public let normal: Double?
        /* How many earlier days there were to make the normal from. */
        public let days: Int

        public init(latest: Double?, normal: Double?, days: Int) {
            self.latest = latest
            self.normal = normal
            self.days = days
        }
    }

    public static let daysNeeded = 4

    public static func reading(_ samples: [Sample], now: Date, calendar: Calendar = .current) -> Reading {
        var byDay: [Date: Sample] = [:]
        for s in samples {
            let day = calendar.startOfDay(for: s.end)
            if let kept = byDay[day], kept.end >= s.end { continue }
            byDay[day] = s
        }
        let today = calendar.startOfDay(for: now)
        guard let newest = byDay.keys.max(),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              newest >= yesterday,
              let from = calendar.date(byAdding: .day, value: -14, to: newest)
        else { return Reading(latest: nil, normal: nil, days: 0) }
        let earlier = byDay.filter { $0.key < newest && $0.key >= from }.map(\.value.value)
        let normal = earlier.count >= daysNeeded ? earlier.reduce(0, +) / Double(earlier.count) : nil
        return Reading(latest: byDay[newest]?.value, normal: normal, days: earlier.count)
    }
}
