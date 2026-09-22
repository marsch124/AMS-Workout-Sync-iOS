import SwiftUI
import WorkoutCore

/*
 * Something the plan did not ask for. It goes to the Extras sheet, never into
 * the plan, and "Counts as training" starts from the activity's kind — a walk
 * does not, a run does — but stays yours to override: a four-hour hike is
 * load whatever the list says.
 *
 * The same form corrects one already saved. It opens filled in with what the
 * sheet holds, and only the boxes that were altered are written — the row was
 * read before whatever was last done to the file in Excel, so writing all of
 * it back would put stale values over newer ones. The Save button says how
 * many changes it is about to make, as the log form's does.
 */
struct ExtraFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let day: String
    /* Set when this is correcting an extra already saved rather than adding one. */
    var editing: ExtraSummary?
    /* Told once the correction is queued, so the screen behind can step out of the way. */
    var onSaved: (() -> Void)?

    @State private var date: Date
    @State private var activity: String
    @State private var what: String
    @State private var duration: String
    @State private var distance: String
    @State private var avgHr: String
    @State private var effort: String
    @State private var notes: String
    @State private var isTraining: Bool?
    @State private var problem: String?
    /* What the boxes held when the form opened. Only what differs from this is written. */
    @State private var openedWith: [String: String] = [:]
    /* The day's workouts from Apple Health — what Garmin sent — offered as for a session. */
    @State private var healthWorkouts: [HealthWorkout] = []
    @State private var healthChecked = false
    @State private var loaded = false

    init(day: String, editing: ExtraSummary? = nil, onSaved: (() -> Void)? = nil) {
        self.day = day
        self.editing = editing
        self.onSaved = onSaved
        _date = State(initialValue: parseDayKey(editing?.dayKey ?? day) ?? Date())
        _activity = State(initialValue: editing?.activity ?? "walk")
        _what = State(initialValue: editing?.what ?? "")
        _duration = State(initialValue: editing?.minutes.map(jsNumberString) ?? "")
        _distance = State(initialValue: editing?.distance ?? "")
        _avgHr = State(initialValue: editing?.avgHr ?? "")
        _effort = State(initialValue: editing?.effort ?? "")
        _notes = State(initialValue: editing?.notes ?? "")
        _isTraining = State(initialValue: editing?.isTraining)
    }

    private var chosen: Activity { Extras.activity(activity) }
    private var training: Bool { isTraining ?? (chosen.kind == "training") }
    private var canSave: Bool {
        parseDuration(duration) != nil || !what.trimmingCharacters(in: .whitespaces).isEmpty
            || !notes.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /*
     * The boxes as the sheet would hold them, so that typing 1:15 over 75 is
     * not a change and neither is 4,2 over 4.2: what counts as changed is what
     * would reach a different cell value.
     */
    private var values: [String: String] {
        [ExtraField.date: dayKey(date) ?? "",
         ExtraField.activity: activity,
         ExtraField.what: trimmed(what),
         ExtraField.duration: parseDuration(duration).map { jsNumberString(jsRound($0 / 60)) } ?? "",
         ExtraField.distance: number(distance).map(jsNumberString) ?? "",
         ExtraField.avgHr: number(avgHr).map(jsNumberString) ?? "",
         ExtraField.effort: number(effort).map(jsNumberString) ?? "",
         ExtraField.isTraining: training ? "Yes" : "No",
         ExtraField.notes: trimmed(notes)]
    }

    private var changes: [String] {
        guard editing != nil, !openedWith.isEmpty else { return [] }
        return values.filter { openedWith[$0.key] != $0.value }.map(\.key).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labelled("When") {
                        DatePicker("When", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                    }
                    // From Apple Health, as on a session's form: Use fills time, distance
                    // and heart rate — never a pace — and nothing is saved until Save.
                    if !healthWorkouts.isEmpty {
                        HealthSuggestions(workouts: healthWorkouts, disciplineId: activity,
                                          note: "Fills time, distance and heart rate. Nothing is saved until you press Save.") { picked in
                            useHealth(picked)
                        }
                    } else if healthChecked && HealthImport.shared.inUse {
                        Text("Nothing in Apple Health for this day.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    labelled("What kind of thing") {
                        Picker("Activity", selection: $activity) {
                            ForEach(Extras.defaultActivities) { Text($0.label).tag($0.id) }
                        }
                        .pickerStyle(.menu).tint(Theme.today)
                        .onChange(of: activity) { _, _ in isTraining = nil }
                    }
                    field("What it was", id: ExtraField.what, text: $what, placeholder: "e.g. Dog walk along the river", keys: .default)
                    field("Duration", id: ExtraField.duration, text: $duration, placeholder: "e.g. 35", keys: .default,
                          hint: "Just a number means minutes. Or 1:15, 1h20, 90min.")
                    if Extras.wantsMetrics(activity) {
                        field("Distance (km)", id: ExtraField.distance, text: $distance, placeholder: "e.g. 4.2", keys: .decimalPad)
                        field("Average heart rate (bpm)", id: ExtraField.avgHr, text: $avgHr, placeholder: "", keys: .numberPad)
                        field("Effort (1–10)", id: ExtraField.effort, text: $effort, placeholder: "1 easy — 10 all out", keys: .numberPad)
                    }
                    labelled("Counts as training?") {
                        Picker("Counts as training", selection: Binding(get: { training }, set: { isTraining = $0 })) {
                            Text("No — it does not add load").tag(false)
                            Text("Yes — count it as training").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    labelled("Notes") {
                        TextField("Anything worth remembering", text: $notes, axis: .vertical)
                            .lineLimit(3...6).padding(12).background(box(changed: changes.contains(ExtraField.notes)))
                    }
                    if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger) }
                }
                .padding(16).padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .task(id: dayKey(date) ?? "") { await loadHealth() }
            .navigationTitle(editing == nil ? "Extra activity" : "Adjust logged data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                openedWith = values
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(saveLabel).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(Theme.today)
                .disabled(editing == nil ? !canSave : changes.isEmpty)
                .accessibilityIdentifier("extra-save")
                .padding(16).background(Theme.bg)
            }
        }
    }

    private var saveLabel: String {
        guard editing != nil else { return "Save it" }
        let n = changes.count
        return n == 0 ? "Nothing changed yet" : "Save \(n) change\(n == 1 ? "" : "s")"
    }

    /* The chosen day's workouts, the ones of this activity's kind first. */
    private func loadHealth() async {
        guard HealthImport.shared.inUse || ProcessInfo.processInfo.environment["AMSWS_FAKE_HEALTH"] != nil,
              let key = dayKey(date) else { return }
        let all = await HealthImport.shared.workouts(on: key)
        let mine = Self.healthSport(for: activity)
        healthWorkouts = all.filter { $0.sport == mine } + all.filter { $0.sport != mine }
        healthChecked = true
    }

    /* The Health sport an extra's activity would show up as. */
    static func healthSport(for activity: String) -> String {
        switch activity {
        case "swim", "bike", "run", "strength": return activity
        case "mobility", "yoga": return "mobility"
        case "walk", "hike": return "walk"
        default: return "other"
        }
    }

    /*
     * Fill the boxes from what Garmin sent. A new extra also takes the workout's
     * kind when Health knows it; a saved one keeps the kind it has. Distance and
     * heart rate only where this kind of activity has those boxes.
     */
    private func useHealth(_ w: HealthWorkout) {
        if editing == nil {
            switch w.sport {
            case "swim", "bike", "run", "strength", "mobility", "walk": activity = w.sport
            default: break
            }
        }
        duration = String(Int((w.seconds / 60).rounded()))
        if Extras.wantsMetrics(activity) {
            if let metres = w.metres, metres > 0 { distance = jsNumberString((metres / 1000 * 100).rounded() / 100) }
            if let hr = w.avgHr { avgHr = String(Int(hr.rounded())) }
        }
    }

    private func save() {
        guard let key = dayKey(date) else { return }
        if let original = editing {
            let fields = changes
            guard !fields.isEmpty else { return }
            store.editExtra(original, entry(on: key, ref: original.ref), fields: fields)
            onSaved?()
            dismiss()
            return
        }
        guard canSave else { problem = "Give it at least a duration or a description."; return }
        store.logExtra(entry(on: key, ref: ""))
        dismiss()
    }

    private func entry(on key: String, ref: String) -> ExtraEntry {
        var entry = ref.isEmpty ? ExtraEntry(date: key, activity: activity)
                                : ExtraEntry(date: key, activity: activity, ref: ref)
        entry.what = trimmed(what)
        entry.minutes = parseDuration(duration).map { jsRound($0 / 60) }
        entry.distance = number(distance)
        entry.avgHr = number(avgHr)
        entry.effort = number(effort)
        entry.isTraining = training
        entry.notes = trimmed(notes)
        return entry
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /* parseFloat with a decimal comma allowed, as the web app's toNumber. */
    private func number(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let n = Double(t.replacingOccurrences(of: ",", with: ".")) ?? jsParseFloat(t.replacingOccurrences(of: ",", with: "."))
        return n.isFinite ? n : nil
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            content()
        }
    }

    private func field(_ label: String, id: String, text: Binding<String>, placeholder: String,
                       keys: UIKeyboardType, hint: String = "") -> some View {
        labelled(label) {
            TextField(placeholder, text: text).keyboardType(keys).autocorrectionDisabled()
                .padding(12).background(box(changed: changes.contains(id)))
                .accessibilityIdentifier("extra-field-" + id)
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(Theme.secondary) }
        }
    }

    /* A box you have altered is edged in the app's green, as the log form's is. */
    private func box(changed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(changed ? Theme.today : Theme.border, lineWidth: changed ? 2 : 1))
    }
}

/* Everything outside the plan, newest first — an extra used to be visible only on its own day. */
struct ExtrasListView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var open: ExtraSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let all = store.allExtras
                if all.isEmpty {
                    Text("Nothing outside the plan yet.").foregroundStyle(Theme.secondary).padding(.top, 24)
                }
                ForEach(grouped(all), id: \.0) { day, list in
                    SectionHeading(text: Dates.long(day))
                    ForEach(list) { x in
                        Button { open = x } label: { ExtraCard(extra: x) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16).padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Extra activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canLog {
                ToolbarItem(placement: .primaryAction) { Button("Add") { adding = true } }
            }
        }
        .sheet(isPresented: $adding) { ExtraFormView(day: store.today).environmentObject(store) }
        .sheet(item: $open) { x in ExtraDetailView(extra: x).environmentObject(store) }
    }

    private func grouped(_ list: [ExtraSummary]) -> [(String, [ExtraSummary])] {
        var out: [(String, [ExtraSummary])] = []
        for x in list {
            if let last = out.last, last.0 == x.dayKey { out[out.count - 1].1.append(x) } else { out.append((x.dayKey, [x])) }
        }
        return out
    }
}
