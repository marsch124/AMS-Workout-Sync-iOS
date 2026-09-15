import SwiftUI
import WorkoutCore

/*
 * "How did it go?" — and, on a session already recorded, "Adjust logged data".
 *
 * The form opens filled in with what the sheet holds. Saving writes only the
 * boxes that were altered (changedOnly), so correcting one number never puts
 * a value the phone read before the last Excel edit back over a newer one.
 * The Save button says how many changes it is about to write, and is disabled
 * while that number is nought.
 */
struct LogFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    let mapping: Mapping

    @State private var values: [String: String] = [:]
    @State private var openedWith: [String: String] = [:]
    // Once you have asked for the full set, you probably want it every time.
    @AppStorage("log.showAllFields") private var showAll = false
    @State private var distanceUnit: String
    @State private var loaded = false
    @State private var healthWorkouts: [HealthWorkout] = []
    @State private var healthChecked = false

    init(workout: Workout, mapping: Mapping) {
        self.workout = workout
        self.mapping = mapping
        _distanceUnit = State(initialValue: LogForm.distanceUnit(for: workout.discipline.id))
    }

    private var fields: (primary: [FormField], all: [FormField]) { LogForm.fields(for: workout, mapping) }
    private var shown: [FormField] { showAll ? fields.all : fields.primary }
    private var hiddenCount: Int { fields.all.count - fields.primary.count }
    private var changes: [String: String] { LogForm.changedOnly(values, openedWith: openedWith) }
    private var adjusting: Bool { workout.loggedInSheet || store.isWaiting(workout.key) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(workout.discipline.label.uppercased() + " · " + Dates.short(workout.dayKey))
                        .font(.caption.weight(.bold)).tracking(0.6)
                        .foregroundStyle(Theme.sportInk(workout.discipline.id))
                    Text(workout.title).font(.headline).foregroundStyle(Theme.secondary).lineLimit(2)

                    if !healthWorkouts.isEmpty {
                        HealthSuggestions(workouts: healthWorkouts, disciplineId: workout.discipline.id) { picked in
                            for (id, value) in picked.formValues(for: workout.discipline.id) { values[id] = value }
                            if workout.discipline.id == "swim" { distanceUnit = "m" }
                        }
                    } else if healthChecked && HealthImport.shared.status == .asked {
                        Text("Nothing in Apple Health for this day and sport.").font(.caption).foregroundStyle(Theme.secondary)
                    }

                    ForEach(shown) { field in
                        FieldBox(field: field,
                                 text: binding(field.id),
                                 changed: changes[field.id] != nil,
                                 unitPicker: field.id == "actualDistance" ? $distanceUnit : nil)
                    }

                    if !showAll && hiddenCount > 0 {
                        Button("Show \(hiddenCount) more field\(hiddenCount == 1 ? "" : "s")") { showAll = true }
                            .font(.subheadline.weight(.semibold)).tint(Theme.today)
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(adjusting ? "Adjust logged data" : "How did it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(saveLabel).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(Theme.today)
                .disabled(changes.isEmpty)
                .padding(16)
                .background(Theme.bg)
            }
            .onAppear(perform: load)
            .task {
                guard HealthImport.shared.status == .asked || ProcessInfo.processInfo.environment["AMSWS_FAKE_HEALTH"] != nil else { return }
                let all = await HealthImport.shared.workouts(on: workout.dayKey)
                let sport = workout.discipline.id
                healthWorkouts = all.filter { sport == "other" || sport == "brick" || $0.sport == sport || (sport == "run" && $0.sport == "walk") }
                healthChecked = true
            }
        }
    }

    private var saveLabel: String {
        let n = changes.count
        if n == 0 { return "Nothing changed yet" }
        return "Save \(n) change\(n == 1 ? "" : "s")"
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { values[id] ?? "" }, set: { values[id] = $0 })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let waiting = store.queue.last { $0.workoutKey == workout.key }?.entry
        var filled: [String: String] = [:]
        for field in fields.all {
            filled[field.id] = LogForm.recordedValue(workout, field.id, mapping, waiting: waiting)
        }
        if let unit = waiting?.distanceUnit, !unit.isEmpty { distanceUnit = unit }
        values = filled
        openedWith = filled
        // A session with values in the extra fields opens showing them.
        let primaryIds = Set(fields.primary.map(\.id))
        if fields.all.contains(where: { !primaryIds.contains($0.id) && !(filled[$0.id] ?? "").isEmpty }) { showAll = true }
    }

    private func save() {
        let entry = LogForm.entry(from: changes, distanceUnit: distanceUnit)
        store.log(workout, entry)
        dismiss()
    }
}

struct FieldBox: View {
    let field: FormField
    @Binding var text: String
    let changed: Bool
    var unitPicker: Binding<String>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(field.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if !field.unit.isEmpty, unitPicker == nil {
                    Text("(\(field.unit))").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if let unitPicker {
                    Picker("Unit", selection: unitPicker) {
                        Text("km").tag("km")
                        Text("m").tag("m")
                    }
                    .pickerStyle(.segmented).frame(width: 110)
                }
            }
            if field.keys == .multiline {
                TextField(field.placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(box)
            } else if field.id == "rpe" {
                HStack(alignment: .center, spacing: 12) {
                    TextField("1–10", text: $text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(12).frame(width: 82).background(box)
                    Text(LogForm.rpeNote(text).isEmpty ? field.placeholder : LogForm.rpeNote(text))
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
            } else {
                TextField(field.placeholder, text: $text)
                    .keyboardType(field.keys == .decimal ? .decimalPad : (field.keys == .digits ? .numberPad : .default))
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(box)
            }
            if !field.hint.isEmpty {
                Text(field.hint).font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(changed ? Theme.today : Theme.border, lineWidth: changed ? 2 : 1))
    }
}


/* The day's workouts from Apple Health, one tap each to fill the boxes. */
struct HealthSuggestions: View {
    let workouts: [HealthWorkout]
    let disciplineId: String
    let use: (HealthWorkout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FROM APPLE HEALTH").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.secondary)
            ForEach(workouts) { w in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(w.typeName + " · " + w.start.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(w.summary + " · " + w.source).font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("Use") { use(w) }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(Theme.today)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
            }
            Text("Fills the boxes; nothing is saved until you press Save.").font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}
