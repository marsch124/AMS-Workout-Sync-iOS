import SwiftUI
import WorkoutCore

/*
 * Something the plan did not ask for. It goes to the Extras sheet, never into
 * the plan, and "Counts as training" starts from the activity's kind — a walk
 * does not, a run does — but stays yours to override: a four-hour hike is
 * load whatever the list says.
 */
struct ExtraFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let day: String

    @State private var date: Date
    @State private var activity = "walk"
    @State private var what = ""
    @State private var duration = ""
    @State private var distance = ""
    @State private var avgHr = ""
    @State private var effort = ""
    @State private var notes = ""
    @State private var isTraining: Bool? = nil
    @State private var problem: String?

    init(day: String) {
        self.day = day
        _date = State(initialValue: parseDayKey(day) ?? Date())
    }

    private var chosen: Activity { Extras.activity(activity) }
    private var training: Bool { isTraining ?? (chosen.kind == "training") }
    private var canSave: Bool {
        parseDuration(duration) != nil || !what.trimmingCharacters(in: .whitespaces).isEmpty
            || !notes.trimmingCharacters(in: .whitespaces).isEmpty
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
                    labelled("What kind of thing") {
                        Picker("Activity", selection: $activity) {
                            ForEach(Extras.defaultActivities) { Text($0.label).tag($0.id) }
                        }
                        .pickerStyle(.menu).tint(Theme.today)
                        .onChange(of: activity) { _, _ in isTraining = nil }
                    }
                    field("What it was", text: $what, placeholder: "e.g. Dog walk along the river", keys: .default)
                    field("Duration", text: $duration, placeholder: "e.g. 35", keys: .default,
                          hint: "Just a number means minutes. Or 1:15, 1h20, 90min.")
                    if Extras.wantsMetrics(activity) {
                        field("Distance (km)", text: $distance, placeholder: "e.g. 4.2", keys: .decimalPad)
                        field("Average heart rate (bpm)", text: $avgHr, placeholder: "", keys: .numberPad)
                        field("Effort (1–10)", text: $effort, placeholder: "1 easy — 10 all out", keys: .numberPad)
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
                            .lineLimit(3...6).padding(12).background(box)
                    }
                    if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger) }
                }
                .padding(16).padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Extra activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Save it").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(Theme.today)
                .disabled(!canSave)
                .padding(16).background(Theme.bg)
            }
        }
    }

    private func save() {
        guard let dayKey = dayKey(date) else { return }
        let seconds = parseDuration(duration)
        guard canSave else { problem = "Give it at least a duration or a description."; return }
        var entry = ExtraEntry(date: dayKey, activity: activity)
        entry.what = what.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.minutes = seconds.map { jsRound($0 / 60) }
        entry.distance = number(distance)
        entry.avgHr = number(avgHr)
        entry.effort = number(effort)
        entry.isTraining = training
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.logExtra(entry)
        dismiss()
    }

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

    private func field(_ label: String, text: Binding<String>, placeholder: String, keys: UIKeyboardType, hint: String = "") -> some View {
        labelled(label) {
            TextField(placeholder, text: text).keyboardType(keys).autocorrectionDisabled().padding(12).background(box)
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(Theme.secondary) }
        }
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
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
        .sheet(item: $open) { x in ExtraDetailView(extra: x) }
    }

    private func grouped(_ list: [ExtraSummary]) -> [(String, [ExtraSummary])] {
        var out: [(String, [ExtraSummary])] = []
        for x in list {
            if let last = out.last, last.0 == x.dayKey { out[out.count - 1].1.append(x) } else { out.append((x.dayKey, [x])) }
        }
        return out
    }
}
