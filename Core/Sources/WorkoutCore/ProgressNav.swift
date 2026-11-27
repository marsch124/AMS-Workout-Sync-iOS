import Foundation

/*
 * 2.20 (his pick "1 + 2 together", 27 Nov 2026): the navigation at the top of Progress — eight colour
 * tiles with a live figure each, and, once they have scrolled out of sight, a slim pinned row of the same
 * colour chips whose chip for the part on screen is filled. The words and the rules live here; the
 * colours and the views live in the app (ProgressNavViews.swift).
 */
public enum ProgressNav {

    public enum Part: String, CaseIterable, Identifiable {
        case race, fitness, load, zones, routes, kept, bests, month
        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .race: return "Race"
            case .fitness: return "Fitness"
            case .load: return "Load"
            case .zones: return "Zones"
            case .routes: return "Routes"
            case .kept: return "Kept"
            case .bests: return "Bests"
            case .month: return "Month"
            }
        }

        /* The scroll target of the part's first card. */
        public var anchor: String { "part-" + rawValue }
    }

    /* "33 weeks", "12 days", "1 day", "Today"; a dash once the race has been. Three weeks and less count in days, like the Road card. */
    public static func raceFigure(daysToGo: Int, weeksToGo: Int) -> String {
        if daysToGo < 0 { return "—" }
        if daysToGo == 0 { return "Today" }
        if daysToGo <= 21 { return daysToGo == 1 ? "1 day" : "\(daysToGo) days" }
        return weeksToGo == 1 ? "1 week" : "\(weeksToGo) weeks"
    }

    /* "2026-10" → "October"; the key itself when it is not a month. */
    public static func monthName(_ key: String) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December"]
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let m = Int(parts[1]), (1...12).contains(m) else { return key }
        return names[m - 1]
    }

    /* "Nov" for "2026-11". */
    public static func monthShort(_ key: String) -> String { String(monthName(key).prefix(3)) }

    /*
     * The part on screen: of the parts whose first card has reached the reading line (its top at or above
     * `line`, measured from the top of the visible page), the one that reached it last — the lowest such
     * top. Nil while no part has reached it (the page is at its very top).
     */
    public static func active(tops: [Part: Double], line: Double) -> Part? {
        tops.filter { $0.value <= line }.max { a, b in
            a.value != b.value ? a.value < b.value
                : (Part.allCases.firstIndex(of: a.key) ?? 0) < (Part.allCases.firstIndex(of: b.key) ?? 0)
        }?.key
    }
}
