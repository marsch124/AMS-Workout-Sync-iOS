import SwiftUI
import WorkoutCore

/*
 * Settings › My week shape (round 30, pick 5): "Say once 'long ride Saturday,
 * swim Mon + Wed'; every future week is laid out that way."
 *
 * The page holds its changes until Save (Cancel leaves the shape as it was);
 * the shape lives on the shelf under "weekshape", so it follows him between
 * iPhone, iPad and Mac. The plan maker uses it. "Lay out my coming weeks this
 * way" shows first what would move; nothing moves until "Take it", and the
 * whole lay-out is one entry with one Undo.
 */

/* Colours of this lane's cards: each card its own, never green, red or teal. */
struct LaneHue: Equatable {
    let accent: Color
    let tile: Color

    static let indigo = LaneHue(accent: .dynamic(light: 0x4F46E5, dark: 0xA5B4FC), tile: .dynamic(light: 0xE8E7FC, dark: 0x282557))
    static let gold = LaneHue(accent: .dynamic(light: 0xA16207, dark: 0xFDE047), tile: .dynamic(light: 0xF8F0DE, dark: 0x4D3A13))
    static let magenta = LaneHue(accent: .dynamic(light: 0xC026D3, dark: 0xF0ABFC), tile: .dynamic(light: 0xF7E3F9, dark: 0x4A1C52))
    static let rust = LaneHue(accent: .dynamic(light: 0xC2410C, dark: 0xFDBA74), tile: .dynamic(light: 0xFCE9DF, dark: 0x562A16))
    static let slate = LaneHue(accent: Theme.settings, tile: .dynamic(light: 0xE6EAEF, dark: 0x26313D))
}

enum WeekShapeShelf {
    /* The saved shape; nil when he never saved one. */
    @MainActor static var saved: WeekShape? { ShelfStore.shared.value(WeekShape.self, for: WeekShape.shelfKey)?.normalised }

    /* The shape to use: his saved one, else the one his plan already has, else an ordinary week. */
    @MainActor static func current(_ store: Store) -> WeekShape {
        if let saved { return saved }
        if let book = store.book {
            return WeekShape.learned(from: book.sessions.filter { $0.dayKey > store.today }.isEmpty ? book.sessions
                                     : book.sessions.filter { $0.dayKey > store.today }, mapping: book.mapping)
        }
        return .standard
    }

    #if DEBUG
    /* Picture switch only: a shape that differs from the invented plan, so the lay-out page has moves to show. */
    static let pictureShape = WeekShape(days: [["swim", "mobility"], ["bike", "strength"], ["run", "mobility"], ["swim", "run", "strength"],
                                               ["bike", "mobility"], ["mobility"], ["bike", "run"]],
                                        longRide: 6, longRun: 3, rest: 5).normalised
    #endif

    static func summary(_ s: WeekShape) -> String {
        "Long ride \(WeekShape.weekdayShort[s.longRide]) \u{00B7} long run \(WeekShape.weekdayShort[s.longRun]) \u{00B7} rest \(WeekShape.weekdayShort[s.rest])"
    }
}

/* The row under Settings › Your plan. */
struct WeekShapeSettingsRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        NavigationLink { WeekShapePage() } label: {
            SettingsRow(title: "My week shape",
                        sub: (WeekShapeShelf.saved == nil ? "Not set yet \u{2014} " : "") + WeekShapeShelf.summary(WeekShapeShelf.current(store)),
                        chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ws-row")
    }
}

// MARK: - the page

struct WeekShapePage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shape: WeekShape = .standard
    @State private var loaded = false
    @State private var savedOnce = false
    @State private var notKept = false

    private var stored: WeekShape { WeekShapeShelf.current(store) }
    private var unsaved: Bool { loaded && (shape.normalised != stored || WeekShapeShelf.saved == nil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head
                daysCard
                longDaysCard
                if !shape.normalised.problems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(shape.normalised.problems, id: \.self) { Text($0) }
                    }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LaneHue.gold.tile))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ws-problems")
                }
                if notKept {
                    Text("The shape could not be saved on this \(Device.word). Nothing was changed.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                }
                layOutCard
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(LaneHue.slate.tile.opacity(0.45).ignoresSafeArea())
        .navigationTitle("My week shape")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(savedOnce && !unsaved ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("ws-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!unsaved || !shape.normalised.problems.isEmpty)
                    .accessibilityIdentifier("ws-save")
            }
        }
        .onAppear {
            guard !loaded else { return }
            shape = stored
            loaded = true
        }
    }

    private func save() {
        let s = shape.normalised
        guard s.problems.isEmpty else { return }
        if ShelfStore.shared.set(s, for: WeekShape.shelfKey) {
            shape = s
            savedOnce = true
            notKept = false
        } else {
            notKept = true
        }
    }

    /* Filled in Settings' slate: what the shape is, in one line. */
    private var head: some View {
        let s = shape.normalised
        return VStack(alignment: .leading, spacing: 3) {
            Text("MY WEEK SHAPE").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            Text(WeekShapeShelf.summary(s)).font(.title3.weight(.bold))
                .accessibilityIdentifier("ws-summary")
            Text("Which sports fit each day. The plan maker builds new plans this way, and your coming weeks can be laid out this way.")
                .font(.footnote).opacity(0.92).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.settings.deepHead))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ws-page")
    }

    private var daysCard: some View {
        let hue = LaneHue.indigo
        return VStack(alignment: .leading, spacing: 8) {
            Text("THE DAYS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            Text("Tap a sport to say it fits that day. The rest day holds mobility at most.")
                .font(.caption).foregroundStyle(Theme.secondary)
            ForEach(0..<7, id: \.self) { d in dayRow(d, hue: hue) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }

    private func dayRow(_ d: Int, hue: LaneHue) -> some View {
        let isRest = d == shape.rest
        let chips = ForEach(WeekShape.sports, id: \.self) { sport in
            chip(d, sport, hue: hue, off: isRest && sport != "mobility")
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(WeekShape.weekdayNames[d]).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if isRest { Text("rest day").font(.caption).foregroundStyle(Theme.secondary) }
                if d == shape.longRide { Text("long ride").font(.caption).foregroundStyle(Theme.secondary) }
                if d == shape.longRun { Text("long run").font(.caption).foregroundStyle(Theme.secondary) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { chips }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) { ForEach(WeekShape.sports.prefix(3), id: \.self) { chip(d, $0, hue: hue, off: isRest && $0 != "mobility") } }
                    HStack(spacing: 5) { ForEach(WeekShape.sports.suffix(2), id: \.self) { chip(d, $0, hue: hue, off: isRest && $0 != "mobility") } }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ws-day-\(d)")
    }

    /* A word that is on (filled in the card's colour, white words) or off (outlined). Never a tick: the tick means done. */
    private func chip(_ d: Int, _ sport: String, hue: LaneHue, off: Bool) -> some View {
        let on = shape.days[d].contains(sport) && !off
        return Button {
            var days = shape.days
            if days[d].contains(sport) { days[d].removeAll { $0 == sport } } else { days[d].append(sport) }
            shape.days = days.map { list in WeekShape.sports.filter { list.contains($0) } }
        } label: {
            Text(Disciplines.five.first { $0.id == sport }?.label ?? sport)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.white : (off ? Theme.secondary.opacity(0.5) : hue.accent))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(on ? hue.accent.deepHead : Color.clear))
                .overlay(Capsule().strokeBorder(off ? Theme.border : hue.accent.opacity(on ? 0 : 0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(off)
        .accessibilityLabel("\(Disciplines.five.first { $0.id == sport }?.label ?? sport) on \(WeekShape.weekdayNames[d])")
        .accessibilityValue(on ? "fits" : "does not fit")
        .accessibilityIdentifier("ws-chip-\(d)-\(sport)")
    }

    private var longDaysCard: some View {
        let hue = LaneHue.gold
        return VStack(alignment: .leading, spacing: 6) {
            Text("THE LONG DAYS AND THE REST DAY").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            dayPicker("Long ride", value: $shape.longRide, id: "ws-long-ride", hue: hue)
            dayPicker("Long run", value: $shape.longRun, id: "ws-long-run", hue: hue)
            dayPicker("Rest day", value: $shape.rest, id: "ws-rest", hue: hue)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }

    /* The name, and the chosen day right beside it. */
    private func dayPicker(_ name: String, value: Binding<Int>, id: String, hue: LaneHue) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            Picker(name, selection: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; shape = shape.normalised })) {
                ForEach(0..<7, id: \.self) { Text(WeekShape.weekdayNames[$0]).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(hue.accent)
            .accessibilityIdentifier(id)
            Spacer(minLength: 0)
        }
    }

    private var layOutCard: some View {
        let hue = LaneHue.rust
        return VStack(alignment: .leading, spacing: 6) {
            Text("YOUR COMING WEEKS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            if !store.canChangePlan {
                Text("Your coming weeks can be laid out once your plan lives in this app.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            } else if unsaved {
                Text("Save first, then lay out your coming weeks this way.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("ws-save-first")
            } else {
                Text("Shows first what would move. Only sessions after today that are not done, in ordinary weeks.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                NavigationLink { LayOutPreviewPage(shape: shape.normalised) } label: {
                    Text("Lay out my coming weeks this way").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.mainButton))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ws-layout-open")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }
}

// MARK: - what would move

struct LayOutPreviewPage: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let shape: WeekShape
    @State private var done: (batch: String, count: Int)?
    @State private var undone = false
    @State private var problem: String?
    @State private var asking = false

    private var change: LayOut.Change {
        guard let book = store.book else { return LayOut.Change() }
        return LayOut.plan(sessions: store.displayed, weeks: book.weeks, shape: shape, mapping: book.mapping,
                           today: store.today, away: AwayStore.current(today: store.today))
    }

    var body: some View {
        let c = done == nil ? change : LayOut.Change()
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head(c)
                if let done {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(undone ? "Undone: your sessions are back on their days."
                                    : "Done: \(done.count) session\(done.count == 1 ? "" : "s") moved. One Undo takes them all back.")
                            .font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                            .accessibilityIdentifier("lo-done")
                        if !undone {
                            Button("Undo") { asking = true }
                                .settingsButton(tint: Theme.danger)
                                .accessibilityIdentifier("lo-undo")
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LaneHue.indigo.tile))
                } else if c.isEmpty {
                    Text("Nothing to move: your coming weeks already fit this shape, or their sessions are done, tests, races or in special weeks.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LaneHue.indigo.tile))
                        .accessibilityIdentifier("lo-nothing")
                } else {
                    ForEach(Array(c.weeks.prefix(2).enumerated()), id: \.offset) { i, w in
                        weekCard(w, hue: i == 0 ? .indigo : .gold, id: "lo-week-\(i + 1)")
                    }
                    if c.weeks.count > 2 {
                        Text("And \(c.weeks.count - 2) more week\(c.weeks.count - 2 == 1 ? "" : "s") the same way.")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    Text("Never moved: sessions on or before today, done or missed sessions, tests, races, easy weeks, test weeks, race week and your away days. Each session stays in its own week.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.danger).accessibilityIdentifier("lo-problem")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(LaneHue.slate.tile.opacity(0.45).ignoresSafeArea())
        .navigationTitle("Lay out my weeks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(done == nil ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("lo-cancel")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if done == nil && !c.isEmpty && store.canChangePlan {
                VStack(spacing: 6) {
                    Button { take(c) } label: {
                        Text("Take it").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                    .accessibilityIdentifier("lo-take")
                    Button("Keep my plan") { dismiss() }
                        .font(.subheadline.weight(.semibold)).tint(Theme.settings)
                        .accessibilityIdentifier("lo-keep")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.bar)
            }
        }
        .confirmationDialog("Undo the lay-out?", isPresented: $asking, titleVisibility: .visible) {
            Button("Undo", role: .destructive) { undo() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The moved sessions go back to their days. What you have logged since stays.")
        }
    }

    private func head(_ c: LayOut.Change) -> some View {
        let n = done?.count ?? c.moves.count
        return VStack(alignment: .leading, spacing: 3) {
            Text("LAY OUT MY COMING WEEKS").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(n)).font(.largeTitle.weight(.bold))
                Text(n == 1 ? "session moves" : "sessions move").font(.subheadline.weight(.semibold))
                if done == nil, !c.isEmpty {
                    Text("in \(c.weeks.count) week\(c.weeks.count == 1 ? "" : "s")").font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("lo-count")
            Text(WeekShapeShelf.summary(shape)).font(.footnote).opacity(0.92)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.settings.deepHead))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lo-page")
    }

    private func weekCard(_ w: LayOut.Week, hue: LaneHue, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WEEK OF " + Dates.short(w.monday).uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            ForEach(Array(w.moves.enumerated()), id: \.offset) { _, m in
                Text(m.words).font(.body).foregroundStyle(Theme.text)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    private func take(_ c: LayOut.Change) {
        let batch = String(UUID().uuidString.prefix(8)).lowercased()
        if let ids = store.applyPlanBatch({ book in try LayOut.apply(c, to: &book, why: LayOut.why(batch: batch)) }) {
            done = (batch, ids.count)
            problem = nil
        } else {
            problem = store.lastProblem ?? "Your plan could not be changed. Nothing was changed."
        }
    }

    private func undo() {
        guard let done else { return }
        if let n = store.applyPlanBatch({ book in try LayOut.undo(batch: done.batch, in: &book) }) {
            // Nothing could go back (each session was changed or logged since): never "Undone".
            undone = n > 0
            problem = n > 0 ? nil : "The sessions were changed again since, so nothing was taken back."
        } else {
            problem = store.lastProblem ?? "The lay-out could not be undone. Nothing was changed."
        }
    }
}
