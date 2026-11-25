import AMSIcons
import SwiftUI
import WorkoutCore

/*
 * The web app's palette, carried across so the two apps look like one app:
 * the same five sport colours (his picture, v1.70.0), the same dark teal
 * ground at night and near-white by day.
 *
 * A sport colour is a fill. Where it has to carry words it is drawn darker on
 * a light screen — the web app's --sport-ink — because the bike's yellow reads
 * as a bar and not as a word on white.
 */
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

enum Theme {
    static let bg = Color.dynamic(light: 0xf6f8f8, dark: 0x0a1f1f)
    static let surface = Color.dynamic(light: 0xffffff, dark: 0x1a3535)
    static let surface2 = Color.dynamic(light: 0xeef3f3, dark: 0x21403f)
    static let text = Color.dynamic(light: 0x16302f, dark: 0xffffff)
    static let secondary = Color.dynamic(light: 0x5c7373, dark: 0xa0b8b8)
    static let border = Color.dynamic(light: 0xdce6e6, dark: 0x2a5555)
    static let danger = Color.dynamic(light: 0xc81e1e, dark: 0xff6b6b)

    static let today = Color.dynamic(light: 0x00875A, dark: 0x00C97B)
    /* Full-colour main buttons: white words need a deeper green than the bright night mint. */
    static let mainButton = Color.dynamic(light: 0x00875A, dark: 0x00875A)
    static let plan = Color.dynamic(light: 0x1266C8, dark: 0x3B9EFF)
    static let progress = Color.dynamic(light: 0x7C3AED, dark: 0xC084FC)
    static let settings = Color.dynamic(light: 0x5A6B7B, dark: 0x94A3B8)
    /* The hour mark on the week's extra blocks: a warm amber that belongs to no
       sport — the bike's yellow would have said "ride" under a strip where it does. */
    static let extraHour = Color.dynamic(light: 0xDE9B26, dark: 0xF0B855)

    /* The ground under Tomorrow: pale blue by day, a deep quiet blue at night —
       a place, not a state, so it never competes with a sport's colour. */
    static let tomorrow = Color.dynamic(light: 0xe8f1fb, dark: 0x122b3d)

    static func sportHex(_ id: String) -> UInt32 {
        switch id {
        case "swim": return 0x4f87f8
        case "bike", "brick": return 0xffd60a
        case "run": return 0x85ce6c
        case "strength": return 0xff8c1a
        case "rowing": return 0x0d9488
        case "mobility": return 0x8650fe
        case "race": return 0xef4444
        case "rest": return 0x64748b
        default: return 0x22d3ee
        }
    }

    static func sport(_ id: String) -> Color { Color(hex: sportHex(id)) }

    /*
     * A sport's "still to do" tint: the colour at a third by day (as before), raised at
     * night, where a third of it on the dark teal ground went murky and sports could not
     * be told apart. Done is the full colour, so it stays clearly stronger.
     */
    static func stillToDo(_ id: String) -> Color {
        let base = UIColor(Color(hex: sportHex(id)))
        return Color(UIColor { $0.userInterfaceStyle == .dark ? base.withAlphaComponent(0.58) : base.withAlphaComponent(0.34) })
    }

    /* Readable as text: the same hue, darker by day. */
    static func sportInk(_ id: String) -> Color {
        let hex = sportHex(id)
        // At night the slate of rest, breathing and meditation is too dim to read
        // on the dark cards (2.8:1); it gets a lighter slate there, and only there.
        let dark = Color(hex: id == "rest" ? 0xA3B1C2 : hex)
        let r = Double((hex >> 16) & 0xff) / 255 * 0.55
        let g = Double((hex >> 8) & 0xff) / 255 * 0.55
        let b = Double(hex & 0xff) / 255 * 0.55
        let light = Color(.sRGB, red: r, green: g, blue: b)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    static func icon(_ discipline: Discipline) -> String {
        switch discipline.id {
        case "swim", "bike", "run", "strength", "mobility": return "icon-" + discipline.id
        case "brick": return "icon-bike"
        // A moon, never the tick: the tick means done and nothing else
        // (his yes of 19 November 2026). The drawing is the icon library's "Night".
        case "rest": return "icon-rest"
        case "race": return "icon-race"
        default: return "icon-other"
        }
    }
}

/// The app's hand-drawn icons, drawn from the central icon library (AMS-Icons).
/// Same drawings, same strokes as the old template images: 1.9 on the 24-point
/// box, and 2.1 for the back arrow, tick, bars and plus, as the web app drew them.
/// The icon takes the foreground colour of the view around it.
struct Glyph: View {
    let name: String
    var size: CGFloat = 22
    private static let marks: [String: (AppMark, CGFloat)] = [
        "icon-back": (.triBack, 2.1),
        "icon-bike": (.triBike, 1.9),
        "icon-breathing": (.triBreathing, 1.9),
        "icon-camera": (.triCamera, 1.9),
        "icon-check": (.triCheck, 2.1),
        "icon-clock": (.triClock, 1.9),
        "icon-cloud": (.triCloud, 1.9),
        "icon-counts": (.triCounts, 2.1),
        "icon-heart": (.triHeart, 1.9),
        "icon-hike": (.triHike, 1.9),
        "icon-meditation": (.triMeditation, 1.9),
        "icon-mic": (.triMic, 1.9),
        "icon-mobility": (.triMobility, 1.9),
        "icon-other": (.triOther, 1.9),
        "icon-pen": (.triPen, 1.9),
        "icon-plan": (.triPlan, 1.9),
        "icon-plus": (.triPlus, 2.1),
        "icon-progress": (.triProgress, 1.9),
        "icon-race": (.triRace, 1.9),
        "icon-rest": (.moon, 1.9),
        "icon-rowing": (.triRowing, 1.9),
        "icon-run": (.triRun, 1.9),
        "icon-settings": (.triSettings, 1.9),
        "icon-share": (.triShare, 1.9),
        "icon-ski": (.triSki, 1.9),
        "icon-strength": (.triStrength, 1.9),
        "icon-stretch": (.triStretch, 1.9),
        "icon-swim": (.triSwim, 1.9),
        "icon-sync": (.triSync, 1.9),
        "icon-today": (.triToday, 1.9),
        "icon-walk": (.triWalk, 1.9),
        "icon-yoga": (.triYoga, 1.9),
    ]
    var body: some View {
        let (mark, weight) = Glyph.marks[name] ?? (.triOther, 1.9)
        // One element for VoiceOver and the screen tests, as the picture it replaced was:
        // a drawn mark is none by itself, so a label on the view around it ("Done" on the
        // tick) had nothing to hold on to (2.4 to 2.4.2; two screen tests went red).
        AppMarkView(mark, size: size, lineWidth: weight)
            .accessibilityElement()
            .accessibilityAddTraits(.isImage)
    }
}

struct SportBadge: View {
    let discipline: Discipline
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(Theme.sport(discipline.id).opacity(0.22))
            Glyph(name: Theme.icon(discipline), size: size * 0.52)
                .foregroundStyle(Theme.sportInk(discipline.id))
        }
        .frame(width: size, height: size)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = Theme.secondary
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surface2))
    }
}

/*
 * The build, phase by phase: cool at the start, warm at the race. The colour
 * is the plan's own shape — a block says where in the build it sits without a
 * word (his ask for more colour, 2026-10-01).
 */
extension Theme {
    private static let phaseHues: [UInt32] = [
        0x4f87f8,   // the swim's blue — the far start
        0x18a5b8,   // teal
        0x14a37a,   // green
        0x85ce6c,   // the run's green
        0xd8b931,   // amber
        0xff8c1a,   // the strength orange
        0xf0603c,   // warm
        0xef4444    // the race's red
    ]

    /* The i-th of n phases, spread across the whole range however many there are. */
    static func phase(_ i: Int, of n: Int) -> Color {
        guard n > 1 else { return Color(hex: phaseHues[0]) }
        let place = Double(min(max(i, 0), n - 1)) / Double(n - 1) * Double(phaseHues.count - 1)
        let low = Int(place), high = min(low + 1, phaseHues.count - 1)
        let t = place - Double(low)
        let a = phaseHues[low], b = phaseHues[high]
        func part(_ shift: UInt32) -> Double {
            let x = Double((a >> shift) & 0xff) / 255, y = Double((b >> shift) & 0xff) / 255
            return x + (y - x) * t
        }
        return Color(.sRGB, red: part(16), green: part(8), blue: part(0))
    }
}

/* A pill carrying a mark instead of words, for what a phrase said twice over. */
struct MarkPill: View {
    let icon: String
    let spoken: String
    var tint: Color = Theme.secondary
    var body: some View {
        Glyph(name: icon, size: 15)
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Theme.surface2))
            .accessibilityLabel(spoken)
    }
}

enum Dates {
    static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }
    static let long = formatter("EEEEdMMMM")
    static let short = formatter("EEEdMMM")
    static let weekday = formatter("EEEE")

    static func long(_ key: String) -> String { parseDayKey(key).map { long.string(from: $0) } ?? key }
    static func short(_ key: String) -> String { parseDayKey(key).map { short.string(from: $0) } ?? key }
}

/*
 * The wide look (iPad and Mac): the colours of its two own pages and of the
 * side list. Each is a light and a dark pair, so the page reads by day and by
 * night. The Week page is blue because it is where the plan is changed
 * (blue means that, everywhere); the Season page has its own warm amber.
 */
extension Theme {
    static let week = plan
    static let season = Color.dynamic(light: 0xB45309, dark: 0xF59E0B)
    /* Today's column on the week board: a pale green that is a place, not a state. */
    static let todayColumn = Color.dynamic(light: 0xDDEFE6, dark: 0x0F3A30)
    /* A day column that is not today. */
    static let dayColumn = Color.dynamic(light: 0xEBF1F1, dark: 0x132B2B)
    /* The side list's panel; the chosen row's plate is Theme.surface. */
    static let sidePanel = Color.dynamic(light: 0xE9EFEF, dark: 0x0F2828)
}
