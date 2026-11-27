import SwiftUI
import UIKit
import WorkoutCore

/*
 * Round 30, lane raceweek: the tune-up race (12), race week (13) and the race report (15).
 * Cards and pages in the Body look: a head card filled with the page's colour, tiles, slim bars, a colour of
 * its own for each card (never green, red or teal as a card colour). A tune-up race is a race, so its tile is
 * the race's red, as everywhere. Nothing here changes his plan except "Take it" on the tune-up card, in one
 * batch with one Undo. Everything he types or ticks is on the shelf (raceweek/…), so it follows him.
 */

// MARK: - colours

enum RaceWeekLook {
    /* Race week's own colour: indigo. */
    static let week = BodyHue.sleep
    /* The race report's: Progress purple. */
    static let report = BodyHue(accent: Theme.progress, tile: .dynamic(light: 0xEEE5FD, dark: 0x352259))
    /* Filled cards carry white words, so their fill is the same deep colour by day and night. */
    static let weekFill = Color(hex: 0x4F46E5)
    static let reportFill = Color(hex: 0x7C3AED)
    static let ground = Color.dynamic(light: 0xF3F3FD, dark: 0x14132B)
    static let reportGround = Color.dynamic(light: 0xF6F1FE, dark: 0x1C1230)
    /* Days of race week, one colour each. */
    static let days: [BodyHue] = [.sleep, .stress, .resting, .gym, .intensity, .load, .workouts]
    /* "What to keep". */
    static let keep = BodyHue.stress
}

// MARK: - what is coming up

struct RaceWeekTarget: Equatable, Identifiable {
    let id: String
    let day: String
    let title: String
    let size: RaceSize?
    let start: String?
    let isTuneUp: Bool

    /* The plan's own race and every tune-up, soonest first. */
    @MainActor static func all(_ store: Store) -> [RaceWeekTarget] {
        let shelf = ShelfStore.shared
        var out: [RaceWeekTarget] = []
        if let r = RaceInfo.current(store) {
            let start = shelf.value(String.self, for: RaceWeekKeys.start(r.day))
            out.append(RaceWeekTarget(id: "main-" + r.day, day: r.day, title: r.title, size: RaceSize.from(title: r.title), start: start, isTuneUp: false))
        }
        for t in TuneUpList.sorted(shelf.value([TuneUp].self, for: RaceWeekKeys.tuneups) ?? []) {
            out.append(RaceWeekTarget(id: t.id, day: t.day, title: t.title, size: t.size, start: t.start.isEmpty ? nil : t.start, isTuneUp: true))
        }
        return out.sorted { $0.day < $1.day }
    }

    /* The race whose week it is: 0…7 days ahead, the soonest. */
    @MainActor static func inRaceWeek(_ store: Store) -> RaceWeekTarget? {
        all(store).first { RaceWeek.isOn(days: Stats.daysBetween(store.today, $0.day)) }
    }

    /* Races that were run in the last `within` days (0 = any time ago), newest first. */
    @MainActor static func past(_ store: Store, within: Int = 0) -> [RaceWeekTarget] {
        all(store).filter { $0.day <= store.today && (within == 0 || Stats.daysBetween($0.day, store.today) <= within) }.reversed()
    }

    static func invented(today: String) -> RaceWeekTarget {
        RaceWeekTarget(id: "invented", day: PlanView.addDays(today, 5), title: "Half-distance triathlon", size: .half, start: "07:30", isTuneUp: false)
    }
}

// MARK: - small pieces

private struct HeadCard: View {
    let label: String
    let title: String
    var line: String?
    let colour: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
            Text(title).font(.title2.weight(.bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            if let line { Text(line).font(.subheadline).foregroundStyle(.white.opacity(0.9)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colour))
    }
}

private struct FullButton: View {
    let title: String
    let colour: Color
    let id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(colour))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

private struct OutlineButton: View {
    let title: String
    let colour: Color
    let id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(colour)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().stroke(colour.opacity(0.6), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/* A page with Cancel and Save (Escape = Cancel). */
private struct SaveFrame<Content: View>: View {
    let title: String
    let idPrefix: String
    let ground: Color
    let canSave: Bool
    let save: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(14).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(ground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier(idPrefix + "-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.disabled(!canSave).accessibilityIdentifier(idPrefix + "-save")
                }
            }
        }
        .tint(Theme.plan)
    }
}

private func labelled(_ label: String, ink: Color, @ViewBuilder _ content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(ink)
        content()
    }
}

private func textBox(_ prompt: String, _ text: Binding<String>, id: String, keyboard: UIKeyboardType = .default) -> some View {
    TextField(prompt, text: text)
        .keyboardType(keyboard)
        .textFieldStyle(.plain)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.neutralSurface))
        .accessibilityIdentifier(id)
}

private func year(_ day: String) -> String {
    parseDayKey(day).map { String(utc.component(.year, from: $0)) } ?? ""
}

// MARK: - 12 · the tune-up race on the race page

/* Under the countdown on the race page: race week, the report, and his tune-up races. */
struct RaceExtras: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var editing: TuneUp?
    @State private var adding = false

    var body: some View {
        let list = TuneUpList.sorted(shelf.value([TuneUp].self, for: RaceWeekKeys.tuneups) ?? [])
        VStack(alignment: .leading, spacing: 10) {
            RaceWeekCard()
            ForEach(RaceWeekTarget.past(store)) { RaceReportCard(target: $0) }
            tuneUps(list)
        }
        .sheet(isPresented: $adding) { TuneUpEdit(tuneUp: nil, today: store.today) }
        .sheet(item: $editing) { TuneUpEdit(tuneUp: $0, today: store.today) }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["AMSWS_TUNEUP_EDIT"] != nil { adding = true }
            if ProcessInfo.processInfo.environment["AMSWS_TUNEUP_ROOM"] != nil, list.isEmpty {
                _ = shelf.set([TuneUpDebug.invented(store.today)], for: RaceWeekKeys.tuneups)
            }
        }
        #endif
    }

    private func tuneUps(_ list: [TuneUp]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tune-up races").font(.headline).foregroundStyle(RaceLook.ink).padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            if list.isEmpty {
                Text("A short rehearsal race in May or June. The plan can make room around it.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            ForEach(list) { t in
                VStack(alignment: .leading, spacing: 6) {
                    TuneUpTile(tuneUp: t) { editing = t }
                    TuneUpRoomCard(tuneUp: t)
                }
            }
            FullButton(title: "Add a tune-up race", colour: Theme.plan, id: "tuneup-add") { adding = true }
        }
    }
}

struct TuneUpTile: View {
    @EnvironmentObject var store: Store
    let tuneUp: TuneUp
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TUNE-UP RACE").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(RaceLook.ink)
                Text(tuneUp.title).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                Text(Dates.short(tuneUp.day) + " " + year(tuneUp.day) + (tuneUp.start.isEmpty ? "" : " \u{00B7} start " + tuneUp.start))
                    .font(.subheadline).foregroundStyle(Theme.text)
                Text([tuneUp.distanceWords, tuneUp.place].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RaceLook.tile))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tuneup-tile-" + tuneUp.day)
    }
}

/* Add or change a tune-up. Cancel and Save; a changed one can be taken out. */
struct TuneUpEdit: View {
    let tuneUp: TuneUp?
    let today: String
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var date = Date()
    @State private var size = RaceSize.sprint
    @State private var km = ""
    @State private var place = ""
    @State private var start = ""
    @State private var loaded = false
    @State private var askRemove = false

    private var kmValue: Double? { Double(km.replacingOccurrences(of: ",", with: ".")) }
    private var startOK: Bool { start.trimmingCharacters(in: .whitespaces).isEmpty || ClockText.minutes(start) != nil }
    private var canSave: Bool { startOK && (size != .other || km.isEmpty || (kmValue ?? 0) > 0) }

    var body: some View {
        SaveFrame(title: tuneUp == nil ? "Add a tune-up race" : "Tune-up race", idPrefix: "tuneup", ground: RaceLook.ground, canSave: canSave, save: save) {
            Text("A short rehearsal race. Once it is saved, the plan offers to make room around it. Nothing changes until you tap Take it.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            labelled("Name", ink: RaceLook.ink) { textBox("Tune-up race", $name, id: "tuneup-name") }
            labelled("Date", ink: RaceLook.ink) {
                DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
                    .accessibilityIdentifier("tuneup-date")
            }
            labelled("Distance", ink: RaceLook.ink) {
                Picker("Distance", selection: $size) {
                    ForEach([RaceSize.sprint, .olympic, .other], id: \.self) { Text($0.word).tag($0) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("tuneup-size")
                if size == .other { textBox("Kilometres in all, e.g. 30", $km, id: "tuneup-km", keyboard: .decimalPad) }
            }
            labelled("Place", ink: RaceLook.ink) { textBox("Where it is", $place, id: "tuneup-place") }
            labelled("Start time", ink: RaceLook.ink) {
                textBox("07:30", $start, id: "tuneup-start", keyboard: .numbersAndPunctuation)
                if !startOK { Text("Type the time as 07:30.").font(.caption).foregroundStyle(Theme.secondary) }
            }
            if tuneUp != nil {
                OutlineButton(title: "Take out this tune-up", colour: Theme.danger, id: "tuneup-remove") { askRemove = true }
                    .padding(.top, 6)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let t = tuneUp {
                name = t.name; size = t.size; km = t.km.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? ""
                place = t.place; start = t.start; date = parseDayKey(t.day) ?? Date()
            } else {
                date = parseDayKey(PlanView.addDays(today, 42)) ?? Date()
            }
        }
        .confirmationDialog("Take out this tune-up?", isPresented: $askRemove, titleVisibility: .visible) {
            Button("Take it out", role: .destructive) { remove() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Changes the plan made for it stay; take them back with Undo in Changes to the plan.")
        }
    }

    private func save() {
        var list = shelf.value([TuneUp].self, for: RaceWeekKeys.tuneups) ?? []
        let made = TuneUp(id: tuneUp?.id ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                          day: dayKey(date) ?? today, size: size, km: size == .other ? kmValue : nil,
                          place: place.trimmingCharacters(in: .whitespaces), start: start.trimmingCharacters(in: .whitespaces))
        if let i = list.firstIndex(where: { $0.id == made.id }) { list[i] = made } else { list.append(made) }
        _ = shelf.set(list, for: RaceWeekKeys.tuneups)
        // A moved date is a new question: the card asks again.
        if let old = tuneUp, old.day != made.day { shelf.remove(for: RaceWeekKeys.room(made.id)) }
    }

    private func remove() {
        var list = shelf.value([TuneUp].self, for: RaceWeekKeys.tuneups) ?? []
        list.removeAll { $0.id == tuneUp?.id }
        _ = shelf.set(list, for: RaceWeekKeys.tuneups)
        if let id = tuneUp?.id { shelf.remove(for: RaceWeekKeys.room(id)) }
        dismiss()
    }
}

/*
 * "Make room for the tune-up": the exact changes listed, Take it · Keep my plan, one Undo.
 * A tune-up too close to the main race, or in a test week, gets one calm grey line and nothing is changed.
 */
struct TuneUpRoomCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    let tuneUp: TuneUp
    @State private var problem: String?

    var body: some View {
        let state = shelf.value(TuneUpRoomState.self, for: RaceWeekKeys.room(tuneUp.id))
        VStack(alignment: .leading, spacing: 6) {
            if let state, state.answer == .took {
                changed(state)
            } else if state == nil, store.canChangePlan {
                offer()
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("tuneup-room-problem")
            }
        }
    }

    private func change() -> TuneUpRoom.Change {
        guard let book = store.book, let mapping = store.mapping,
              !TuneUpRoom.takenInPlan(book.changes, tuneUp: tuneUp) else { return TuneUpRoom.Change() }
        var mainDay = RaceInfo.current(store)?.day
        #if DEBUG
        // AMSWS_TUNEUP_ROOM=far: the fixture's race is days away; this shows the offer as if the main race were months off.
        if ProcessInfo.processInfo.environment["AMSWS_TUNEUP_ROOM"] == "far" { mainDay = PlanView.addDays(tuneUp.day, 70) }
        #endif
        return TuneUpRoom.plan(tuneUp, sessions: store.displayed, weeks: book.weeks, mainRaceDay: mainDay,
                               mapping: mapping, today: store.today)
    }

    @ViewBuilder private func offer() -> some View {
        let c = change()
        #if DEBUG
        // AMSWS_TUNEUP_ROOM=far: the fixture holds few sessions, so the card shows invented changes (buttons do nothing real).
        if ProcessInfo.processInfo.environment["AMSWS_TUNEUP_ROOM"] == "far" {
            card(headline: "Make room for the tune-up: Thu and Fri shorter and easy, Sat rest, Mon and Tue easy",
                 lines: ["Thu \u{00B7} Run 50 min \u{2192} 30 min, easy", "Fri \u{00B7} Bike 60 min \u{2192} 35 min, easy", "Sat \u{00B7} Swim taken out",
                         "Mon \u{00B7} Run 60 min, easy", "Tue \u{00B7} Bike 75 min \u{2192} 60 min, easy"], take: nil)
        } else { offerReal(c) }
        #else
        offerReal(c)
        #endif
    }

    @ViewBuilder private func offerReal(_ c: TuneUpRoom.Change) -> some View {
        if let grey = c.grey {
            Text(grey).font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tuneup-room-grey")
        } else if !c.isEmpty {
            card(headline: c.headline, lines: c.lines, take: c)
        }
    }

    private func card(headline: String, lines: [String], take c: TuneUpRoom.Change?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline).font(.headline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tuneup-room-headline")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    Text(line).font(.subheadline).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("tuneup-room-line-\(i)")
                }
            }
            Text("A session you have done, a test or a race is never changed.").font(.caption).foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                OutlineButton(title: RuleBookWords.takeIt, colour: Theme.plan, id: "tuneup-room-take") { if let c { take(c) } }
                OutlineButton(title: RuleBookWords.keepMyPlan, colour: Theme.plan, id: "tuneup-room-keep") {
                    if c != nil { _ = shelf.set(TuneUpRoomState(answer: .kept), for: RaceWeekKeys.room(tuneUp.id)) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.neutralSurface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tuneup-room-card")
    }

    private func changed(_ s: TuneUpRoomState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Changed for the tune-up").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Button("Undo") { undo(s) }.font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini)
                .tint(Theme.danger).accessibilityIdentifier("tuneup-room-undo")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.neutralSurface))
        .accessibilityIdentifier("tuneup-room-changed")
    }

    private func take(_ c: TuneUpRoom.Change) {
        let batch = String(UUID().uuidString.prefix(8))
        let n = store.writeBatch { book in try TuneUpRoom.apply(c, to: &book, why: TuneUpRoom.why(batch: batch)).count }
        if let n, n > 0 {
            problem = nil
            _ = shelf.set(TuneUpRoomState(answer: .took, batch: batch), for: RaceWeekKeys.room(tuneUp.id))
        } else {
            problem = "Your plan could not be changed. Nothing was changed."
        }
    }

    private func undo(_ s: TuneUpRoomState) {
        let n = store.writeBatch { book in try TuneUpRoom.undo(batch: s.batch, in: &book) }
        if n == nil {
            problem = "Your plan could not be changed. Nothing was changed."
            return
        }
        problem = (n ?? 0) == 0 ? "The plan was changed again since, so nothing was taken back." : nil
        shelf.remove(for: RaceWeekKeys.room(tuneUp.id))
    }
}

/* In the week board: a small race-red line on a tune-up's day. */
struct TuneUpDayMark: View {
    @ObservedObject private var shelf = ShelfStore.shared
    let day: String
    var body: some View {
        let here = TuneUpList.on(day, in: shelf.value([TuneUp].self, for: RaceWeekKeys.tuneups) ?? [])
        ForEach(here) { t in
            Text("Tune-up race").font(.caption2.weight(.bold)).foregroundStyle(RaceLook.ink)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(RaceLook.tile))
                .accessibilityIdentifier("tuneup-day-" + t.day)
        }
    }
}

// MARK: - 13 · race week

/* The card on Today and on the race page, from 7 days before until race day. */
struct RaceWeekCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    var target: RaceWeekTarget?
    @State private var open = false

    var body: some View {
        if let t = target ?? RaceWeekTarget.inRaceWeek(store) {
            let days = Stats.daysBetween(store.today, t.day)
            let ticks = shelf.value([String].self, for: RaceWeekKeys.ticks(t.day)) ?? []
            let total = RaceWeek.allItems(raceDay: t.day, size: t.size).count
            Button { open = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(RaceWeek.cardWords(days: days)).font(.headline).foregroundStyle(.white)
                    Text(t.title + " \u{00B7} " + Dates.short(t.day)).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    Text("\(RaceWeek.tickedCount(ticks, raceDay: t.day, size: t.size)) of \(total) things ticked \u{00B7} open the list \u{203A}")
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(RaceWeekLook.weekFill))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("raceweek-card")
            .sheet(isPresented: $open) { NavigationStack { RaceWeekPage(target: t) }.environmentObject(store) }
            #if DEBUG
            .task { if ProcessInfo.processInfo.environment["AMSWS_RACEWEEK_OPEN"] != nil { open = true } }
            #endif
        }
    }
}

struct RaceWeekPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    let target: RaceWeekTarget
    @State private var kit = false
    @State private var editingStart = false

    private var start: String { target.start ?? RaceWeek.defaultStart }

    var body: some View {
        let ticks = shelf.value([String].self, for: RaceWeekKeys.ticks(target.day)) ?? []
        let days = Stats.daysBetween(store.today, target.day)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HeadCard(label: target.isTuneUp ? "Tune-up race" : "Race", title: target.title,
                         line: Dates.short(target.day) + " " + year(target.day) + " \u{00B7} " + RaceWeek.cardWords(days: max(0, days)).replacingOccurrences(of: "Race week \u{00B7} ", with: ""),
                         colour: RaceWeekLook.weekFill)
                    .accessibilityIdentifier("raceweek-head")
                Text("A tick means done.").font(.caption).foregroundStyle(Theme.secondary)
                ForEach(Array(RaceWeek.days(raceDay: target.day, size: target.size).enumerated()), id: \.element.id) { i, d in
                    dayCard(d, hue: RaceWeekLook.days[i % RaceWeekLook.days.count], ticks: ticks)
                }
                morning()
                FullButton(title: "Open your kit list", colour: RaceWeekLook.weekFill, id: "raceweek-kit") { kit = true }
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(RaceWeekLook.ground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("raceweek-page")
        .navigationTitle("Race week")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("raceweek-done")
            }
        }
        .sheet(isPresented: $kit) { NavigationStack { RacePage(inSheet: true) }.environmentObject(store) }
        .sheet(isPresented: $editingStart) { StartTimeEdit(target: target) }
        .tint(RaceWeekLook.week.accent)
        #if DEBUG
        .task {
            if target.id == "invented", !shelf.has(RaceWeekKeys.ticks(target.day)) {
                _ = shelf.set(["d7-bike-check", "d7-guide", "d6-key-session"], for: RaceWeekKeys.ticks(target.day))
            }
        }
        #endif
    }

    private func dayCard(_ d: RaceWeekDay, hue: BodyHue, ticks: [String]) -> some View {
        let isToday = d.day == store.today
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Dates.short(d.day).uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(hue.accent)
                Text(d.before == 1 ? "the day before" : "\(d.before) days before").font(.caption).foregroundStyle(Theme.secondary)
                if isToday { Text("Today").font(.caption.weight(.bold)).foregroundStyle(Theme.today) }
            }
            ForEach(d.items) { item in
                tickRow(item, hue: hue, done: ticks.contains(item.id)) {
                    var now = ticks
                    if let i = now.firstIndex(of: item.id) { now.remove(at: i) } else { now.append(item.id) }
                    _ = shelf.set(now, for: RaceWeekKeys.ticks(target.day))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("raceweek-day-\(d.before)")
    }

    private func tickRow(_ item: RaceWeekItem, hue: BodyHue, done: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Theme.secondary.opacity(0.7), lineWidth: 1.5).opacity(done ? 0 : 1)
                    Circle().fill(Theme.mainButton).opacity(done ? 1 : 0)
                    if done { Glyph(name: "icon-check", size: 13).foregroundStyle(.white) }
                }
                .frame(width: 22, height: 22)
                Text(item.text).font(.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : "not done")
        .accessibilityIdentifier("raceweek-item-" + item.id)
    }

    private func morning() -> some View {
        let hue = BodyHue.gym
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("RACE MORNING").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(hue.accent)
                Text(Dates.short(target.day)).font(.caption).foregroundStyle(Theme.secondary)
            }
            ForEach(RaceWeek.morning(start: start)) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(step.clock).font(.body.weight(.bold)).foregroundStyle(Theme.text).frame(width: 52, alignment: .leading)
                    Text(step.text).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("raceweek-morning-" + step.clock)
            }
            Text(target.start == nil ? "Worked back from an assumed start at \(RaceWeek.defaultStart). Type your own start time." : "Worked back from your start at \(start). Check the race guide for when transition opens and closes.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("raceweek-morning-note")
            if !target.isTuneUp {
                OutlineButton(title: "Change the start time", colour: hue.accent, id: "raceweek-start-edit") { editingStart = true }
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("raceweek-morning")
    }
}

/* The main race's start time: Cancel and Save. */
struct StartTimeEdit: View {
    let target: RaceWeekTarget
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var text = ""
    @State private var loaded = false
    private var ok: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty || ClockText.minutes(text) != nil }

    var body: some View {
        SaveFrame(title: "Start time", idPrefix: "raceweek-start", ground: RaceWeekLook.ground, canSave: ok, save: save) {
            Text("The time your race starts. The race morning is worked back from it.").font(.footnote).foregroundStyle(Theme.secondary)
            labelled("Start time", ink: RaceWeekLook.week.accent) { textBox("07:30", $text, id: "raceweek-start-field", keyboard: .numbersAndPunctuation) }
            if !ok { Text("Type the time as 07:30.").font(.caption).foregroundStyle(Theme.secondary) }
        }
        .onAppear { if !loaded { loaded = true; text = target.start ?? "" } }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { shelf.remove(for: RaceWeekKeys.start(target.day)) } else { _ = shelf.set(t, for: RaceWeekKeys.start(target.day)) }
    }
}

// MARK: - 15 · race report

extension GarminClient {
    /* Garmin's multisport parent of that day and its children: swim, T1, bike, T2, run. Empty when there is none. */
    func multisportLegs(day: String) async throws -> [RaceLegResult] {
        let list = try await activities(from: day, to: day)
        guard let parent = list.filter({ GarminMultisport.isMultisport(typeKey: $0.typeKey) }).max(by: { $0.seconds < $1.seconds }) else { return [] }
        let detail = try await tolerant("/activity-service/activity/\(parent.id)")
        var kids: [GarminMultisport.Child] = []
        for id in GarminMultisport.childIds(parent: detail) {
            if let c = GarminMultisport.child(detail: try await tolerant("/activity-service/activity/\(id)")) { kids.append(c) }
        }
        return GarminMultisport.legs(kids)
    }
}

@MainActor
final class RaceReportReader: ObservableObject {
    static let shared = RaceReportReader()
    @Published private(set) var reading: Set<String> = []
    @Published private(set) var empty: Set<String> = []
    private var tried: [String: Date] = [:]

    /* Reads Garmin for that race day when the shelf holds no report yet (or when asked again); at most once in 30 minutes. */
    func read(day: String, force: Bool = false) async {
        let shelf = ShelfStore.shared
        if !force, shelf.has(RaceWeekKeys.report(day)) { return }
        #if DEBUG
        if GarminKey.isFake {
            _ = shelf.set(RaceReport(day: day, legs: Self.inventedLegs), for: RaceWeekKeys.report(day))
            return
        }
        #endif
        guard GarminKey.isSaved, !reading.contains(day) else { return }
        if !force, let t = tried[day], Date().timeIntervalSince(t) < 30 * 60 { return }
        tried[day] = Date()
        reading.insert(day)
        defer { reading.remove(day) }
        do {
            let legs = try await GarminClient.shared.multisportLegs(day: day)
            if legs.isEmpty { empty.insert(day) } else {
                empty.remove(day)
                _ = shelf.set(RaceReport(day: day, legs: legs), for: RaceWeekKeys.report(day))
            }
        } catch {
            // No connection or no key: the card says nothing new.
        }
    }

    static var inventedLegs: [RaceLegResult] {
        [RaceLegResult(leg: .swim, seconds: 2_455, metres: 1_900, speedMps: 0.77, avgHr: 131),
         RaceLegResult(leg: .t1, seconds: 262),
         RaceLegResult(leg: .bike, seconds: 10_960, metres: 90_000, speedMps: 8.2, avgHr: 139),
         RaceLegResult(leg: .t2, seconds: 141),
         RaceLegResult(leg: .run, seconds: 7_820, metres: 21_100, speedMps: 2.7, avgHr: 152)]
    }
}

/* The card on the race page and on Today. */
struct RaceReportCard: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var reader = RaceReportReader.shared
    let target: RaceWeekTarget
    @State private var open = false

    var body: some View {
        let report = shelf.value(RaceReport.self, for: RaceWeekKeys.report(target.day))
        Group {
            if let report, !report.legs.isEmpty {
                Button { open = true } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Race report").font(.headline).foregroundStyle(.white)
                        Text(target.title + " \u{00B7} " + Dates.short(target.day)).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                        Text("Each leg, the changeovers and your pacing against plan \u{203A}").font(.caption).foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(RaceWeekLook.reportFill))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("race-report-card")
                .sheet(isPresented: $open) { NavigationStack { RaceReportPage(target: target) } }
                #if DEBUG
                .task { if ProcessInfo.processInfo.environment["AMSWS_RACE_REPORT_OPEN"] != nil { open = true } }
                #endif
            } else if reader.empty.contains(target.day) {
                Text("Garmin holds no triathlon on \(Dates.short(target.day)) yet. The race report appears when it does.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("race-report-none")
            }
        }
        .task { await reader.read(day: target.day) }
    }
}

struct RaceReportPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var reader = RaceReportReader.shared
    @Environment(\.dismiss) private var dismiss
    let target: RaceWeekTarget
    @State private var payload: SharePayload?

    private var plan: RacePacing { shelf.value(RacePacing.self, for: RaceKeys.pacing(target.day)) ?? RacePacing() }

    var body: some View {
        let report = shelf.value(RaceReport.self, for: RaceWeekKeys.report(target.day)) ?? RaceReport(day: target.day, legs: [])
        let rows = report.rows(plan: plan)
        let total = report.legs.reduce(0) { $0 + $1.seconds }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RACE REPORT").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                    Text(target.title).font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text(Dates.short(target.day) + " " + year(target.day)).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(formatDuration(total)).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                        Text("all five parts").font(.headline).foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("race-report-total")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RaceWeekLook.reportFill))
                if plan.isEmpty {
                    Text("Type your times on the race page to see each leg against your plan.").font(.footnote).foregroundStyle(Theme.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(rows, id: \.leg) { legTile($0, firstPlanned: rows.first(where: { $0.planned != nil })?.leg) }
                }
                keepCard(report)
                FullButton(title: "Share as PDF", colour: RaceWeekLook.reportFill, id: "race-report-share") { share(report, rows) }
                Text("Speeds are Garmin\u{2019}s own averages, written per 100 m, km/h and per km.").font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
        .background(RaceWeekLook.reportGround.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-report-page")
        .navigationTitle("Race report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("race-report-done")
            }
        }
        .sheet(item: $payload) { ActivitySheet(items: $0.items) }
        .tint(RaceWeekLook.report.accent)
        .task {
            #if DEBUG
            if target.id == "invented-report", !shelf.has(RaceKeys.pacing(target.day)) {
                _ = shelf.set(RacePacing(swim: 2_400, t1: 270, bike: 10_800, t2: 150, run: 7_500), for: RaceKeys.pacing(target.day))
            }
            if ProcessInfo.processInfo.environment["AMSWS_RACE_REPORT_PDF"] != nil { _ = makePDF(report, report.rows(plan: plan)) }
            #endif
        }
    }

    private func hue(_ leg: RaceLeg) -> Color {
        switch leg {
        case .swim: return Theme.sport("swim")
        case .bike: return Theme.sport("bike")
        case .run: return Theme.sport("run")
        default: return Theme.settings
        }
    }

    private func legTile(_ r: RaceReport.Row, firstPlanned: RaceLeg? = nil) -> some View {
        let colour = hue(r.leg)
        return VStack(alignment: .leading, spacing: 4) {
            Text(r.leg.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(colour)
            Text(RaceReport.line(r)).font(.headline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(colour.opacity(0.18))
                    Capsule().fill(colour).frame(width: max(6, g.size.width * r.fillFraction))
                    if let p = r.plannedFraction {
                        Rectangle().fill(Theme.text).frame(width: 2, height: 12).offset(x: max(0, g.size.width * p - 1))
                    }
                }
            }
            .frame(height: 8)
            let facts = [r.metres.map { $0 >= 1000 ? String(format: "%.1f km", $0 / 1000) : "\(Int($0)) m" },
                         RaceReport.speedWords(r.leg, mps: r.speedMps),
                         r.avgHr.map { "pulse \(Int($0.rounded()))" }].compactMap { $0 }
            if !facts.isEmpty {
                Text(facts.joined(separator: " \u{00B7} ")).font(.caption).foregroundStyle(Theme.secondary)
            }
            if r.planned != nil, r.leg == firstPlanned { Text("The dark mark on the bar is your plan.").font(.caption2).foregroundStyle(Theme.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colour.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("race-report-leg-" + r.leg.rawValue)
    }

    private func keepCard(_ report: RaceReport) -> some View {
        let hue = RaceWeekLook.keep
        return VStack(alignment: .leading, spacing: 4) {
            Text("WHAT TO KEEP").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(hue.accent)
            ForEach(Array(report.keep(plan: plan).enumerated()), id: \.offset) { i, line in
                Text(line).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("race-report-keep-\(i)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("race-report-keep")
    }

    // MARK: PDF (A4, black on white, as the plan print is)

    private func share(_ report: RaceReport, _ rows: [RaceReport.Row]) {
        if let url = makePDF(report, rows) { payload = SharePayload(items: [url]) }
    }

    @MainActor private func makePDF(_ report: RaceReport, _ rows: [RaceReport.Row]) -> URL? {
        let page = RaceReportPrintPage(title: target.title, date: Dates.short(target.day) + " " + year(target.day), rows: rows, keep: report.keep(plan: plan),
                                       total: report.legs.reduce(0) { $0 + $1.seconds })
        let renderer = ImageRenderer(content: page)
        let name = "Race report \(target.day).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var written = false
        renderer.render { _, draw in
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            written = true
        }
        return written ? url : nil
    }
}

private struct RaceReportPrintPage: View {
    let title: String
    let date: String
    let rows: [RaceReport.Row]
    let keep: [String]
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Race report").font(.system(size: 11, weight: .bold)).foregroundStyle(.gray)
            Text(title).font(.system(size: 22, weight: .bold))
            Text(date + " \u{00B7} all five parts " + formatDuration(total)).font(.system(size: 12))
            Rectangle().fill(.black).frame(height: 0.5)
            ForEach(rows, id: \.leg) { r in
                VStack(alignment: .leading, spacing: 3) {
                    Text(RaceReport.line(r)).font(.system(size: 13, weight: .semibold))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.2))
                            Capsule().fill(Color.black.opacity(0.75)).frame(width: max(5, g.size.width * r.fillFraction))
                            if let p = r.plannedFraction { Rectangle().fill(.red).frame(width: 2, height: 10).offset(x: g.size.width * p - 1) }
                        }
                    }
                    .frame(height: 7)
                    let facts = [r.metres.map { $0 >= 1000 ? String(format: "%.1f km", $0 / 1000) : "\(Int($0)) m" },
                                 RaceReport.speedWords(r.leg, mps: r.speedMps), r.avgHr.map { "pulse \(Int($0.rounded()))" }].compactMap { $0 }
                    if !facts.isEmpty { Text(facts.joined(separator: " \u{00B7} ")).font(.system(size: 10)).foregroundStyle(.gray) }
                }
            }
            Text("What to keep").font(.system(size: 13, weight: .bold)).padding(.top, 6)
            ForEach(Array(keep.enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 12)) }
            Spacer(minLength: 0)
            Text("The red mark on a bar is the planned time.").font(.system(size: 9)).foregroundStyle(.gray)
        }
        .foregroundStyle(.black)
        .padding(36)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Today

/* One hook on Today: the tune-up question, race week, and the race report for a week after the race. */
struct RaceTodayCards: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        let tuneUps = TuneUpList.sorted(shelf.value([TuneUp].self, for: RaceWeekKeys.tuneups) ?? []).filter { $0.day > store.today }
        let recent = RaceWeekTarget.past(store, within: 7)
        if !tuneUps.isEmpty || RaceWeekTarget.inRaceWeek(store) != nil || !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tuneUps) { t in
                    if shelf.value(TuneUpRoomState.self, for: RaceWeekKeys.room(t.id)) == nil { TuneUpRoomCard(tuneUp: t) }
                }
                RaceWeekCard()
                ForEach(recent) { RaceReportCard(target: $0) }
            }
        }
    }
}

// MARK: - pictures (DEBUG only)

#if DEBUG
enum TuneUpDebug {
    /* A Sunday about three weeks ahead, in whatever plan is open. */
    static func invented(_ today: String) -> TuneUp {
        var d = PlanView.addDays(today, 21)
        while PlanView.weekStart(d) != PlanView.addDays(d, -6) { d = PlanView.addDays(d, 1) }
        return TuneUp(id: "invented", name: "Spring tune-up", day: d, size: .olympic, place: "The lake", start: "09:00")
    }
}

/*
 * Launch switches: AMSWS_TUNEUP_EDIT=1 (the Add page), AMSWS_TUNEUP_ROOM=1 (the card alone, with an invented tune-up),
 * AMSWS_RACEWEEK=1 (the page, an invented half race in 5 days; AMSWS_RACEWEEK_CARD=1 the card alone),
 * AMSWS_RACE_REPORT=1 (the page with invented Garmin legs; AMSWS_RACE_REPORT_CARD=1 the card alone; AMSWS_RACE_REPORT_PDF=1 also writes the PDF).
 * With AMSWS_RACE_PAGE=1 the race page itself shows the same cards (AMSWS_TUNEUP_ROOM / AMSWS_TUNEUP_EDIT seed and open them there).
 */
struct RaceWeekDebugScreens: View {
    @EnvironmentObject var store: Store
    private let env = ProcessInfo.processInfo.environment

    var body: some View {
        if env["AMSWS_RACE_PAGE"] == nil, env["AMSWS_TUNEUP_EDIT"] != nil {
            TuneUpEdit(tuneUp: nil, today: store.today).environmentObject(store)
        }
        if env["AMSWS_RACE_PAGE"] == nil, env["AMSWS_TUNEUP_ROOM"] != nil {
            ScrollView {
                VStack(spacing: 8) {
                    TuneUpTile(tuneUp: TuneUpDebug.invented(store.today)) {}
                    TuneUpRoomCard(tuneUp: TuneUpDebug.invented(store.today))
                }.padding(12)
            }
            .background(RaceLook.ground.ignoresSafeArea()).environmentObject(store)
        }
        if env["AMSWS_RACEWEEK"] != nil {
            NavigationStack { RaceWeekPage(target: .invented(today: store.today)) }.environmentObject(store)
        }
        if env["AMSWS_RACEWEEK_CARD"] != nil {
            VStack { RaceWeekCard(target: .invented(today: store.today)).padding(12); Spacer() }
                .background(Theme.bg.ignoresSafeArea()).environmentObject(store)
        }
        if env["AMSWS_RACE_REPORT"] != nil || env["AMSWS_RACE_REPORT_CARD"] != nil {
            let t = RaceWeekTarget(id: "invented-report", day: PlanView.addDays(store.today, -1), title: "Half-distance triathlon", size: .half, start: nil, isTuneUp: false)
            let _ = ShelfStore.shared.set(RaceReport(day: t.day, legs: RaceReportReader.inventedLegs), for: RaceWeekKeys.report(t.day))
            if env["AMSWS_RACE_REPORT"] != nil {
                NavigationStack { RaceReportPage(target: t) }.environmentObject(store)
            } else {
                VStack { RaceReportCard(target: t).padding(12); Spacer() }.background(Theme.bg.ignoresSafeArea()).environmentObject(store)
            }
        }
    }
}
#endif
