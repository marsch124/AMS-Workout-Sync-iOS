import SwiftUI
import WorkoutCore

/*
 * Favourite sessions, the screens that sit on a session's page and on the
 * add-session page. The list lives on the shelf (key "favourites"), so it
 * follows him between iPhone, iPad and the Mac. The rules are in Core.
 */
enum FavouritesShelf {
    @MainActor static var list: [FavouriteTemplate] {
        ShelfStore.shared.value([FavouriteTemplate].self, for: Favourites.shelfKey) ?? []
    }

    @MainActor @discardableResult
    static func save(_ list: [FavouriteTemplate]) -> Bool {
        ShelfStore.shared.set(list, for: Favourites.shelfKey)
    }

    static func discipline(_ sport: String) -> Discipline {
        SessionEditView.sports.first { $0.id == sport } ?? Disciplines.other
    }
}

/*
 * On a session's page, under its title: "Save as favourite" (it becomes
 * "In your favourites" once saved) and, on a session still in the plan, "Repeat…".
 */
struct SessionFavouriteRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    let key: String
    @State private var repeating = false
    @State private var full = false

    var body: some View {
        if let d = store.draft(of: key) {
            let isFavourite = Favourites.isFavourite(sport: d.sport, title: d.title, in: FavouritesShelf.list)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if isFavourite {
                        Text("In your favourites").font(.caption.weight(.semibold)).foregroundStyle(Theme.plan)
                            .accessibilityIdentifier("favourite-save")
                    } else {
                        Button("Save as favourite") { save(d) }
                            .settingsButton(tint: Theme.plan)
                            .accessibilityIdentifier("favourite-save")
                    }
                    if store.canChangePlan {
                        Button("Repeat\u{2026}") { repeating = true }
                            .settingsButton(tint: Theme.plan)
                            .accessibilityIdentifier("session-repeat")
                    }
                    Spacer(minLength: 0)
                }
                if full {
                    Text("Your favourites are full (\(Favourites.limit)). Remove one in Settings first.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("favourite-full")
                }
            }
            .sheet(isPresented: $repeating) {
                RepeatSheet(key: key).environmentObject(store)
            }
        }
    }

    private func save(_ d: SessionDraft) {
        var list = FavouritesShelf.list
        guard Favourites.add(Favourites.template(from: d), to: &list), FavouritesShelf.save(list) else {
            full = list.count >= Favourites.limit
            return
        }
        full = false
    }
}

/* On the add-session page, at the top: each favourite as a small tile; a tap fills the form. */
struct FavouritesBlock: View {
    @ObservedObject private var shelf = ShelfStore.shared
    var onPick: (FavouriteTemplate) -> Void

    var body: some View {
        let list = FavouritesShelf.list
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your favourites").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.plan)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { n, f in
                            Button { onPick(f) } label: { tile(f) }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("favourite-tile-\(n)")
                        }
                    }
                }
                Text("Tap one to fill the page. You can still change everything before Save.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("favourites-block")
        }
    }

    private func tile(_ f: FavouriteTemplate) -> some View {
        let d = FavouritesShelf.discipline(f.sport)
        return HStack(spacing: 8) {
            Glyph(name: Theme.icon(d), size: 18).foregroundStyle(Theme.sportInk(d.id))
            VStack(alignment: .leading, spacing: 1) {
                Text(f.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(f.minutes.map { formatDuration($0 * 60) } ?? d.label)
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: 190, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.plan.opacity(0.5), lineWidth: 1)))
    }
}

#if DEBUG
/* Picture switches: AMSWS_FAVOURITES_PAGE, AMSWS_ADD_WITH_FAVOURITES, AMSWS_REPEAT. Invented favourites only. */
struct FavouritesDebugScreens: View {
    @EnvironmentObject var store: Store
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor static func seed() {
        guard FavouritesShelf.list.isEmpty else { return }
        FavouritesShelf.save([
            FavouriteTemplate(id: "demo-1", sport: "bike", title: "Aerobic ride, steady Z2", purpose: "Steady, no efforts", minutes: 60, zone: "Z2"),
            FavouriteTemplate(id: "demo-2", sport: "run", title: "Easy run", purpose: "Conversational", minutes: 40, zone: "Z1\u{2013}Z2"),
            FavouriteTemplate(id: "demo-3", sport: "swim", title: "Drills and 6 x 200", purpose: "Warm-up, drills, 6 x 200 steady", minutes: 45, zone: "Z2"),
        ])
    }

    /* A new session on a day that, a week or two on, meets a session the plan already has: shows a "left out" line. */
    private var addDraft: SessionDraft {
        let later = (store.book?.sessions ?? []).filter { $0.dayKey > store.today && ["bike", "run", "swim"].contains($0.discipline.id) }
            .sorted { $0.dayKey < $1.dayKey }
        if let s = later.dropFirst(3).first ?? later.first {
            return SessionDraft(dayKey: PlanView.addDays(s.dayKey, -14), sport: s.discipline.id, title: s.title, minutes: 45, intensity: "Z2")
        }
        return SessionDraft(dayKey: PlanView.addDays(store.today, 1), sport: "run")
    }

    var body: some View {
        if env["AMSWS_FAVOURITES_PAGE"] != nil {
            NavigationStack { FavouritesSettingsView() }.onAppear { Self.seed() }
        }
        if env["AMSWS_ADD_WITH_FAVOURITES"] != nil || env["AMSWS_REPEAT"] != nil {
            SessionEditView(key: nil, draft: env["AMSWS_REPEAT"] != nil ? addDraft : SessionDraft(dayKey: PlanView.addDays(store.today, 1), sport: "run"))
                .environmentObject(store)
                .onAppear { Self.seed() }
        }
    }
}
#endif
