import SwiftUI
import WorkoutCore

/*
 * Settings → Favourite sessions: the list with rename, remove (with a
 * question) and drag to arrange. A grouped Form's onMove does nothing on the
 * Mac, so the rows are plain and each has its own handle and drag: the dragged
 * row follows the finger, the row under it is tinted, and on release the
 * dragged one takes that row's place (the rule is Favourites.move in Core).
 */
struct FavouritesSettingsView: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var frames: [String: CGRect] = [:]
    @State private var dragging: String?
    @State private var dragY: CGFloat = 0
    @State private var over: String?
    @State private var renaming: FavouriteTemplate?
    @State private var newName = ""
    @State private var removing: FavouriteTemplate?
    @State private var problem: String?

    var body: some View {
        let list = FavouritesShelf.list
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                head(list.count)
                if list.isEmpty {
                    Text("No favourites yet. Open a session and tap Save as favourite.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("favourites-empty")
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.id) { n, f in
                        row(f, n, list)
                    }
                    Text("Drag the three lines to put your favourites in order. The first is shown first on the New session page.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("favourites-hint")
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("favourites-problem")
                }
            }
            .padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .onPreferenceChange(FavouriteFrameKey.self) { frames = $0 }
        .background(Theme.plan.opacity(0.05).background(Theme.bg).ignoresSafeArea())
        .navigationTitle("Favourite sessions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("favourites-done")
            }
        }
        .alert("Rename favourite", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let r = renaming {
                    var l = FavouritesShelf.list
                    if Favourites.rename(r.id, to: newName, in: &l) { keep(l) }
                }
                renaming = nil
            }
        }
        .confirmationDialog("Remove this favourite?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let r = removing {
                    var l = FavouritesShelf.list
                    Favourites.remove(r.id, from: &l)
                    keep(l)
                }
                removing = nil
            }
            Button("Keep it", role: .cancel) { removing = nil }
        } message: {
            Text("Sessions already in your plan stay as they are.")
        }
    }

    private func keep(_ l: [FavouriteTemplate]) {
        problem = FavouritesShelf.save(l) ? nil : "The change could not be saved. Nothing was changed."
    }

    private func head(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count == 1 ? "1 favourite" : "\(count) favourites").font(.title2.weight(.bold))
            Text("Kept for the New session page, and on all your devices.").font(.footnote)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.plan))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("favourites-head")
    }

    private func row(_ f: FavouriteTemplate, _ n: Int, _ list: [FavouriteTemplate]) -> some View {
        let d = FavouritesShelf.discipline(f.sport)
        let isDragged = dragging == f.id
        let isTarget = over == f.id
        let sub = [f.minutes.map { formatDuration($0 * 60) }, f.zone.isEmpty ? nil : f.zone, d.label].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return HStack(alignment: .top, spacing: 10) {
            handle()
                .highPriorityGesture(drag(f.id))
                .accessibilityLabel("Drag to move \(f.title)")
                .accessibilityAction(named: "Move up") { shift(f.id, by: -1) }
                .accessibilityAction(named: "Move down") { shift(f.id, by: 1) }
                .accessibilityIdentifier("favourite-handle-\(n)")
            Glyph(name: Theme.icon(d), size: 18).foregroundStyle(Theme.sportInk(d.id)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(f.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(sub).font(.footnote).foregroundStyle(Theme.secondary)
                HStack(spacing: 8) {
                    Button("Rename") { newName = f.title; renaming = f }
                        .settingsButton(tint: Theme.plan)
                        .accessibilityIdentifier("favourite-rename-\(n)")
                    Button("Remove") { removing = f }
                        .settingsButton(tint: Theme.danger)
                        .accessibilityIdentifier("favourite-remove-\(n)")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isTarget ? Theme.plan.opacity(0.18) : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isTarget ? Theme.plan : .clear, lineWidth: 2))
        .background(GeometryReader { p in
            Color.clear.preference(key: FavouriteFrameKey.self, value: [f.id: p.frame(in: .global)])
        })
        .offset(y: isDragged ? dragY : 0)
        .shadow(color: .black.opacity(isDragged ? 0.2 : 0), radius: 6, y: 2)
        .zIndex(isDragged ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("favourite-row-\(n)")
    }

    /* Three hand-drawn lines on a 24-point grid, one 1.9 stroke with round ends. */
    private func handle() -> some View {
        Path { p in
            for y in [7.0, 12.0, 17.0] { p.move(to: CGPoint(x: 5, y: y)); p.addLine(to: CGPoint(x: 19, y: y)) }
        }
        .stroke(Theme.secondary, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
        .frame(width: 24, height: 24)
        .padding(4)
        .contentShape(Rectangle())
    }

    private func drag(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                dragging = id
                dragY = v.translation.height
                over = frames.first { $0.key != id && $0.value.contains(v.location) }?.key
            }
            .onEnded { _ in
                if let target = over {
                    var l = FavouritesShelf.list
                    Favourites.move(id, onto: target, in: &l)
                    keep(l)
                }
                dragging = nil; over = nil; dragY = 0
            }
    }

    /* The same move for VoiceOver's actions: one place up or down. */
    private func shift(_ id: String, by step: Int) {
        var l = FavouritesShelf.list
        guard let i = l.firstIndex(where: { $0.id == id }), l.indices.contains(i + step) else { return }
        Favourites.move(id, onto: l[i + step].id, in: &l)
        keep(l)
    }
}

private struct FavouriteFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
