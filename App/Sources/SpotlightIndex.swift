import SwiftUI
import Combine
import CoreSpotlight
import UniformTypeIdentifiers
import WorkoutCore

/*
 * Round 28, "system": the plan in the system's search, and the links that open it.
 *
 * Spotlight holds the next 14 days' sessions and the last 14 done ones, each as
 * "Tue 1 Dec · Swim · 40 min". It is rebuilt when the plan changes and emptied
 * when the plan is gone or moves house (Go back to Excel): the session keys of
 * the two homes differ, so an old result would open nothing. Nothing here ever
 * writes to the plan.
 */

extension Store {
    /* Every session as the system parts see it. */
    var briefs: [SessionBrief] {
        guard let mapping else { return [] }
        return displayed.map { SessionBrief($0, mapping) }
    }
}

/*
 * One Store for the whole process: the app's own screens and the Siri intents use the same one, so an intent
 * that wakes the app in the background loads the plan exactly as the launch does, and a later opening of the
 * screens never makes a second copy that could write the same waiting log.
 */
@MainActor
enum IntentStore {
    static let shared = Store()
}

@MainActor
final class SpotlightIndex {
    static let shared = SpotlightIndex()
    private let domain = "com.schabbauer.amsworkoutsync.session"
    private var last = ""

    func refresh(_ store: Store) {
        if store.phase == .empty { removeAll(); return }
        guard store.view != nil else { return }
        let entries = SystemWords.spotlightEntries(store.briefs, today: store.today)
        let signature = store.home.rawValue + "\n" + entries.map { "\($0.key)|\($0.title)|\($0.detail)" }.joined(separator: "\n")
        guard signature != last else { return }
        last = signature
        let index = CSSearchableIndex.default()
        let domain = self.domain
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            let items = entries.map { entry -> CSSearchableItem in
                let set = CSSearchableItemAttributeSet(contentType: UTType.content)
                set.title = entry.title
                set.contentDescription = entry.detail
                set.keywords = entry.keywords
                let item = CSSearchableItem(uniqueIdentifier: entry.key, domainIdentifier: domain, attributeSet: set)
                item.expirationDate = Date().addingTimeInterval(60 * 60 * 24 * 30)
                return item
            }
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { _ in }
        }
    }

    func removeAll() {
        guard last != "" else { return }
        last = ""
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}

/* Where a link or a Spotlight result goes. */
enum SystemTarget {
    case today
    case session(String)
    /* 2.11: a page by its name in `SystemLink.pages` (plan, sessions, body, progress, settings). */
    case page(String)
}

/*
 * The hook the two roots (phone and wide) share: amsworkoutsync://today, amsworkoutsync://session/<key>, a
 * Spotlight result, and the keeping of Spotlight up to date as the plan changes.
 */
private struct SystemLinks: ViewModifier {
    @EnvironmentObject var store: Store
    let open: (SystemTarget) -> Void

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if url.host == "today" { open(.today) }
                else if let key = SystemLink.sessionKey(host: url.host, path: url.path) { open(.session(key)) }
                else if let page = SystemLink.page(host: url.host) { open(.page(page)) }
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let key = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String { open(.session(key)) }
            }
            .modifier(TodayNoteHook(open: open))
            .onAppear { SpotlightIndex.shared.refresh(store) }
            .onReceive(store.objectWillChange.debounce(for: .seconds(1.5), scheduler: RunLoop.main)) { _ in
                SpotlightIndex.shared.refresh(store)
            }
    }
}

extension View {
    func systemLinks(open: @escaping (SystemTarget) -> Void) -> some View {
        modifier(SystemLinks(open: open))
    }
}
