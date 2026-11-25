/*
 * THE SHELF — for lanes that must remember something that follows him between iPhone, iPad and Mac.
 *   let away = ShelfStore.shared.value(AwayPeriod.self, for: "away")      // nil = nothing there
 *   ShelfStore.shared.set(AwayPeriod(until: "2027-01-06", has: ["pool"]), for: "away")  // false = not kept
 *   ShelfStore.shared.remove(for: "away")                                 // taken away on every device
 *   ShelfStore.shared.keys(prefix: "session/")                            // keys holding a value
 * Views: `@ObservedObject private var shelf = ShelfStore.shared` redraws on every change (`revision`).
 * Values: any small Codable (≤ 64 KB as JSON; dates go as whole milliseconds). Per key the newest set wins.
 * Keys: "favourites", "away", "gear", "race/<what>", "session/<Workout.key>/<fact>" (see shelf-design.md).
 * Never put plan sessions, logs he made in the plan, or anything secret here; the plan stays in PlanBook.
 * Saved on the device first, then met in iCloud as Sync/shelf.json at the plan's next meeting.
 * A Codable type you store must decode older values: give new fields defaults (decodeIfPresent).
 */
import Foundation
import SwiftUI
import WorkoutCore

@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    /* Goes up by one with every change, here or from another device. */
    @Published private(set) var revision = 0
    private(set) var doc = ShelfDoc()
    /* The file here could not be read and could not be put aside: nothing is written over it, nothing travels. */
    private(set) var blocked = false
    /* The file was there but could not be read (not: could not be understood): read again before the next use. */
    private var readFailed = false

    private func readAgainIfNeeded() {
        guard readFailed else { return }
        readFailed = false
        blocked = false
        load()
        if !blocked { revision += 1 }
    }

    /* A change here: iCloud is met a moment later (set by Store, as for the diary). */
    var onChange: (() -> Void)?

    static let fileName = "shelf.json"

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.fileName)
    }

    init() {
        #if DEBUG
        // Pictures and screen tests start with an empty shelf; PlanCloud keeps them away from iCloud.
        if ProcessInfo.processInfo.environment["AMSWS_RESET"] != nil { try? FileManager.default.removeItem(at: fileURL) }
        #endif
        load()
    }

    /*
     * A file that cannot be read never stops the app: it is put aside under a
     * dated name (kept for rescue) and the shelf starts empty.
     */
    private func load() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Round 28 safety: a file that cannot be READ just now (locked device, a passing error) is not
        // a broken file: nothing is moved or written this time, and nothing travels until the next launch.
        guard let data = try? Data(contentsOf: url) else { blocked = true; readFailed = true; return }
        if let read = try? ShelfDoc.decoded(data) {
            doc = read
            return
        }
        let aside = url.deletingLastPathComponent().appendingPathComponent("shelf-unreadable-\(Self.stamp()).json")
        if (try? FileManager.default.moveItem(at: url, to: aside)) == nil { blocked = true }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    /* Saved before it is shown: false when the file could not be written (the change is then not made). */
    private func keep(_ new: ShelfDoc) -> Bool {
        guard !blocked else { return false }
        guard let data = try? new.encoded(), (try? data.write(to: fileURL, options: .atomic)) != nil else { return false }
        doc = new
        revision += 1
        return true
    }

    // MARK: the typed front

    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? { doc.get(type, for: key) }

    func has(_ key: String) -> Bool { doc.has(key) }

    func keys(prefix: String = "") -> [String] { doc.keys(prefix: prefix) }

    /* False when it was not kept (a key that is empty or too long, a value over 64 KB, or no room to save). */
    @discardableResult
    func set<T: Encodable>(_ value: T, for key: String) -> Bool {
        readAgainIfNeeded()
        var new = doc
        do { try new.set(value, for: key, device: Device.id) } catch { tellNotKept(); return false }
        guard keep(new) else { tellNotKept(); return false }
        onChange?()
        return true
    }

    func remove(for key: String) {
        readAgainIfNeeded()
        var new = doc
        new.remove(key, device: Device.id)
        guard new != doc else { return }
        guard keep(new) else { tellNotKept(); return }
        onChange?()
    }

    /*
     * Round 28 safety: a change that was not kept is never lost in silence. One calm
     * message over whatever is on screen (a sheet included); the page itself may say more.
     */
    private var telling = false
    private func tellNotKept() {
        guard !telling else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_RESET"] != nil { return }
        #endif
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let alert = UIAlertController(title: "Not saved",
                                      message: "This change could not be saved on this \(Device.word), so it was not made. Your plan is untouched. Try again in a moment.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.telling = false })
        telling = true
        top.present(alert, animated: true)
    }

    // MARK: iCloud (PlanCloud meets it after the plan, the diary and the pause)

    /* False while nothing may travel: an unreadable file here that could not be put aside. */
    var travels: Bool { readAgainIfNeeded(); return !blocked }

    /* The shelf joined with the other devices', put in place here (joined again with this one, so a tap in between is kept). */
    func takeFromCloud(_ joined: ShelfDoc) {
        let new = ShelfDoc.merge(doc, joined)
        guard new != doc else { return }
        _ = keep(new)
    }
}
