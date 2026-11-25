import SwiftUI
import WorkoutCore

/*
 * Round 28 — four extra facts beside a session's log (brick times, "Stomach OK?",
 * a niggle, open-water notes). They are EXTRAS: the plan, the log's own fields and the way
 * a session is saved are untouched. They live on the shelf, one key each:
 *   session/<Workout.key>/brick | stomach | niggle | openwater
 * and are written when the log is saved (removed again if he clears them).
 */

/* What the form holds for the four facts, as typed. */
struct LogExtrasDraft: Equatable {
    var bike = "", change = "", run = ""
    var stomach: StomachAnswer?
    var stomachLine = ""
    var niggle: NiggleNote?
    var waterOn = false
    var wetsuit: Bool?
    var temp = ""
    var waterLine = ""

    /* Which of the rows belong to this session (stomach depends on its length, so it is asked each time). */
    struct Applies { var brick = false, stomach = false, water = false }

    static func applies(_ w: Workout, seconds: Double?) -> Applies {
        Applies(brick: w.discipline.id == "brick", stomach: StomachNote.applies(seconds: seconds), water: w.discipline.id == "swim")
    }

    @MainActor static func load(_ key: String) -> LogExtrasDraft {
        var d = LogExtrasDraft()
        let shelf = ShelfStore.shared
        if let b = shelf.value(BrickLog.self, for: LogExtrasKeys.key(key, "brick")) {
            d.bike = clock(b.bikeSeconds)
            d.change = BrickLog.minutesSecondsText(b.changeSeconds)
            d.run = clock(b.runSeconds)
        }
        if let s = shelf.value(StomachNote.self, for: LogExtrasKeys.key(key, "stomach")) { d.stomach = s.answer; d.stomachLine = s.line }
        d.niggle = shelf.value(NiggleNote.self, for: LogExtrasKeys.key(key, "niggle"))
        if let o = shelf.value(OpenWaterNote.self, for: LogExtrasKeys.key(key, "openwater")) {
            d.waterOn = true; d.wetsuit = o.wetsuit; d.temp = o.tempC.map(String.init) ?? ""; d.waterLine = o.line
        }
        return d
    }

    /* "1:05", or "1:05:05" when seconds are there, so reading it back gives the same number. */
    private static func clock(_ seconds: Int?) -> String {
        guard let s = seconds else { return "" }
        let base = "\(s / 3600):" + String(format: "%02d", s % 3600 / 60)
        return s % 60 == 0 ? base : base + String(format: ":%02d", s % 60)
    }

    /* Whether anything differs from the shelf (nothing is written). */
    @MainActor func differs(for key: String, _ a: Applies) -> Bool { write(to: key, a, commit: false).differs }

    /* Writes what differs from the shelf (and removes what he cleared). False when a note could not be kept: he must be told. */
    @MainActor @discardableResult
    func apply(to key: String, _ a: Applies) -> Bool { write(to: key, a, commit: true).kept }

    @MainActor private func write(to key: String, _ a: Applies, commit: Bool) -> (differs: Bool, kept: Bool) {
        let shelf = ShelfStore.shared
        var differs = false
        var kept = true
        func sync<T: Codable & Equatable>(_ new: T?, _ fact: String) {
            let k = LogExtrasKeys.key(key, fact)
            let old = shelf.value(T.self, for: k)
            guard new != old else { return }
            differs = true
            guard commit else { return }
            if let new { if !shelf.set(new, for: k) { kept = false } } else { shelf.remove(for: k) }
        }
        if a.brick { sync(BrickLog.make(bike: bike, change: change, run: run), "brick") }
        if a.stomach { sync(StomachNote.make(answer: stomach, line: stomachLine), "stomach") }
        sync(niggle, "niggle")
        if a.water { sync(OpenWaterNote.make(on: waterOn, wetsuit: wetsuit, temp: temp, line: waterLine), "openwater") }
        return (differs, kept)
    }

    var brickNow: BrickLog? { BrickLog.make(bike: bike, change: change, run: run) }
}

/* Small caps name in the page's colour, as on the other tiles. */
struct NoteTile: View {
    let name: String
    let figure: String
    var tint: Color = Theme.plan
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text(figure).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }
}

/* A word button that shows when it is the chosen one: filled; the others outlined. One colour for all. */
struct ChoiceWord: View {
    let word: String
    let chosen: Bool
    let id: String
    let action: () -> Void
    var body: some View {
        Button(word, action: action)
            .settingsButton(tint: Theme.plan, filled: chosen)
            .accessibilityIdentifier(id)
    }
}

private func extrasBox() -> some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface2)
}

/* The rows on the log form (and, without the niggle, on the done page's "Change notes" sheet). */
struct LogExtrasSection: View {
    let workout: Workout
    @Binding var draft: LogExtrasDraft
    let seconds: Double?
    /* The log's own length box, for "Use … as the length". Nil: no offer. */
    var duration: Binding<String>?
    var includeNiggle = true
    /* A picture shows every row whatever the session. */
    var forced: LogExtrasDraft.Applies?
    @State private var niggling = false

    var body: some View {
        let a = forced ?? LogExtrasDraft.applies(workout, seconds: seconds)
        VStack(alignment: .leading, spacing: 10) {
            if a.brick || a.stomach || a.water || includeNiggle {
                SectionHeading(text: "Notes beside the log")
            }
            if a.brick { brick }
            if a.stomach { stomach }
            if includeNiggle { niggle }
            if a.water { water }
        }
        .accessibilityElement(children: .contain)
    }

    private var brick: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                box("Bike time", "1:10", $draft.bike, "brick-bike")
                box("Change-over", "1:30", $draft.change, "brick-change")
                box("Run time", "40", $draft.run, "brick-run")
            }
            Text("Bike and run: minutes, or 1:10 for an hour and ten. Change-over: minutes:seconds.")
                .font(.caption).foregroundStyle(Theme.secondary)
            if let words = draft.brickNow?.useSumWords, let clock = draft.brickNow?.sumAsClock,
               let duration, parseDuration(duration.wrappedValue) != parseDuration(clock) {
                Button(words) { duration.wrappedValue = clock }
                    .settingsButton(tint: Theme.today)
                    .accessibilityIdentifier("brick-use-sum")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }

    private func box(_ name: String, _ hint: String, _ text: Binding<String>, _ id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name.uppercased()).font(.caption2.weight(.bold)).tracking(0.4).foregroundStyle(Theme.plan)
                .lineLimit(1).minimumScaleFactor(0.7)
            TextField(hint, text: text)
                .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                .padding(8).background(extrasBox())
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stomach: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Stomach OK?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("stomach-row")
                ForEach(StomachAnswer.allCases, id: \.self) { a in
                    ChoiceWord(word: a.word, chosen: draft.stomach == a, id: "stomach-" + a.rawValue) {
                        draft.stomach = draft.stomach == a ? nil : a
                    }
                }
                Spacer(minLength: 0)
            }
            TextField("What did you eat and drink?", text: $draft.stomachLine, axis: .vertical)
                .lineLimit(1...3).padding(8).background(extrasBox())
                .accessibilityIdentifier("stomach-line")
            NavigationLink { FuelNotesPage() } label: { Text("Fuel notes").font(.caption.weight(.semibold)) }
                .buttonStyle(.bordered).controlSize(.mini).tint(Theme.plan)
                .accessibilityIdentifier("fuel-notes-open")
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }

    private var niggle: some View {
        HStack(spacing: 8) {
            Text("Niggle?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Text(draft.niggle.map { $0.placeWords + ($0.line.isEmpty ? "" : " — " + $0.line) } ?? "Nothing noted")
                .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Button(draft.niggle == nil ? "Add" : "Change") { niggling = true }
                .settingsButton(tint: Theme.plan)
                .accessibilityIdentifier("niggle-row")
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .sheet(isPresented: $niggling) { NiggleSheet(initial: draft.niggle) { draft.niggle = $0 } }
    }

    private var water: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open water", isOn: $draft.waterOn)
                .font(.subheadline.weight(.semibold)).tint(Theme.plan)
                .accessibilityIdentifier("openwater-switch")
            if draft.waterOn {
                HStack(spacing: 8) {
                    Text("Wetsuit").font(.subheadline).foregroundStyle(Theme.text)
                    ChoiceWord(word: "Yes", chosen: draft.wetsuit == true, id: "openwater-wetsuit") {
                        draft.wetsuit = draft.wetsuit == true ? nil : true
                    }
                    ChoiceWord(word: "No", chosen: draft.wetsuit == false, id: "openwater-wetsuit-no") {
                        draft.wetsuit = draft.wetsuit == false ? nil : false
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("Water temperature").font(.subheadline).foregroundStyle(Theme.text)
                    TextField("17", text: $draft.temp).keyboardType(.numberPad)
                        .multilineTextAlignment(.center).frame(width: 52).padding(6).background(extrasBox())
                        .accessibilityIdentifier("openwater-temp")
                    Text("°C").font(.subheadline).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                TextField("Sighting and conditions", text: $draft.waterLine, axis: .vertical)
                    .lineLimit(1...3).padding(8).background(extrasBox())
                    .accessibilityIdentifier("openwater-line")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }
}

/* "Niggle?" — where, which side, one line of his own words. Cancel and Save; Remove when one exists. */
struct NiggleSheet: View {
    let initial: NiggleNote?
    /* Called with the note, or nil for Remove. */
    let done: (NiggleNote?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var place: String?
    @State private var side: String?
    @State private var line: String
    @State private var problem: String?

    init(initial: NiggleNote?, done: @escaping (NiggleNote?) -> Void) {
        self.initial = initial; self.done = done
        _place = State(initialValue: initial?.place)
        _side = State(initialValue: initial?.side)
        _line = State(initialValue: initial?.line ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A note for yourself. Nothing here is advice or a diagnosis.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                    SectionHeading(text: "Where")
                    VStack(spacing: 0) {
                        ForEach(NiggleNote.places, id: \.self) { p in
                            Button { place = p; if !NiggleNote.sideApplies(to: p) { side = nil } } label: {
                                HStack { Text(p).font(.body).foregroundStyle(place == p ? Color.white : Theme.text); Spacer() }
                                    .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                                    .background(place == p ? Theme.plan : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("niggle-place-" + p.lowercased())
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if let p = place, NiggleNote.sideApplies(to: p) {
                        SectionHeading(text: "Which side")
                        HStack(spacing: 8) {
                            ForEach(NiggleNote.sides, id: \.self) { s in
                                ChoiceWord(word: s.capitalized, chosen: side == s, id: "niggle-side-" + s) { side = side == s ? nil : s }
                            }
                        }
                    }
                    SectionHeading(text: "In your words")
                    TextField("e.g. tight after the hills", text: $line, axis: .vertical)
                        .lineLimit(1...3).padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                        .accessibilityIdentifier("niggle-line")
                    if initial != nil {
                        Button("Remove") { done(nil); dismiss() }
                            .settingsButton(tint: Theme.secondary)
                            .accessibilityIdentifier("niggle-remove")
                    }
                }
                .padding(16).padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Niggle?").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading) }
                    Button(action: save) { Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 52) }
                        .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                        .accessibilityIdentifier("niggle-save")
                }
                .padding(16).background(Theme.bg)
            }
        }
    }

    private func save() {
        guard let note = NiggleNote.make(place: place, side: side, line: line) else { problem = "Pick where it is first."; return }
        done(note); dismiss()
    }
}

/* What the shelf holds for one session. */
struct SessionNotes: Equatable {
    var brick: BrickLog?
    var stomach: StomachNote?
    var niggle: NiggleNote?
    var water: OpenWaterNote?

    @MainActor static func load(_ key: String) -> SessionNotes {
        let s = ShelfStore.shared
        return SessionNotes(brick: s.value(BrickLog.self, for: LogExtrasKeys.key(key, "brick")),
                            stomach: s.value(StomachNote.self, for: LogExtrasKeys.key(key, "stomach")),
                            niggle: s.value(NiggleNote.self, for: LogExtrasKeys.key(key, "niggle")),
                            water: s.value(OpenWaterNote.self, for: LogExtrasKeys.key(key, "openwater")))
    }

    static let invented = SessionNotes(
        brick: BrickLog(bikeSeconds: 3900, changeSeconds: 80, runSeconds: 2700),
        stomach: StomachNote(answer: .soso, line: "Two bananas, a gel an hour, 750 ml of mix"),
        niggle: NiggleNote(place: "Calf", side: "left", line: "tight after the hills"),
        water: OpenWaterNote(wetsuit: true, tempC: 17, line: "Sighted every ten strokes, chop on the way back"))
}

/* One compact block on a done session's page: "Your notes on this session". */
struct SessionNotesBlock: View {
    let workout: Workout
    let mapping: Mapping
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var editing = false
    @State private var niggling = false
    @State private var draft = LogExtrasDraft()

    private var invented: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_DONE_EXTRAS"] != nil
        #else
        return false
        #endif
    }

    private var seconds: Double? { ShareText.actualSeconds(workout, mapping) ?? Plan.plannedSeconds(workout, mapping) }

    var body: some View {
        let notes = invented ? SessionNotes.invented : SessionNotes.load(workout.key)
        let a = invented ? LogExtrasDraft.Applies(brick: true, stomach: true, water: true) : LogExtrasDraft.applies(workout, seconds: seconds)
        let any = a.brick || a.stomach || a.water
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Your notes on this session")
            if let b = notes.brick, !b.isEmpty {
                HStack(spacing: 8) {
                    NoteTile(name: "Bike", figure: BrickLog.lengthText(b.bikeSeconds).ifEmpty("—"))
                    NoteTile(name: "Change-over", figure: BrickLog.minutesSecondsText(b.changeSeconds).ifEmpty("—"))
                    NoteTile(name: "Run", figure: BrickLog.lengthText(b.runSeconds).ifEmpty("—"))
                }
            }
            if let o = notes.water {
                HStack(spacing: 8) {
                    NoteTile(name: "Open water", figure: "On")
                    if let w = o.wetsuit { NoteTile(name: "Wetsuit", figure: w ? "Yes" : "No") }
                    if let t = o.tempC { NoteTile(name: "Water", figure: "\(t)°") }
                }
                if !o.line.isEmpty { Text(o.line).font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true) }
            }
            if let s = notes.stomach {
                HStack(spacing: 8) {
                    NoteTile(name: "Stomach", figure: s.answer?.word ?? "—").frame(maxWidth: 140)
                    if !s.line.isEmpty { Text(s.line).font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("stomach-row")
            }
            if let n = notes.niggle {
                Text(n.doneLine).font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
            FlowRow(spacing: 6) {
                Button(notes.niggle == nil ? "Niggle?" : "Change niggle") { niggling = true }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("niggle-row")
                if any && !invented {
                    Button(a.stomach && !a.brick && !a.water ? "Stomach OK?" : "Change notes") {
                        draft = LogExtrasDraft.load(workout.key); editing = true
                    }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("session-notes-edit")
                }
                if a.stomach {
                    NavigationLink { FuelNotesPage() } label: { Text("Fuel notes").font(.caption.weight(.semibold)) }
                        .buttonStyle(.bordered).controlSize(.mini).tint(Theme.plan)
                        .accessibilityIdentifier("fuel-notes-open")
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
        .accessibilityElement(children: .contain).accessibilityIdentifier("session-notes-block")
        .sheet(isPresented: $niggling) {
            NiggleSheet(initial: notes.niggle) { n in
                let k = LogExtrasKeys.key(workout.key, "niggle")
                if let n { shelf.set(n, for: k) } else { shelf.remove(for: k) }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ScrollView {
                    LogExtrasSection(workout: workout, draft: $draft, seconds: seconds, duration: nil, includeNiggle: false)
                        .padding(16)
                }
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle("Notes on this session").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false }.keyboardShortcut(.cancelAction) } }
                .safeAreaInset(edge: .bottom) {
                    Button { if draft.apply(to: workout.key, a) { editing = false } } label: {
                        Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                    .padding(16).background(Theme.bg)
                    .accessibilityIdentifier("session-notes-save")
                }
            }
        }
    }
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
