import SwiftUI
import WorkoutCore

/*
 * The plan maker (round 30, pick 1): "A new season plan made in the app:
 * race, date, hours a week." His answer on where it goes: "A draft beside
 * mine." His plan is never touched by making, changing or deleting a draft;
 * only "Switch to this plan" writes into it — from a Monday he picks, after a
 * safety copy, with one Undo. The rules are in Core (PlanMaker, DraftSwitch,
 * PlanMakerClaude); this file is the pages.
 *
 * The draft lives on the shelf in several keys (planmaker/draft/meta and
 * planmaker/draft/week/<n>), so each stays well under 64 KB and the draft
 * follows him between iPhone, iPad and Mac.
 */

// MARK: - colours

/* The season's amber family: the page's own colour, and each block its own shade. Never green, red or teal. */
enum DraftHue {
    /* The head card and the main button: white words stand on it by day and by night. */
    static let fill = Color.dynamic(light: 0xB45309, dark: 0x9A4608)
    /* The page behind, lightly tinted. */
    static let ground = Color.dynamic(light: 0xFDF6EC, dark: 0x1A1209)
    static let tile = Color.dynamic(light: 0xF8E9D3, dark: 0x3A2810)

    static func block(_ b: PlanBlock) -> Color {
        switch b {
        case .base: return .dynamic(light: 0xE0A23B, dark: 0xF2C46B)
        case .build: return .dynamic(light: 0xD97706, dark: 0xF59E0B)
        case .peak: return .dynamic(light: 0xC2410C, dark: 0xFB923C)
        case .taper: return .dynamic(light: 0x9A6B1F, dark: 0xD9A55B)
        case .raceWeek: return .dynamic(light: 0x7C2D12, dark: 0xE0855A)
        case .postSeason: return .dynamic(light: 0xA8946A, dark: 0xD6C79A)
        }
    }

    /* The block's word, readable on the page. */
    static func ink(_ b: PlanBlock) -> Color {
        switch b {
        case .base: return .dynamic(light: 0x8A5A0B, dark: 0xF2C46B)
        case .postSeason: return .dynamic(light: 0x6E5F3E, dark: 0xD6C79A)
        default: return block(b)
        }
    }
}

// MARK: - the draft on the shelf

@MainActor
enum PlanDraftShelf {
    struct Draft: Equatable {
        var meta: PlanDraftMeta
        var weeks: [MadeWeek]
    }

    #if DEBUG
    /* Picture switch: AMSWS_PLANMAKER=form|draft|claude|week|switch (an invented draft, never stored). */
    static var picture: String? { ProcessInfo.processInfo.environment["AMSWS_PLANMAKER"] }
    private static var invented: Draft?
    static func inventedDraft(_ store: Store) -> Draft {
        if let invented { return invented }
        let start = PlanMaker.defaultStart(lastSession: store.book?.sessions.last?.dayKey ?? store.plan.last?.dayKey, today: store.today)
        let settings = PlanMakerSettings(raceName: "Lakeside Half", raceDay: PlanView.addDays(start, 7 * 39 + 6), distance: .half,
                                         start: start, hoursLow: 6, hoursHigh: 10)
        let shape = WeekShapeShelf.current(store)
        let weeks = PlanMaker.make(settings, shape: shape)
        var meta = PlanDraftMeta(settings: settings, shape: shape, madeAt: Date(), weekCount: weeks.count,
                                 sessionCount: weeks.reduce(0) { $0 + $1.training.count })
        if picture == "claude" {
            let menu = PlanMaker.menu(settings: settings, shape: shape, tweaks: [], weeks: weeks)
            let facts = PlanMakerClaude.facts(settings: settings, shape: shape, tweaks: [], weeks: weeks)
            let a = PlanMakerClaude.invented(menu: menu, facts: facts)
            meta.note = a.note
            meta.offered = a.picks
        }
        let d = Draft(meta: meta, weeks: weeks.map { var w = $0; w.draft = meta.id; return w })
        invented = d
        return d
    }
    #endif

    static var meta: PlanDraftMeta? { ShelfStore.shared.value(PlanDraftMeta.self, for: PlanMaker.metaKey) }

    /* The draft, whole, or nil (none, or still arriving from another device). */
    static func load(_ store: Store) -> Draft? {
        if let meta {
            let weeks = (1...max(meta.weekCount, 1)).map { ShelfStore.shared.value(MadeWeek.self, for: PlanMaker.weekKey($0)) }
            return meta.complete(weeks).map { Draft(meta: meta, weeks: $0) }
        }
        #if DEBUG
        if let picture, picture != "form" { return inventedDraft(store) }
        #endif
        return nil
    }

    /* A draft is named on the shelf but not all its weeks are here yet. */
    static func arriving(_ store: Store) -> Bool { meta != nil && load(store) == nil }

    /*
     * Kept whole or not at all: the old draft's name goes first, then each
     * week, then the new name — so a half-written draft is never shown.
     */
    @discardableResult
    static func save(_ meta: PlanDraftMeta, _ weeks: [MadeWeek]) -> Bool {
        let shelf = ShelfStore.shared
        shelf.remove(for: PlanMaker.metaKey)
        for w in weeks {
            var mine = w
            mine.draft = meta.id
            guard shelf.set(mine, for: PlanMaker.weekKey(w.number)) else { return false }
        }
        for key in shelf.keys(prefix: PlanMaker.draftPrefix + "week/") {
            if let n = Int(key.split(separator: "/").last ?? ""), n > weeks.count { shelf.remove(for: key) }
        }
        var m = meta
        m.weekCount = weeks.count
        m.sessionCount = weeks.reduce(0) { $0 + $1.training.count }
        return shelf.set(m, for: PlanMaker.metaKey)
    }

    /* Only the meta (Claude's note, his picks): the weeks stay as they are. */
    @discardableResult
    static func saveMeta(_ meta: PlanDraftMeta) -> Bool { ShelfStore.shared.set(meta, for: PlanMaker.metaKey) }

    static func delete() {
        let shelf = ShelfStore.shared
        shelf.remove(for: PlanMaker.metaKey)
        for key in shelf.keys(prefix: PlanMaker.draftPrefix) { shelf.remove(for: key) }
    }

    static var record: SwitchRecord? { ShelfStore.shared.value(SwitchRecord.self, for: PlanMaker.switchKey) }

    /* The draft made again from its settings, shape and tweaks. */
    static func remade(_ meta: PlanDraftMeta) -> [MadeWeek] {
        PlanMaker.make(meta.settings, shape: meta.shape, tweaks: meta.tweaks)
    }
}

enum PlanMakerWords {
    static func hours(_ h: Double) -> String {
        h.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(h)) : String(format: "%.1f", h)
    }

    static func year(_ day: String) -> String { String(day.prefix(4)) }

    /* "Mon 9 Aug 2027". */
    static func dayYear(_ day: String) -> String { Dates.short(day) + " " + year(day) }

    static func discipline(_ id: String) -> Discipline {
        Disciplines.five.first { $0.id == id } ?? Disciplines.compound.first { $0.id == id }
            ?? (id == "rest" ? Disciplines.rest : Disciplines.other)
    }

    /* "Swim 2 · Bike 3 · Run 3 · Strength 2 · Mobility 3". */
    static func counts(_ w: MadeWeek) -> String {
        WeekShape.sports.compactMap { s in
            let n = w.count(s) + (s == "bike" ? w.count("brick") : 0)
            return n > 0 ? "\(discipline(s).label) \(n)" : nil
        }.joined(separator: " \u{00B7} ")
    }

    /* A day key from the date picker's day, and back (the phone's own calendar, as "today" is). */
    static func key(_ date: Date) -> String { PlanView.todayKey(date) }
    static func date(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }
}

// MARK: - the row in Settings

/*
 * "Make a new plan" — or, once there is a draft, "Your new plan (draft)".
 * 2.21, his ask (28 Nov 2026): it lives in Settings › Your plan only, as a row
 * under My week shape; before, it was a full-colour button on the Plan page and
 * the Sessions tab.
 */
struct PlanMakerRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        let hasDraft = PlanDraftShelf.meta != nil
        NavigationLink { PlanMakerHome().readableWidth(760) } label: {
            SettingsRow(title: hasDraft ? "Your new plan (draft)" : "Make a new plan",
                        sub: hasDraft ? "Ready to look at \u{2014} your plan stays until you switch"
                                      : "A draft of a new season beside your plan \u{2014} you switch when you choose",
                        chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan-maker-open")
    }
}

// MARK: - the plan maker's home: the form, or the draft

struct PlanMakerHome: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        let draft = PlanDraftShelf.load(store)
        Group {
            if !editing, let draft {
                PlanDraftPage(draft: draft, edit: { editing = true })
            } else if !editing, PlanDraftShelf.arriving(store) {
                Text("Your draft is still arriving from your other device. Open this page again in a moment.")
                    .font(.callout).foregroundStyle(Theme.secondary).padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DraftHue.ground.ignoresSafeArea())
                    .accessibilityIdentifier("pm-arriving")
            } else {
                PlanMakerForm(existing: draft?.meta,
                              cancel: { if editing && draft != nil { editing = false } else { dismiss() } },
                              made: { editing = false })
            }
        }
    }
}

// MARK: - the form

struct PlanMakerForm: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    let existing: PlanDraftMeta?
    let cancel: () -> Void
    let made: () -> Void

    @State private var s = PlanMakerSettings(raceDay: "", start: "")
    @State private var loaded = false
    @State private var notKept = false

    private var shape: WeekShape { WeekShapeShelf.current(store) }
    private var problems: [String] { PlanMaker.problems(s, today: store.today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head
                raceCard
                weeksCard
                hoursCard
                shapeCard
                if !problems.isEmpty && loaded {
                    VStack(alignment: .leading, spacing: 2) { ForEach(problems, id: \.self) { Text($0) } }
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DraftHue.tile))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pm-problems")
                }
                if notKept {
                    Text("The draft could not be kept on this \(Device.word). Your plan is not changed.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                }
                Button { make() } label: {
                    Text(existing == nil ? "Make the draft" : "Make the draft again").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DraftHue.fill))
                }
                .buttonStyle(.plain)
                .disabled(!problems.isEmpty)
                .opacity(problems.isEmpty ? 1 : 0.5)
                .accessibilityIdentifier("pm-make")
                if existing != nil {
                    Text("Making it again starts from the rules: changes taken from Claude are left out.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(DraftHue.ground.ignoresSafeArea())
        .navigationTitle("Plan maker")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("pm-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { make() }.disabled(!problems.isEmpty).accessibilityIdentifier("pm-save")
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let existing {
                s = existing.settings
            } else {
                let start = PlanMaker.defaultStart(lastSession: store.book?.sessions.last?.dayKey ?? store.plan.last?.dayKey, today: store.today)
                s = PlanMakerSettings(raceDay: PlanView.addDays(start, 7 * 39 + 6), start: start)
            }
            loaded = true
        }
    }

    private func make() {
        guard problems.isEmpty else { return }
        let weeks = PlanMaker.make(s, shape: shape)
        let meta = PlanDraftMeta(settings: s, shape: shape, madeAt: Date(), weekCount: weeks.count,
                                 sessionCount: weeks.reduce(0) { $0 + $1.training.count })
        if PlanDraftShelf.save(meta, weeks) {
            notKept = false
            made()
        } else {
            notKept = true
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PLAN MAKER").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            Text("A new season plan, made as a draft").font(.title3.weight(.bold))
            Text("It sits beside your plan: your plan is not changed until you switch.")
                .font(.footnote).opacity(0.92).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DraftHue.fill))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pm-form")
    }

    private func card<C: View>(_ name: String, _ hue: LaneHue, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(name).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }

    private var raceCard: some View {
        card("THE RACE", .indigo) {
            TextField("Race name", text: $s.raceName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("pm-race-name")
            DatePicker("Race date", selection: Binding(get: { PlanMakerWords.date(s.raceDay) },
                                                       set: { s.raceDay = PlanMakerWords.key($0) }),
                       displayedComponents: .date)
                .font(.body.weight(.semibold))
                .tint(LaneHue.indigo.accent)
                .accessibilityIdentifier("pm-race-date")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { distanceChips }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) { ForEach(RaceDistance.allCases.prefix(2), id: \.self) { distanceChip($0) } }
                    HStack(spacing: 5) { ForEach(RaceDistance.allCases.suffix(2), id: \.self) { distanceChip($0) } }
                }
            }
        }
    }

    private var distanceChips: some View { ForEach(RaceDistance.allCases, id: \.self) { distanceChip($0) } }

    private func distanceChip(_ d: RaceDistance) -> some View {
        WordChip(words: d.title, on: s.distance == d, hue: .indigo, id: "pm-distance-\(d.rawValue)") { s.distance = d }
    }

    private var weeksCard: some View {
        card("THE WEEKS", .gold) {
            DatePicker("First day", selection: Binding(get: { PlanMakerWords.date(s.start) },
                                                       set: { s.start = PlanMaker.monday(onOrAfter: PlanMakerWords.key($0)) }),
                       displayedComponents: .date)
                .font(.body.weight(.semibold))
                .tint(LaneHue.gold.accent)
                .accessibilityIdentifier("pm-start")
            Text("Always a Monday: \(PlanMakerWords.dayYear(s.start)). Unless you pick another, the Monday after your plan\u{2019}s last session.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if parseDayKey(s.start) != nil, parseDayKey(s.raceDay) != nil, s.raceDay > s.start {
                let n = PlanMaker.weekCount(start: s.start, raceDay: s.raceDay)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(n)).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                    Text(n == 1 ? "week to the race" : "weeks to the race, race week included").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pm-week-count")
            }
        }
    }

    private var hoursCard: some View {
        card("HOURS A WEEK", .magenta) {
            hoursRow("Lowest", $s.hoursLow, id: "pm-hours-low")
            hoursRow("Highest", $s.hoursHigh, id: "pm-hours-high")
            Text("Ordinary weeks climb from the lowest to the highest; Peak is the highest.")
                .font(.caption).foregroundStyle(Theme.secondary)
            Text("An easy week").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).padding(.top, 2)
            HStack(spacing: 5) {
                WordChip(words: "Every 3rd week", on: s.easyEvery == 3, hue: .magenta, id: "pm-easy-3") { s.easyEvery = 3 }
                WordChip(words: "Every 4th week", on: s.easyEvery == 4, hue: .magenta, id: "pm-easy-4") { s.easyEvery = 4 }
            }
            Text("Tests about every \(s.testEvery) weeks: a swim, a bike and a run test, in an easy week.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    /* The name, the figure right beside it, then the minus and plus. */
    private func hoursRow(_ name: String, _ value: Binding<Double>, id: String) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            Text(PlanMakerWords.hours(value.wrappedValue) + " h").font(.body.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
            Stepper(name, value: value, in: 3...20, step: 0.5).labelsHidden()
                .accessibilityIdentifier(id)
        }
    }

    private var shapeCard: some View {
        card("MY WEEK SHAPE", .rust) {
            Text(WeekShapeShelf.summary(shape)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Text("The plan lays its sessions out this way. Mobility on the days your shape gives it, 30 min.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            NavigationLink { WeekShapePage() } label: { Text("Change my week shape") }
                .settingsButton(tint: LaneHue.rust.accent)
                .accessibilityIdentifier("pm-shape")
        }
    }
}

/* A word that is chosen (filled in the card's colour, white words) or not (outlined). */
struct WordChip: View {
    let words: String
    let on: Bool
    let hue: LaneHue
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(words).font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.white : hue.accent)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(on ? hue.accent.deepHead : Color.clear))
                .overlay(Capsule().strokeBorder(hue.accent.opacity(on ? 0 : 0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - the draft

struct PlanDraftPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var client = ClaudeClient.shared
    let draft: PlanDraftShelf.Draft
    let edit: () -> Void
    @State private var deleting = false
    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    private var meta: PlanDraftMeta { draft.meta }
    private var weeks: [MadeWeek] { draft.weeks }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                head
                SwitchedCard()
                seasonCard
                tiles
                claudeCard
                weeksCard
                actions
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(DraftHue.ground.ignoresSafeArea())
        .navigationTitle("New plan")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this draft?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete draft", role: .destructive) {
                PlanDraftShelf.delete()
                dismiss()
            }
            .accessibilityIdentifier("pm-delete-confirm")
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The draft goes on all your devices. Your plan is not changed.")
        }
    }

    /* Filled in the season's amber: it is a draft, and his plan is not changed. */
    private var head: some View {
        let s = meta.settings
        let toRace = weeks.filter { $0.block != .postSeason }.count
        return VStack(alignment: .leading, spacing: 3) {
            Text("DRAFT").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            Text("Draft \u{2014} your plan is not changed").font(.title3.weight(.bold))
                .accessibilityIdentifier("pm-draft-title")
            Text("\(s.raceWords) \u{00B7} \(s.distance.title) \u{00B7} \(PlanMakerWords.dayYear(s.raceDay))")
                .font(.subheadline.weight(.semibold))
            Text("\(toRace) weeks from \(PlanMakerWords.dayYear(weeks.first?.monday ?? s.start)) \u{00B7} \(PlanMakerWords.hours(s.hoursLow))\u{2013}\(PlanMakerWords.hours(s.hoursHigh)) h a week")
                .font(.footnote).opacity(0.92)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DraftHue.fill))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pm-draft-head")
    }

    /* The blocks as one slim bar, each its own shade of the season's amber, with their names and weeks under it. */
    private var seasonCard: some View {
        let spans = PlanMaker.spans(weeks)
        return VStack(alignment: .leading, spacing: 7) {
            Text("THE SEASON").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.season)
            GeometryReader { geo in
                let gap: CGFloat = 2
                let unit = (geo.size.width - gap * CGFloat(max(spans.count - 1, 0))) / CGFloat(max(weeks.count, 1))
                HStack(spacing: gap) {
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, b in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(DraftHue.block(b.block))
                            .frame(width: max(3, unit * CGFloat(b.weeks)))
                    }
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, b in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(b.block.title).font(.caption.weight(.bold)).foregroundStyle(DraftHue.ink(b.block))
                        Text("\(b.weeks) wk").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DraftHue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pm-season")
    }

    private var tiles: some View {
        let toRace = weeks.filter { $0.block != .postSeason }
        let longest = toRace.filter { $0.block != .raceWeek }.max { $0.minutes < $1.minutes }
        let most = longest?.minutes ?? 0
        return HStack(spacing: 8) {
            DraftTile(name: "Weeks", figure: String(toRace.count), unit: "to the race",
                      note: "then \(weeks.count - toRace.count) easy", hue: .gold, id: "pm-tile-weeks")
            DraftTile(name: "Sessions", figure: String(weeks.reduce(0) { $0 + $1.training.count }), unit: "",
                      note: "rest days not counted", hue: .magenta, id: "pm-tile-sessions")
            DraftTile(name: "Longest week", figure: formatDuration(Double(most) * 60), unit: "",
                      note: longest.map { "in " + ($0.block == .raceWeek ? "race week" : $0.phase) } ?? "", hue: .rust, id: "pm-tile-hours")
        }
    }

    // MARK: Claude

    private var claudeCard: some View {
        let hue = LaneHue.indigo
        return VStack(alignment: .leading, spacing: 7) {
            Text("CLAUDE\u{2019}S LOOK").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            if !meta.note.isEmpty {
                ForEach(Array(meta.note.enumerated()), id: \.offset) { i, line in
                    Text(line).font(.subheadline).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pm-claude-line-\(i + 1)")
                }
            }
            if !meta.offered.isEmpty {
                Text("Claude picks, from the changes the rules allow:").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                ForEach(meta.offered, id: \.self) { t in
                    Text(t.words).font(.footnote).foregroundStyle(Theme.text)
                }
                HStack(spacing: 8) {
                    Button("Use these changes") { useOffered() }
                        .settingsButton(tint: hue.accent, filled: true)
                        .accessibilityIdentifier("pm-claude-use")
                    Button("Keep the draft as it is") { keepAsItIs() }
                        .settingsButton(tint: hue.accent)
                        .accessibilityIdentifier("pm-claude-keep")
                }
            } else if !meta.note.isEmpty {
                Text("Nothing in the draft changed.").font(.caption).foregroundStyle(Theme.secondary)
            }
            if !meta.tweaks.isEmpty {
                Text("Taken: " + meta.tweaks.map(\.words).joined(separator: "; ") + ".")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("pm-claude-taken")
            }
            if !client.canWrite {
                Text("Claude is off. Settings \u{2192} Claude turns it on; the draft is made by the rules either way.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("pm-claude-off")
            } else if let trouble = client.trouble {
                Text(trouble.restLine).font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("pm-claude-trouble")
            } else if meta.note.isEmpty {
                Text(PlanMakerClaude.sentWords + " " + ClaudeReview.costWords + " Claude may only pick from the changes the rules allow.")
                    .font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Button { Task { await ask() } } label: {
                    Text(busy ? "Asking\u{2026}" : "Ask Claude to look it over").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(hue.accent)
                .disabled(busy)
                .accessibilityIdentifier("pm-claude-ask")
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("pm-claude-message")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pm-claude-card")
    }

    private func ask() async {
        let menu = PlanMaker.menu(settings: meta.settings, shape: meta.shape, tweaks: meta.tweaks, weeks: weeks)
        let facts = PlanMakerClaude.facts(settings: meta.settings, shape: meta.shape, tweaks: meta.tweaks, weeks: weeks)
        let body = PlanMakerClaude.body(system: PlanMakerClaude.system, user: PlanMakerClaude.user(facts: facts, menu: menu))
        busy = true
        message = nil
        let result = await client.run(kind: "planmaker", label: "Looked over a new plan draft", body: body,
                                      fake: PlanMakerClaude.invented(menu: menu, facts: facts),
                                      read: { PlanMakerClaude.read($0, menu: menu, facts: facts) })
        busy = false
        switch result {
        case .answer(let a):
            var m = meta
            m.note = a.note
            m.offered = a.picks
            if !PlanDraftShelf.saveMeta(m) { message = "Claude\u{2019}s look could not be kept on this \(Device.word)." }
        case .notPassed:
            message = ClaudeReview.didNotPass
        case .none:
            message = client.trouble == nil ? ClaudeReview.nothingCame : nil
        }
    }

    /* His tap: the picked tweaks go through the same rules; the draft is made again with them. */
    private func useOffered() {
        var m = meta
        m.tweaks = m.offered.reduce(m.tweaks) { PlanMaker.adding($1, to: $0) }
        m.offered = []
        if !PlanDraftShelf.save(m, PlanDraftShelf.remade(m)) { message = "The draft could not be kept on this \(Device.word)." }
    }

    private func keepAsItIs() {
        var m = meta
        m.offered = []
        PlanDraftShelf.saveMeta(m)
    }

    // MARK: the weeks

    private var weeksCard: some View {
        let most = max(weeks.map(\.minutes).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text("THE WEEKS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(LaneHue.rust.accent)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
            Text("Tap a week to see its sessions.").font(.caption).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 12).padding(.bottom, 4)
            ForEach(weeks) { w in
                NavigationLink { PlanDraftWeekPage(week: w) } label: { DraftWeekRow(week: w, most: most) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pm-week-\(w.number)")
                if w.number != weeks.last?.number { Divider().overlay(Theme.border).padding(.leading, 12) }
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.neutralSurface))
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { PlanSwitchPage(draft: draft) } label: {
                Text("Switch to this plan").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DraftHue.fill))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pm-switch-open")
            Text("You pick the first day and see what happens before anything changes.")
                .font(.caption).foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                Button("Change the settings") { edit() }
                    .settingsButton(tint: DraftHue.fill)
                    .accessibilityIdentifier("pm-edit")
                Button("Delete draft") { deleting = true }
                    .settingsButton(tint: Theme.danger)
                    .accessibilityIdentifier("pm-delete")
            }
        }
        .padding(.top, 4)
    }
}

/* One tile: the name in small capitals, the figure beside its unit, one grey line. */
struct DraftTile: View {
    let name: String
    let figure: String
    let unit: String
    let note: String
    let hue: LaneHue
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name.uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(figure).font(.title2.weight(.bold))
                if !unit.isEmpty { Text(unit).font(.caption.weight(.semibold)) }
            }
            .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/* "Week 4 · Mon 12 Oct · 5h 55m", its block and kind, a slim bar, and the sessions by sport. */
struct DraftWeekRow: View {
    let week: MadeWeek
    let most: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Week \(week.number) \u{00B7} \(Dates.short(week.monday))").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(formatDuration(Double(week.minutes) * 60)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                Text("\u{203A}").font(.title3).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 6) {
                Text(week.block == .raceWeek ? "Race week" : week.phase).font(.caption.weight(.bold)).foregroundStyle(DraftHue.ink(week.block))
                if week.test { Text("Test week").font(.caption).foregroundStyle(Theme.secondary) }
                else if week.easy { Text("Easy week").font(.caption).foregroundStyle(Theme.secondary) }
            }
            GeometryReader { geo in
                Capsule().fill(DraftHue.block(week.block))
                    .frame(width: max(6, geo.size.width * CGFloat(week.minutes) / CGFloat(most)), height: 6)
            }
            .frame(height: 6)
            Text(PlanMakerWords.counts(week)).font(.caption).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - one week of the draft

struct PlanDraftWeekPage: View {
    let week: MadeWeek

    var body: some View {
        let days = (0..<7).map { PlanView.addDays(week.monday, $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WEEK \(week.number) \u{00B7} \((week.block == .raceWeek ? "Race week" : week.phase).uppercased())")
                        .font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                    Text("\(Dates.short(days[0])) \u{2013} \(Dates.short(days[6]))").font(.title3.weight(.bold))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(formatDuration(Double(week.minutes) * 60)).font(.title2.weight(.bold))
                        Text("planned \u{00B7} \(week.training.count) sessions" + (week.test ? " \u{00B7} test week" : (week.easy ? " \u{00B7} easy week" : "")))
                            .font(.footnote.weight(.semibold))
                    }
                    Text("A draft: nothing here is in your plan yet.").font(.footnote).opacity(0.92)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DraftHue.fill))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("pm-week-page")

                ForEach(days, id: \.self) { day in
                    let list = week.sessions.filter { $0.day == day }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Dates.long(day)).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(DraftHue.ink(week.block))
                            ForEach(Array(list.enumerated()), id: \.offset) { _, m in sessionRow(m) }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.neutralSurface))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(DraftHue.ground.ignoresSafeArea())
        .navigationTitle("Week \(week.number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sessionRow(_ m: MadeSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SportBadge(discipline: PlanMakerWords.discipline(m.sport), size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if m.sport != "rest" {
                    Text(formatDuration(Double(m.minutes) * 60) + (m.zone.isEmpty ? "" : " \u{00B7} " + m.zone))
                        .font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.sportInk(m.sport))
                }
                Text(m.purpose).font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pm-week-session")
    }
}

// MARK: - switching

/* On the draft page once he has switched: what happened, and the one Undo while it still stands. */
struct SwitchedCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var asking = false
    @State private var problem: String?

    var body: some View {
        if let book = store.book, let line = DraftSwitch.latest(in: book), let batch = DraftSwitch.batch(of: line.why) {
            let hue = LaneHue.slate
            VStack(alignment: .leading, spacing: 5) {
                Text("IN YOUR PLAN").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
                Text("\(DraftSwitch.shownWhy(line.why)): \(line.after).").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Switched \(line.at.formatted(date: .abbreviated, time: .shortened)).").font(.caption).foregroundStyle(Theme.secondary)
                Button("Undo the switch") { asking = true }
                    .settingsButton(tint: Theme.danger)
                    .accessibilityIdentifier("pm-switched-undo")
                if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pm-switched")
            .confirmationDialog("Undo the switch?", isPresented: $asking, titleVisibility: .visible) {
                Button("Undo", role: .destructive) { problem = DraftSwitchUndo.run(store, batch: batch) }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text(DraftSwitchUndo.words(store, batch: batch))
            }
        }
    }
}

@MainActor
enum DraftSwitchUndo {
    static func words(_ store: Store, batch: String) -> String {
        let logged = store.book.map { DraftSwitch.loggedSince(batch: batch, in: $0) } ?? 0
        return "The new plan\u{2019}s sessions are taken out again and the sessions it took out come back."
            + (logged > 0 ? " The \(logged) you have logged since stay\(logged == 1 ? "s" : "")." : "")
    }

    /* One Undo, in one save. Returns a problem in plain words, or nil when it was undone. */
    static func run(_ store: Store, batch: String) -> String? {
        let record = PlanDraftShelf.record
        let n = store.applyPlanBatch { book in try DraftSwitch.undo(batch: batch, record: record?.batch == batch ? record : nil, in: &book) }
        return n == nil ? (store.lastProblem ?? "The switch could not be undone. Nothing was changed.") : nil
    }
}

struct PlanSwitchPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    let draft: PlanDraftShelf.Draft
    @State private var from = ""
    @State private var done: SwitchRecord?
    @State private var problem: String?
    @State private var undone = false
    @State private var asking = false

    private var days: [String] { DraftSwitch.days(draft: draft.weeks, sessions: store.displayed, today: store.today) }

    var body: some View {
        let list = days
        let chosen = list.contains(from) ? from : (list.first ?? "")
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head
                if let done {
                    doneCard(done)
                } else if !store.canChangePlan {
                    note("Your plan must live in this app before it can switch. Nothing was changed.", id: "pm-switch-problem")
                } else if list.isEmpty {
                    note("Your plan has sessions that must stay \u{2014} done ones, tests or the race \u{2014} until after this draft\u{2019}s race week. Make the draft for a later race to switch.", id: "pm-switch-problem")
                } else {
                    dayCard(list, chosen: chosen)
                    wordsCard(chosen)
                }
                if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger).accessibilityIdentifier("pm-switch-failed") }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(DraftHue.ground.ignoresSafeArea())
        .navigationTitle("Switch to this plan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(done == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("pm-switch-cancel")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if done == nil, store.canChangePlan, !list.isEmpty {
                Button { go(chosen) } label: {
                    Text("Switch from \(PlanMakerWords.dayYear(chosen))").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DraftHue.fill))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pm-switch-go")
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.bar)
            }
        }
        .confirmationDialog("Undo the switch?", isPresented: $asking, titleVisibility: .visible) {
            Button("Undo", role: .destructive) {
                guard let done else { return }
                problem = DraftSwitchUndo.run(store, batch: done.batch)
                undone = problem == nil
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(done.map { DraftSwitchUndo.words(store, batch: $0.batch) } ?? "")
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SWITCH TO THIS PLAN").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            Text(draft.meta.settings.raceWords).font(.title3.weight(.bold))
            Text("Nothing changes until you tap the button below. A safety copy of your plan is kept first.")
                .font(.footnote).opacity(0.92).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DraftHue.fill))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pm-switch-page")
    }

    private func note(_ words: String, id: String) -> some View {
        Text(words).font(.callout).foregroundStyle(Theme.secondary)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DraftHue.tile))
            .accessibilityIdentifier(id)
    }

    private func dayCard(_ list: [String], chosen: String) -> some View {
        let hue = LaneHue.gold
        return VStack(alignment: .leading, spacing: 5) {
            Text("THE FIRST DAY").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            HStack(spacing: 8) {
                Text("From").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Picker("First day", selection: Binding(get: { chosen }, set: { from = $0 })) {
                    ForEach(list, id: \.self) { Text(PlanMakerWords.dayYear($0)).tag($0) }
                }
                .pickerStyle(.menu).tint(hue.accent).fixedSize()
                .accessibilityIdentifier("pm-switch-day")
                Spacer(minLength: 0)
            }
            Text("Always a Monday, after every session of your plan that must stay (done ones, tests and the race).")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }

    private func wordsCard(_ chosen: String) -> some View {
        let p = DraftSwitch.preview(sessions: store.displayed, draft: draft.weeks, from: chosen)
        let hue = LaneHue.indigo
        return VStack(alignment: .leading, spacing: 5) {
            Text("WHAT HAPPENS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            Text("From \(PlanMakerWords.dayYear(chosen)): \(p.added) sessions added. Nothing before that day changes.")
                .font(.body.weight(.semibold)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pm-switch-words")
            if p.takenOut > 0 {
                Text("\(p.takenOut) session\(p.takenOut == 1 ? "" : "s") of your current plan from that day on \(p.takenOut == 1 ? "is" : "are") taken out (none of them done).")
                    .font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
            if p.leftOut > 0 {
                Text("The draft\u{2019}s \(p.leftOut) sessions before that day are left out.")
                    .font(.subheadline).foregroundStyle(Theme.text)
            }
            Text("A safety copy of your plan is kept first (Settings \u{2192} Safety copies). One Undo takes the whole switch back.")
                .font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }

    private func doneCard(_ r: SwitchRecord) -> some View {
        let hue = LaneHue.slate
        return VStack(alignment: .leading, spacing: 6) {
            Text(undone ? "Undone: your plan is back as it was before the switch."
                        : "Done: \(r.added) sessions added from \(PlanMakerWords.dayYear(r.from))" + (r.removed > 0 ? ", \(r.removed) taken out." : "."))
                .font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pm-switch-done")
            if !undone {
                Text("A safety copy was kept first. Undo takes the whole switch back.").font(.footnote).foregroundStyle(Theme.secondary)
                Button("Undo the switch") { asking = true }
                    .settingsButton(tint: Theme.danger)
                    .accessibilityIdentifier("pm-switch-undo")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }

    private func go(_ chosen: String) {
        guard let book = store.book else { return }
        // A safety copy first: no copy, no switch.
        let before = Set(store.safetyCopyDays)
        store.keepAside(book, as: "other-plan", tail: PlanMakerCopy.tail)
        guard Set(store.safetyCopyDays).subtracting(before).contains(where: { $0.hasSuffix("-" + PlanMakerCopy.tail) }) else {
            problem = "No safety copy could be kept (is the \(Device.word) full?). Nothing was changed."
            return
        }
        let raceName = draft.meta.settings.raceWords
        let weeks = draft.weeks
        let today = store.today
        if let record = store.applyPlanBatch({ book in
            try DraftSwitch.apply(draft: weeks, from: chosen, raceName: raceName, to: &book, today: today)
        }) {
            ShelfStore.shared.set(record, for: PlanMaker.switchKey)
            done = record
            problem = nil
        } else {
            problem = store.lastProblem ?? "Your plan could not be changed. Nothing was changed."
        }
    }
}

/* The safety copy kept just before a switch, as the list of safety copies names it. */
@MainActor
enum PlanMakerCopy {
    static let tail = "newplan"

    /* "Fri 27 Nov 2026, 13:15 — your plan just before you switched to a new plan"; nil for any other copy. */
    static func title(_ id: String) -> String? {
        guard id.hasPrefix("other-plan-"), id.hasSuffix("-" + tail) else { return nil }
        let moment = Store.copyMoment(id)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd"
        let g = DateFormatter()
        g.locale = Locale(identifier: "en_GB"); g.dateFormat = "EEE d MMM yyyy"
        let day = f.date(from: String(moment.prefix(10))).map { g.string(from: $0) } ?? String(moment.prefix(10))
        return day + ", " + String(moment.dropFirst(11).prefix(2)) + ":" + String(moment.dropFirst(13).prefix(2))
            + " \u{2014} your plan just before you switched to a new plan"
    }
}

// MARK: - Changes to the plan: one entry for a switch or a lay-out

struct PlanMakerChangeRow: View {
    @EnvironmentObject var store: Store
    let changes: [PlanChange]
    let index: Int
    @State private var asking = false
    @State private var problem: String?

    private var mark: String { PlanMakerBatch.of(changes[0].why) ?? "" }
    private var isSwitch: Bool { mark.hasPrefix("switch:") }
    private var batch: String { String(mark.split(separator: ":").last ?? "") }
    private var summary: PlanChange? { changes.first { $0.kind == DraftSwitch.summaryKind } }

    private var canUndo: Bool {
        guard let book = store.book else { return false }
        if isSwitch { return summary.map { !$0.undone && DraftSwitch.latest(in: book)?.key == $0.key } ?? false }
        return !LayOut.undoable(changes, book: book).isEmpty
    }
    private var allUndone: Bool { isSwitch ? (summary?.undone ?? true) : changes.allSatisfy(\.undone) }

    var body: some View {
        let lead = changes[0]
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isSwitch ? "NEW PLAN" : "CHANGED").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Theme.plan)
                Text(lead.at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if allUndone {
                    Text("Undone").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("change-undone-\(index)")
                } else if canUndo {
                    Button("Undo") { asking = true }
                        .settingsButton(tint: Theme.danger)
                        .accessibilityIdentifier("change-undo-\(index)")
                } else {
                    Text("Changed again since").font(.caption).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("change-older-\(index)")
                }
            }
            if isSwitch {
                Text(DraftSwitch.shownWhy(lead.why)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text([summary?.after ?? "", summary?.before ?? ""].filter { !$0.isEmpty }.joined(separator: "; "))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            } else {
                Text(LayOut.why).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(changes.count) session\(changes.count == 1 ? "" : "s") moved").font(.footnote).foregroundStyle(Theme.secondary)
            }
            if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.neutralSurface))
        .opacity(allUndone ? 0.7 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-planmaker-\(index)")
        .confirmationDialog("Undo this change?", isPresented: $asking, titleVisibility: .visible) {
            Button("Undo", role: .destructive) { undo() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(isSwitch ? DraftSwitchUndo.words(store, batch: batch)
                          : "The moved sessions go back to their days. What you have logged since stays.")
        }
    }

    private func undo() {
        if isSwitch {
            problem = DraftSwitchUndo.run(store, batch: batch)
        } else if store.applyPlanBatch({ book in try LayOut.undo(batch: batch, in: &book) }) == nil {
            problem = store.lastProblem ?? "The change could not be undone. Nothing was changed."
        }
    }
}

// MARK: - picture switches (DEBUG only)

/*
 * AMSWS_PLANMAKER=form|draft|claude|week|switch: the plan maker's pages with an invented draft (never stored);
 * AMSWS_WEEKSHAPE=1: My week shape; AMSWS_WEEKSHAPE=layout: the lay-out preview with a shape that differs from the plan.
 */
struct PlanMakerDebugScreens: View {
    @EnvironmentObject var store: Store

    var body: some View {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let page = env["AMSWS_PLANMAKER"] {
            NavigationStack {
                switch page {
                case "form": PlanMakerForm(existing: nil, cancel: {}, made: {})
                case "week":
                    let d = PlanDraftShelf.inventedDraft(store)
                    PlanDraftWeekPage(week: d.weeks.first(where: \.test) ?? d.weeks[0])
                case "switch": PlanSwitchPage(draft: PlanDraftShelf.inventedDraft(store))
                default: PlanMakerHome()
                }
            }
            .environmentObject(store)
        }
        if let page = env["AMSWS_WEEKSHAPE"] {
            NavigationStack {
                if page == "layout" { LayOutPreviewPage(shape: WeekShapeShelf.pictureShape) } else { WeekShapePage() }
            }
            .environmentObject(store)
        }
        #endif
    }
}
