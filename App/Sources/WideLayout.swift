import SwiftUI

/*
 * The wide look (iPad, and the iPad app on the Mac). Everything wide is behind
 * `horizontalSizeClass == .regular`; the phone never takes these paths.
 */

/* Keeps a page's content in a comfortable reading column on a wide screen, centred; does nothing on the phone. */
struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.wideReadableLimit) private var override
    var limit: CGFloat

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.frame(maxWidth: override ?? limit).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /* At most `limit` points wide and centred when the window is wide; unchanged on the phone. */
    func readableWidth(_ limit: CGFloat = 680) -> some View { modifier(ReadableWidth(limit: limit)) }
}

/* A page's own reading width, set from the side list's root for the page as a whole (the Sessions page: 760 on a wide screen). */
private struct WideReadableLimitKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var wideReadableLimit: CGFloat? {
        get { self[WideReadableLimitKey.self] }
        set { self[WideReadableLimitKey.self] = newValue }
    }
}
