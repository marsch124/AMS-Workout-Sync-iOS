import SwiftUI
import WorkoutCore

/*
 * A test result typed in: threshold pulse, bike power, swim pace, weight, the
 * day or days, a few words. The boxes are read in Core (TestEntry); when
 * something is missing or cannot be read, Save stays on the page and says so
 * in one red line. Save is always full colour.
 */
struct TestEntryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var fields = TestEntryFields()
    @State private var first = Date()
    @State private var last = Date()
    @State private var started = false
    @State private var saved = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var lastTest: TestResult? { TestEntry.last(of: store.tests) }
    private let utc = TimeZone(identifier: "UTC") ?? .current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if lastTest != nil {
                        Button("Same as the last test") {
                            fields = TestEntry.sameAs(lastTest!, into: fields)
                            problem = nil
                        }
                        .settingsButton(tint: Theme.today)
                        .accessibilityIdentifier("test-same")
                    }
                    fieldRow("Threshold pulse", unit: "beats a minute") {
                        numberBox("160", text: $fields.lthr, id: "test-lthr", pad: .decimalPad)
                    }
                    fieldRow("Bike power (FTP)", unit: "watts") {
                        numberBox("200", text: $fields.ftp, id: "test-ftp", pad: .decimalPad)
                    }
                    fieldRow("Swim pace per 100 m", unit: "min:sec") {
                        numberBox("1:50", text: $fields.swim, id: "test-swim", pad: .numbersAndPunctuation)
                    }
                    fieldRow("Weight", unit: "kg") {
                        numberBox("70", text: $fields.weight, id: "test-weight", pad: .decimalPad)
                    }
                    HStack(spacing: 8) {
                        Text("First day").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        DatePicker("First day", selection: $first, displayedComponents: .date)
                            .labelsHidden().environment(\.timeZone, utc)
                            .accessibilityIdentifier("test-first")
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text("Last day").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        DatePicker("Last day", selection: $last, in: first..., displayedComponents: .date)
                            .labelsHidden().environment(\.timeZone, utc)
                            .accessibilityIdentifier("test-last")
                        Spacer(minLength: 0)
                    }
                    labelled("Notes") {
                        TextField("Anything worth keeping", text: $fields.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .focused($focused)
                            .padding(10).background(box)
                            .accessibilityIdentifier("test-notes")
                    }
                    Text(TestEntry.becomesLine(existing: store.tests))
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("test-becomes")
                    Text("Leave a box empty if that part was not tested; the zones keep the last number there is.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Enter a test result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("test-cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }.accessibilityIdentifier("test-keyboard-done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("test-problem")
                    }
                    Button(action: save) {
                        Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.today)
                    .accessibilityIdentifier("test-save")
                }
                .padding(16)
                .background(Theme.bg)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if let d = parseDayKey(store.today) { first = d; last = d }
        }
        .onChange(of: first) { _, new in if last < new { last = new } }
    }

    private func save() {
        guard !saved else { return }
        var f = fields
        f.firstDay = dayKey(first) ?? ""
        f.lastDay = dayKey(last) ?? ""
        switch TestEntry.make(f, existing: store.tests) {
        case .failure(let p):
            problem = p.words
        case .success(let test):
            if store.recordTest(test) { saved = true; dismiss() } else { problem = "The test could not be saved. Nothing was changed." }
        }
    }

    private func numberBox(_ hint: String, text: Binding<String>, id: String, pad: UIKeyboardType) -> some View {
        TextField(hint, text: text)
            .keyboardType(pad)
            .autocorrectionDisabled()
            .focused($focused)
            .padding(10).background(box)
            .accessibilityIdentifier(id)
    }

    /* One row per box: the name, the box right beside it, the unit in grey after it. */
    private func fieldRow<Content: View>(_ title: String, unit: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            content().frame(maxWidth: 110)
            Text(unit).font(.footnote).foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/* The tests for the zones page: the ones with numbers, newest first; then one compact card for those still to come. */
struct TestsList: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let done = Array(store.tests.filter(\.hasNumbers).reversed())
        let waiting = store.tests.filter { !$0.hasNumbers }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(done, id: \.name) { test in
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TestEntry.cleanLabel(test)).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(numbers(test)).font(.subheadline).foregroundStyle(Theme.text)
                        if !test.notes.isEmpty {
                            Text(test.notes).font(.footnote).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("test-row")
            }
            if !waiting.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Still to come").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        ForEach(waiting, id: \.name) { test in
                            Text(TestEntry.cleanLabel(test)).font(.footnote).foregroundStyle(Theme.secondary)
                                .accessibilityIdentifier("test-row-waiting")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tests-list")
    }

    private func numbers(_ t: TestResult) -> String {
        var parts: [String] = []
        if let x = t.lthr { parts.append("Threshold pulse " + jsNumberString(x)) }
        if let x = t.ftp { parts.append("Bike power " + jsNumberString(x) + " W") }
        if let x = t.css { parts.append("Swim pace " + TestEntry.swimText(x)) }
        if let x = t.weight { parts.append("Weight " + jsNumberString(x) + " kg") }
        return parts.joined(separator: " \u{00B7} ")
    }
}
