#if DEBUG
import UIKit

/* Picture helper: AMSWS_TODAY_OFFSET=<points> scrolls the page that is on screen down by that much. */
enum DebugScrollOffset {
    static func applyFromEnvironment() {
        guard let raw = ProcessInfo.processInfo.environment["AMSWS_TODAY_OFFSET"], let y = Double(raw) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            guard let root = windows.first(where: \.isKeyWindow) else { return }
            if let sv = firstScroll(in: root) { sv.setContentOffset(CGPoint(x: 0, y: y), animated: false) }
        }
    }
    private static func firstScroll(in v: UIView) -> UIScrollView? {
        if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height { return s }
        for c in v.subviews { if let s = firstScroll(in: c) { return s } }
        return nil
    }
}
#endif
