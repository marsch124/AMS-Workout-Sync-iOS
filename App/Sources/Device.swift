import UIKit

/*
 * Which kind of device this is. One build serves the iPhone, the iPad and the
 * Mac ("Designed for iPad"), and a few things belong to one of them only: the
 * iPhone keeps the Training calendar, Dropbox and Apple Health; the iPad and
 * the Mac take the plan from iCloud.
 *
 * The rank orders marks that carry no time at all (PlanBook.baselined): Mac 1,
 * iPad 2, iPhone 3 — the iPhone, where the plan was first logged, counts most.
 */
enum Device {
    enum Kind: String, Codable { case iPhone, iPad, Mac }

    /* DEBUG: AMSWS_DEVICE=phone|ipad|mac fakes the kind, for screens and tests on any simulator. */
    private static let faked: Kind? = {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["AMSWS_DEVICE"]?.lowercased() {
        case "phone", "iphone": return .iPhone
        case "ipad", "pad": return .iPad
        case "mac": return .Mac
        default: return nil
        }
        #else
        return nil
        #endif
    }()

    static let kind: Kind = {
        if let faked { return faked }
        if ProcessInfo.processInfo.isiOSAppOnMac { return .Mac }
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }()

    static var isPhone: Bool { kind == .iPhone }
    static var isPad: Bool { kind == .iPad }
    static var isMac: Bool { kind == .Mac }

    static var rank: Int {
        switch kind {
        case .Mac: return 1
        case .iPad: return 2
        case .iPhone: return 3
        }
    }

    /* "iPhone", "iPad", "Mac" — the word the screens use. */
    static var word: String { kind.rawValue }

    /* This installation's own name for its file in iCloud (devices/<id>.json); made once. */
    static let id: String = {
        let key = "sync.deviceID"
        if let known = UserDefaults.standard.string(forKey: key) { return known }
        let made = UUID().uuidString
        UserDefaults.standard.set(made, forKey: key)
        return made
    }()
}
