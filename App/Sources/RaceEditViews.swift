import SwiftUI
import WorkoutCore

/*
 * The race page's editing pages. Every one has Cancel and Save (Escape is
 * Cancel); nothing is kept until Save. Lists he puts in order are dragged by a
 * handle on each row — never arrows — and the drag is our own (a handle and a
 * DragGesture) because a grouped Form's onMove does nothing on the Mac.
 */

// MARK: - dragging a row into place

/* Three short lines: hold and drag. It is drawn here, not an icon of the library. */
struct DragHandle: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().fill(Theme.secondary).frame(width: 16, height: 2)
            }
        }
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
}

private struct RowFrames: PreferenceKey {
    static var defaultValue: [AnyHashable: CGRect] = [:]
    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/*
 * Rows with a handle at the left. While a handle is dragged the row follows the
 * pointer and the row under it is tinted; letting go puts the dragged row in
 * that row's place (RaceOrder.move, tested).
 */
struct ReorderColumn<Item: Identifiable, Row: View>: View where Item.ID: Hashable {
    @Binding var items: [Item]
    /* Number of the first row on the whole page, for identifiers. */
    var firstNumber = 0
    var handleID = "race-check-handle"
    let tint: Color
    @ViewBuilder let row: (Binding<Item>, Int) -> Row

    @State private var dragging: Item.ID?
    @State private var offset: CGFloat = 0
    @State private var target: Item.ID?
    @State private var frames: [AnyHashable: CGRect] = [:]
    @State private var space = "reorder-" + UUID().uuidString

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 4) {
                    DragHandle()
                        .gesture(drag(item.id))
                        .accessibilityLabel("Move \(index + 1) of \(items.count)")
                        .accessibilityIdentifier("\(handleID)-\(firstNumber + index)")
                    row($items[index], firstNumber + index)
                }
                .padding(.trailing, 8)
                .background(GeometryReader { g in
                    Color.clear.preference(key: RowFrames.self, value: [AnyHashable(item.id): g.frame(in: .named(space))])
                })
                .background(target == item.id && dragging != item.id ? tint.opacity(0.35) : Color.clear)
                .offset(y: dragging == item.id ? offset : 0)
                .zIndex(dragging == item.id ? 1 : 0)
                .shadow(color: dragging == item.id ? .black.opacity(0.15) : .clear, radius: 4)
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(RowFrames.self) { frames = $0 }
    }

    private func drag(_ id: Item.ID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { v in
                dragging = id
                offset = v.translation.height
                target = items.map(\.id).first { other in
                    other != id && (frames[AnyHashable(other)].map { v.location.y >= $0.minY && v.location.y <= $0.maxY } ?? false)
                }
            }
            .onEnded { _ in
                if let t = target { withAnimation(.easeInOut(duration: 0.15)) { items = RaceOrder.move(items, id, onto: t) } }
                dragging = nil; target = nil; offset = 0
            }
    }
}

// MARK: - a page with Cancel and Save

private struct EditFrame<Content: View>: View {
    let title: String
    let idPrefix: String
    let canSave: Bool
    let save: () -> Bool
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                    if failed {
                        Text("Not saved. Try again.").font(.footnote).foregroundStyle(Theme.secondary)
                            .accessibilityIdentifier(idPrefix + "-failed")
                    }
                }
                .padding(14)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(RaceLook.ground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(idPrefix + "-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if save() { dismiss() } else { failed = true } }
                        .disabled(!canSave)
                        .accessibilityIdentifier(idPrefix + "-save")
                }
            }
        }
        .tint(Theme.plan)
    }
}

private func field(_ label: String, text: Binding<String>, prompt: String, id: String,
                   keyboard: UIKeyboardType = .default) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(RaceLook.ink)
        TextField(prompt, text: text)
            .keyboardType(keyboard)
            .textFieldStyle(.plain)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            .accessibilityIdentifier(id)
    }
}

// MARK: - the five times

struct RacePacingEdit: View {
    let race: RaceInfo
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var times: [RaceLeg: String] = [:]
    @State private var notes: [RaceLeg: String] = [:]
    @State private var loaded = false

    private func bind<K: Hashable>(_ dict: Binding<[K: String]>, _ key: K) -> Binding<String> {
        Binding(get: { dict.wrappedValue[key] ?? "" }, set: { dict.wrappedValue[key] = $0 })
    }

    /* The legs whose box holds something that is not a time. */
    private var unreadable: [RaceLeg] {
        RaceLeg.allCases.filter {
            let t = (times[$0] ?? "").trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && RacePacing.parse(t, changeOver: $0.isChangeOver) == nil
        }
    }

    var body: some View {
        EditFrame(title: "Your times", idPrefix: "race-pacing", canSave: unreadable.isEmpty, save: save) {
            Text("Type the time you plan for each part. Legs as hours and minutes (1:10), change-overs as minutes and seconds (4:30). Leave a box empty to leave it out.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            ForEach(RaceLeg.allCases, id: \.self) { leg in
                VStack(alignment: .leading, spacing: 6) {
                    field(leg.word, text: bind($times, leg),
                          prompt: leg.isChangeOver ? "e.g. 4:30" : "e.g. 1:10",
                          id: "race-pacing-" + leg.rawValue, keyboard: .numbersAndPunctuation)
                    if !leg.isChangeOver {
                        TextField("How you will hold it, e.g. pulse Z2, power 150–160 W, by feel", text: bind($notes, leg))
                            .textFieldStyle(.plain).font(.subheadline)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                            .accessibilityIdentifier("race-pacing-note-" + leg.rawValue)
                    }
                    if unreadable.contains(leg) {
                        Text("That is not a time yet.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
            if let f = preview {
                Text("Planned finish \(formatDuration(Double(f)))").font(.headline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("race-pacing-finish")
            }
        }
        .onAppear(perform: load)
    }

    private var preview: Int? {
        var p = RacePacing()
        for leg in RaceLeg.allCases { p.set(leg, RacePacing.parse(times[leg] ?? "", changeOver: leg.isChangeOver)) }
        return p.finish?.seconds
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let p = shelf.value(RacePacing.self, for: RaceKeys.pacing(race.day)) ?? RacePacing()
        for leg in RaceLeg.allCases {
            if let s = p.seconds(leg) { times[leg] = Self.typed(s, changeOver: leg.isChangeOver) }
            notes[leg] = p.note(leg)
        }
    }

    /* A time as it is typed back into the box: 4200 -> "1:10", 270 -> "4:30". */
    static func typed(_ s: Int, changeOver: Bool) -> String {
        if changeOver { return String(format: "%d:%02d", s / 60, s % 60) }
        if s % 60 != 0 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    private func save() -> Bool {
        var p = RacePacing()
        for leg in RaceLeg.allCases {
            p.set(leg, RacePacing.parse(times[leg] ?? "", changeOver: leg.isChangeOver))
            p.setNote(leg, notes[leg] ?? "")
        }
        if p.isEmpty { shelf.remove(for: RaceKeys.pacing(race.day)); return true }
        return shelf.set(p, for: RaceKeys.pacing(race.day))
    }
}

// MARK: - fuel

/* One fuel row: where, when, what, how many grams. Cancel and Save. */
struct RaceFuelRowEditor: View {
    @State var row: RaceFuelRow
    let isNew: Bool
    let onSave: (RaceFuelRow) -> Void
    @State private var grams = ""

    init(row: RaceFuelRow, isNew: Bool, onSave: @escaping (RaceFuelRow) -> Void) {
        _row = State(initialValue: row)
        _grams = State(initialValue: row.carbs > 0 ? String(row.carbs) : "")
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        EditFrame(title: isNew ? "New fuel row" : "Fuel row", idPrefix: "race-fuel-row", canSave: true, save: {
            row.carbs = Int(grams.trimmingCharacters(in: .whitespaces)) ?? 0
            onSave(row)
            return true
        }) {
            Picker("Part", selection: $row.leg) {
                ForEach(RaceFuelLeg.allCases, id: \.self) { Text($0.word).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("race-fuel-leg")
            field("When", text: $row.when, prompt: "e.g. every 20 min", id: "race-fuel-when")
            field("What", text: $row.what, prompt: "e.g. 1 gel", id: "race-fuel-what")
            field("Carbohydrate, grams in all", text: $grams, prompt: "e.g. 198", id: "race-fuel-grams", keyboard: .numberPad)
            Text("The grams for this row over the whole part, as you will take them.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

/* All the rows: tap one to change it, drag a handle to put them in order, remove one. */
struct RaceFuelEdit: View {
    let race: RaceInfo
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var rows: [RaceFuelRow] = []
    @State private var loaded = false
    @State private var changing: RaceFuelRow?

    var body: some View {
        EditFrame(title: "Fuel plan", idPrefix: "race-fuel", canSave: true, save: {
            if rows.isEmpty { shelf.remove(for: RaceKeys.fuel(race.day)); return true }
            return shelf.set(RaceFuel(rows: rows), for: RaceKeys.fuel(race.day))
        }) {
            Text("Hold the three lines and drag a row to where it belongs. Tap a row to change it.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            ReorderColumn(items: $rows, handleID: "race-fuel-handle", tint: Theme.plan) { $row, n in
                HStack(spacing: 8) {
                    Button { changing = row } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(row.carbs) g \(row.what)").font(.body).foregroundStyle(Theme.text)
                            Text(row.when.isEmpty ? row.leg.word : row.leg.word + " · " + row.when)
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("race-fuel-change-\(n)")
                    Button("Remove") { rows.removeAll { $0.id == row.id } }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("race-fuel-remove-\(n)")
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RaceLook.tile))
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            rows = (shelf.value(RaceFuel.self, for: RaceKeys.fuel(race.day)) ?? RaceFuel()).rows
        }
        .sheet(item: $changing) { r in
            RaceFuelRowEditor(row: r, isNew: false) { changed in
                if let i = rows.firstIndex(where: { $0.id == changed.id }) { rows[i] = changed }
            }
        }
    }
}

// MARK: - kit checklist

/* The list as he wants it: rename, remove, add, and drag within each group. */
struct RaceChecklistEdit: View {
    let race: RaceInfo
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var list = RaceChecklist.starting
    @State private var loaded = false

    private func group(_ g: RaceKitGroup) -> Binding<[RaceKitItem]> {
        Binding(get: { list.items.filter { $0.group == g } },
                set: { new in list.items = list.items.filter { $0.group != g } + new })
    }

    private func firstNumber(_ g: RaceKitGroup) -> Int {
        RaceKitGroup.allCases.prefix { $0 != g }.reduce(0) { n, earlier in n + list.items.filter { $0.group == earlier }.count }
    }

    var body: some View {
        EditFrame(title: "Kit checklist", idPrefix: "race-check", canSave: true, save: {
            var kept = list
            kept.items.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            return shelf.set(kept, for: RaceKeys.checklist(race.day))
        }) {
            Text("Hold the three lines and drag an item to where it belongs. Rename it in its box.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            ForEach(RaceKitGroup.allCases, id: \.self) { g in
                VStack(alignment: .leading, spacing: 0) {
                    Text(g.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(RaceLook.ink)
                        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
                    ReorderColumn(items: group(g), firstNumber: firstNumber(g), tint: Theme.plan) { $item, n in
                        HStack(spacing: 8) {
                            TextField("Item", text: $item.name)
                                .textFieldStyle(.plain).padding(.vertical, 6)
                                .accessibilityIdentifier("race-check-name-\(n)")
                            Button("Remove") { list.items.removeAll { $0.id == item.id } }
                                .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.danger)
                                .accessibilityIdentifier("race-check-remove-\(n)")
                        }
                    }
                    Button("Add to \(g.word.lowercased())") {
                        list.items.append(RaceKitItem(group: g, name: ""))
                    }
                    .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Theme.plan)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .accessibilityIdentifier("race-check-add-" + g.rawValue)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RaceLook.tile))
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            list = shelf.value(RaceChecklist.self, for: RaceKeys.checklist(race.day)) ?? .starting
        }
    }
}
