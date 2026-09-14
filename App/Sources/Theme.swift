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
    static let plan = Color.dynamic(light: 0x1266C8, dark: 0x3B9EFF)
    static let settings = Color.dynamic(light: 0x5A6B7B, dark: 0x94A3B8)

    static func sportHex(_ id: String) -> UInt32 {
        switch id {
        case "swim": return 0x4f87f8
        case "bike", "brick": return 0xf7cb44
        case "run": return 0x85ce6c
        case "strength": return 0xf2a33a
        case "mobility": return 0x8650fe
        case "race": return 0xef4444
        case "rest": return 0x64748b
        default: return 0x22d3ee
        }
    }

    static func sport(_ id: String) -> Color { Color(hex: sportHex(id)) }

    /* Readable as text: the same hue, darker by day. */
    static func sportInk(_ id: String) -> Color {
        let hex = sportHex(id)
        let dark = Color(hex: hex)
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
        case "rest": return "icon-check"
        default: return "icon-other"
        }
    }
}

struct Glyph: View {
    let name: String
    var size: CGFloat = 22
    var body: some View {
        Image(name).resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size)
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
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surface2))
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
