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
    /* The scroll view that is really on screen (a tab that is not showing keeps its own, hidden). */
    private static func firstScroll(in v: UIView) -> UIScrollView? {
        var all: [UIScrollView] = []
        func walk(_ x: UIView) {
            if x.isHidden || x.alpha < 0.05 { return }
            if let s = x as? UIScrollView, s.contentSize.height > s.bounds.height, s.window != nil { all.append(s) }
            x.subviews.forEach(walk)
        }
        walk(v)
        return all.filter { s in
            guard let w = s.window else { return false }
            let r = s.convert(s.bounds, to: w).intersection(w.bounds)
            return r.height > w.bounds.height * 0.5 && r.width > w.bounds.width * 0.5
        }.last
    }
}
#endif
