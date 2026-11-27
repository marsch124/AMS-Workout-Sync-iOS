import SwiftUI
import UIKit

/*
 * Round 30: a head card is filled with its part's colour and carries white words. The shared accents are light at night
 * (a pale blue, a pale amber, a pale lavender), and white words on those cannot be read at a glance. `deepHead` is the same
 * colour darkened just enough (day and night) that white words reach a clear contrast; a colour that is already deep stays
 * as it is.
 */
extension Color {
    var deepHead: Color {
        Color(UIColor { traits in
            let c = UIColor(self).resolvedColor(with: traits)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            var k: CGFloat = 1
            for _ in 0..<40 {
                let l = 0.2126 * lin(r * k) + 0.7152 * lin(g * k) + 0.0722 * lin(b * k)
                if l <= 0.12 { break }
                k -= 0.03
            }
            return UIColor(red: r * k, green: g * k, blue: b * k, alpha: 1)
        })
    }
}

extension Color {
    /// A neutral field/card surface for the round-30 pages (the shared night surface is green-blue, which he does not want).
    static let neutralSurface = Color.dynamic(light: 0xFFFFFF, dark: 0x26262B)
}
