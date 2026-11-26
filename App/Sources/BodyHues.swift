import SwiftUI
import WorkoutCore

/*
 * 2.10: a colour of its own for every card on the Body page (his ask, 26 November 2026: "add a multitude of colours …
 * a lot of different colours on this page. I hate this boring colour"). A card's colour paints its name, its bars and
 * marks and, much paler, its ground; the figures stay in the text colour so they read at a glance. The colour only tells
 * the cards apart and means nothing else. Raspberry stays Body's own: Body Battery, the page's headings, the range
 * buttons and Share. No card uses the green of today/done or the red of a warning.
 *
 * Sleep and Sleep debt share indigo (both are sleep). The grounds are the colour at 13 % on white by day and at 30 % on
 * near-black by night.
 */
struct BodyHue: Equatable {
    let accent: Color
    let tile: Color

    static let body = BodyHue(accent: Theme.body, tile: Theme.bodyTile)

    static let sleep = BodyHue(accent: .dynamic(light: 0x4F46E5, dark: 0xA5B4FC), tile: .dynamic(light: 0xE8E7FC, dark: 0x282557))
    static let hrv = BodyHue(accent: .dynamic(light: 0x0D9488, dark: 0x5EEAD4), tile: .dynamic(light: 0xE0F1F0, dark: 0x143C3B))
    static let resting = BodyHue(accent: .dynamic(light: 0xC026D3, dark: 0xF0ABFC), tile: .dynamic(light: 0xF7E3F9, dark: 0x4A1C52))
    static let stress = BodyHue(accent: .dynamic(light: 0xD97706, dark: 0xFCD34D), tile: .dynamic(light: 0xFAEDDF, dark: 0x513414))
    static let steps = BodyHue(accent: .dynamic(light: 0x65A30D, dark: 0xBEF264), tile: .dynamic(light: 0xEBF3E0, dark: 0x2E4116))
    static let intensity = BodyHue(accent: .dynamic(light: 0x2563EB, dark: 0x93C5FD), tile: .dynamic(light: 0xE3EBFC, dark: 0x1B2E59))
    static let load = BodyHue(accent: .dynamic(light: 0x7C3AED, dark: 0xC4B5FD), tile: .dynamic(light: 0xEEE5FD, dark: 0x352259))
    static let fitness = BodyHue(accent: .dynamic(light: 0x0891B2, dark: 0x67E8F9), tile: .dynamic(light: 0xDFF1F5, dark: 0x123C48))
    static let gym = BodyHue(accent: .dynamic(light: 0xEA580C, dark: 0xFDBA74), tile: .dynamic(light: 0xFCE9DF, dark: 0x562A16))
    static let workouts = BodyHue(accent: .dynamic(light: 0xDB2777, dark: 0xF9A8D4), tile: .dynamic(light: 0xFAE3ED, dark: 0x521C36))
    static let weight = BodyHue(accent: .dynamic(light: 0x9333EA, dark: 0xD8B4FE), tile: .dynamic(light: 0xF1E4FC, dark: 0x3C1F58))
    static let energy = BodyHue(accent: .dynamic(light: 0xCA8A04, dark: 0xFDE047), tile: .dynamic(light: 0xF8F0DE, dark: 0x4D3A13))
    static let water = BodyHue(accent: .dynamic(light: 0x0EA5E9, dark: 0x7DD3FC), tile: .dynamic(light: 0xE0F3FC, dark: 0x144258))

    /* The six tiles under Body Battery. */
    static func of(_ i: BodyPage.Instrument) -> BodyHue {
        switch i {
        case .sleep: return .sleep
        case .hrv: return .hrv
        case .resting: return .resting
        case .stress: return .stress
        case .steps: return .steps
        case .intensity: return .intensity
        }
    }
}

private struct BodyHueKey: EnvironmentKey {
    static let defaultValue = BodyHue.body
}

extension EnvironmentValues {
    /* The colour of the card being drawn; Body's raspberry where no card set one. */
    var bodyHue: BodyHue {
        get { self[BodyHueKey.self] }
        set { self[BodyHueKey.self] = newValue }
    }
}

extension View {
    /* Paints this card (and the page it opens) in its own colour. */
    func bodyHue(_ hue: BodyHue) -> some View { environment(\.bodyHue, hue) }
}
