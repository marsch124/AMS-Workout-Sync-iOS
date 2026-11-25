import SwiftUI
import WorkoutCore

/*
 * The Race page (round 28, pick 25): his race day, written by him. A head card
 * in the race's own red with the countdown, then his plan for the five parts of
 * the day, his fuel plan and his kit checklist. Nothing here is worked out by
 * the app: it adds up the times he typed and divides his own grams by his own
 * hours. All of it lives on the shelf (race/<race day>/pacing|fuel|checklist),
 * so it follows him between his devices. Red means the race, here as everywhere;
 * nothing else on this page is red (a packed tick is green, as every tick is).
 */
enum RaceLook {
    /* The race's own red, as everywhere in the app. */
    static let fill = Theme.sport("race")
    static let ink = Theme.sportInk("race")
    static let tile = Color.dynamic(light: 0xFDE8E8, dark: 0x3B1B1B)
    static let ground = Color.dynamic(light: 0xFEF5F5, dark: 0x1F1111)
}

/* The race the plan holds: its day and its name. */
struct RaceInfo: Equatable {
    let day: String
    let title: String

    @MainActor static func current(_ store: Store) -> RaceInfo? {
        if let v = store.view, let road = Stats.road(v.visible, today: store.today, mapping: v.mapping), road.isRace {
            return RaceInfo(day: road.raceDay, title: road.raceTitle)
        }
        #if DEBUG
        // A picture without a plan: an invented half-distance race.
        if ProcessInfo.processInfo.environment["AMSWS_RACE_PAGE"] != nil {
            return RaceInfo(day: PlanView.addDays(store.today, 228), title: "Half-distance triathlon")
        }
        #endif
        return nil
    }
}

struct RacePage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    /* Opened over another page (a sheet): it gets a Done. */
    var inSheet = false

    @State private var editingPacing = false
    @State private var editingFuel = false
    @State private var addingFuel = false
    @State private var editingList = false
    @State private var askUntick = false

    var body: some View {
        Group {
            if let race = RaceInfo.current(store) { content(race) } else { noRace }
        }
        .background(RaceLook.ground.ignoresSafeArea())
        .navigationTitle("Race")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("race-done")
                }
            }
        }
        .tint(Theme.plan)
    }

    private var noRace: some View {
        Text("Your plan has no race day yet. When it has, your race page is here.")
            .font(.body).foregroundStyle(Theme.secondary)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("race-none")
    }

    // MARK: the page

    private func content(_ race: RaceInfo) -> some View {
        let pacing = shelf.value(RacePacing.self, for: RaceKeys.pacing(race.day)) ?? RacePacing()
        let fuel = shelf.value(RaceFuel.self, for: RaceKeys.fuel(race.day)) ?? RaceFuel()
        let list = shelf.value(RaceChecklist.self, for: RaceKeys.checklist(race.day)) ?? .starting
        return ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head(race)
                dayPlan(race, pacing)
                fuelPlan(race, fuel, pacing).id("race-fuel-part")
                kit(race, list).id("race-kit-part")
            }
            .padding(.horizontal, 12).padding(.bottom, 16).padding(.top, 6)
            .frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        #if DEBUG
        .task {
            // Pictures: AMSWS_RACE_SCROLL=fuel|kit scrolls down; AMSWS_RACE_OPEN=pacing|fuel|fuelrow|list opens an editing page.
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let w = env["AMSWS_RACE_SCROLL"] { proxy.scrollTo(w == "kit" ? "race-kit-part" : "race-fuel-part", anchor: .top) }
            switch env["AMSWS_RACE_OPEN"] {
            case "pacing": editingPacing = true
            case "fuel": editingFuel = true
            case "fuelrow": addingFuel = true
            case "list": editingList = true
            default: break
            }
        }
        #endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-page")
        .sheet(isPresented: $editingPacing) { RacePacingEdit(race: race) }
        .sheet(isPresented: $editingFuel) { RaceFuelEdit(race: race) }
        .sheet(isPresented: $addingFuel) { RaceFuelRowEditor(row: RaceFuelRow(), isNew: true) { row in
            var f = fuel; f.rows.append(row); shelf.set(f, for: RaceKeys.fuel(race.day))
        } }
        .sheet(isPresented: $editingList) { RaceChecklistEdit(race: race) }
        .confirmationDialog("Untick all \(list.packedCount) packed items?", isPresented: $askUntick, titleVisibility: .visible) {
            Button("Untick all") { shelf.set(list.unticked(), for: RaceKeys.checklist(race.day)) }
            Button("Keep them", role: .cancel) {}
        }
        #if DEBUG
        .task { seedForPicture(race) }
        #endif
    }

    // MARK: head card

    private func head(_ race: RaceInfo) -> some View {
        let days = Stats.daysBetween(store.today, race.day)
        var date = Dates.short(race.day)
        if let d = parseDayKey(race.day) { date += " " + String(utc.component(.year, from: d)) }
        let clock = RaceCountdown.make(days: days, doneDate: Dates.short(race.day))
        return VStack(alignment: .leading, spacing: 3) {
            Text("RACE").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
            Text(race.title).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text(date).font(.subheadline).foregroundStyle(.white.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(clock.figure)
                    .font(clock.phase == .done ? .title.weight(.bold) : .largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                if let beside = clock.beside {
                    Text(beside).font(.headline).foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("race-countdown")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RaceLook.fill))
    }

    // MARK: your plan for the day

    private func heading(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(RaceLook.ink).padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func dayPlan(_ race: RaceInfo, _ p: RacePacing) -> some View {
        let words = RaceKind.distances(fromTitle: race.title)
        return VStack(alignment: .leading, spacing: 8) {
            heading("Your plan for the day")
            finishLine(p)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(RaceLeg.allCases, id: \.self) { leg in legTile(leg, p, words?[leg]) }
            }
            Text("Your own times, added up. The app works out no pace and no speed.")
                .font(.caption).foregroundStyle(Theme.secondary)
            fullButton("Type your times", id: "race-edit-pacing") { editingPacing = true }
        }
    }

    private func finishLine(_ p: RacePacing) -> some View {
        Group {
            if let f = p.finish {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(f.complete ? "Planned finish" : "So far").font(.subheadline).foregroundStyle(Theme.secondary)
                    Text(formatDuration(Double(f.seconds))).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                    if !f.complete {
                        Text("\(f.typed) of 5 times typed").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            } else {
                Text("Type your five times to see your planned finish.").font(.subheadline).foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-finish")
    }

    private func legTile(_ leg: RaceLeg, _ p: RacePacing, _ distance: String?) -> some View {
        Button { editingPacing = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(leg.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(RaceLook.ink)
                if let s = p.seconds(leg) {
                    Text(RacePacing.words(s, changeOver: leg.isChangeOver)).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                } else {
                    Text("Not typed").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if let distance { Text(distance).font(.caption).foregroundStyle(Theme.secondary) }
                if !p.note(leg).isEmpty { Text(p.note(leg)).font(.footnote).foregroundStyle(Theme.text) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RaceLook.tile))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-leg-" + leg.rawValue)
    }

    // MARK: fuel plan

    private func fuelPlan(_ race: RaceInfo, _ f: RaceFuel, _ p: RacePacing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Fuel plan")
            if f.rows.isEmpty {
                Text("Add what you will eat and drink, and when. The grams are added up for each part.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(RaceFuelLeg.allCases, id: \.self) { leg in sumTile(leg, f, p) }
                }
                VStack(spacing: 6) {
                    ForEach(Array(f.rows.enumerated()), id: \.element.id) { i, row in
                        fuelRow(row, i)
                    }
                }
            }
            HStack(spacing: 8) {
                fullButton("Add a row", id: "race-fuel-add") { addingFuel = true }
                if f.rows.count > 0 {
                    plainButton("Arrange or change", id: "race-fuel-edit") { editingFuel = true }
                }
            }
        }
    }

    private func sumTile(_ leg: RaceFuelLeg, _ f: RaceFuel, _ p: RacePacing) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(leg.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(RaceLook.ink)
            Text("\(f.grams(leg)) g").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            if leg != .before {
                if let ph = f.gramsPerHour(leg, pacing: p) {
                    Text("\(ph) g an hour").font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("from your times").font(.caption2).foregroundStyle(Theme.secondary)
                } else {
                    Text(f.grams(leg) == 0 ? "No grams yet" : "Type your \(leg == .bike ? "bike" : "run") time for grams an hour")
                        .font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RaceLook.tile))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-fuel-sum-" + leg.rawValue)
    }

    private func fuelRow(_ row: RaceFuelRow, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(row.carbs) g").font(.body.weight(.bold)).foregroundStyle(Theme.text)
                Text(row.what.isEmpty ? "—" : row.what).font(.body).foregroundStyle(Theme.text)
            }
            Text(row.when.isEmpty ? row.leg.word : row.leg.word + " · " + row.when)
                .font(.caption).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(RaceLook.tile))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-fuel-row-\(n)")
    }

    // MARK: kit checklist

    private func kit(_ race: RaceInfo, _ list: RaceChecklist) -> some View {
        let ordered = list.ordered
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                heading("Kit checklist")
                Text("packed \(list.packedCount) of \(ordered.count)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("race-checklist-count")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
            ForEach(RaceKitGroup.allCases, id: \.self) { g in
                let items = ordered.enumerated().filter { $0.element.group == g }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(g.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(RaceLook.ink)
                            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
                        ForEach(items, id: \.element.id) { n, item in
                            tickRow(item, n) { shelf.set(list.toggled(item.id), for: RaceKeys.checklist(race.day)) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RaceLook.tile))
                }
            }
            }
            Text("A tick means packed.").font(.caption).foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                plainButton("Untick all", id: "race-untick-all", danger: true) { askUntick = true }
                    .disabled(list.packedCount == 0)
                plainButton("Change the list", id: "race-check-edit") { editingList = true }
            }
        }
    }

    private func tickRow(_ item: RaceKitItem, _ n: Int, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Theme.secondary.opacity(0.7), lineWidth: 1.5).opacity(item.packed ? 0 : 1)
                    Circle().fill(Theme.mainButton).opacity(item.packed ? 1 : 0)
                    if item.packed { Glyph(name: "icon-check", size: 13).foregroundStyle(.white) }
                }
                .frame(width: 22, height: 22)
                Text(item.name).font(.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.packed ? "packed" : "not packed")
        .accessibilityIdentifier("race-check-\(n)")
    }

    // MARK: buttons

    /* The page's main buttons are full colour. */
    private func fullButton(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(Theme.plan))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func plainButton(_ title: String, id: String, danger: Bool = false, _ action: @escaping () -> Void) -> some View {
        let c = danger ? Theme.danger : Theme.plan
        return Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(c)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().stroke(c.opacity(0.6), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    #if DEBUG
    /* For a picture: invented targets, fuel rows and a part-ticked list, when the shelf holds none. */
    private func seedForPicture(_ race: RaceInfo) {
        guard ProcessInfo.processInfo.environment["AMSWS_RACE_PAGE"] != nil else { return }
        if !shelf.has(RaceKeys.pacing(race.day)) {
            shelf.set(RacePacing(swim: 40 * 60, t1: 4 * 60 + 30, bike: 3 * 3600 + 15 * 60, t2: 2 * 60 + 30, run: 2 * 3600 + 5 * 60,
                                 swimNote: "by feel", bikeNote: "power 150–160 W", runNote: "pulse Z2"), for: RaceKeys.pacing(race.day))
        }
        if !shelf.has(RaceKeys.fuel(race.day)) {
            shelf.set(RaceFuel(rows: [
                RaceFuelRow(id: "f1", leg: .before, when: "Breakfast, 3 h before", what: "porridge and banana", carbs: 90),
                RaceFuelRow(id: "f2", leg: .bike, when: "every 20 min", what: "1 gel", carbs: 198),
                RaceFuelRow(id: "f3", leg: .bike, when: "from the second hour", what: "1 bar", carbs: 60),
                RaceFuelRow(id: "f4", leg: .run, when: "every 5 km", what: "1 gel", carbs: 88),
            ]), for: RaceKeys.fuel(race.day))
        }
        if !shelf.has(RaceKeys.checklist(race.day)) {
            var list = RaceChecklist.starting
            for i in [0, 1, 4, 5, 6, 8, 9, 13] where list.items.indices.contains(i) { list.items[i].packed = true }
            shelf.set(list, for: RaceKeys.checklist(race.day))
        }
    }
    #endif
}

/* The way in from Progress, the Plan page and the season flag: the page over what he was looking at. */
struct RaceSheetLink<Label: View>: View {
    @State private var open = false
    let label: Label
    init(@ViewBuilder label: () -> Label) { self.label = label() }
    var body: some View {
        Button { open = true } label: { label }
            .buttonStyle(.plain)
            .sheet(isPresented: $open) { NavigationStack { RacePage(inSheet: true) } }
    }
}
