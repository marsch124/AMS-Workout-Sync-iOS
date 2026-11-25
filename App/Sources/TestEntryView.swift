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
                    HStack(alignment: .top, spacing: 12) {
                        labelled("Threshold pulse (beats a minute)") {
                            numberBox("160", text: $fields.lthr, id: "test-lthr", pad: .decimalPad)
                        }
                        labelled("Bike power FTP (watts)") {
                            numberBox("200", text: $fields.ftp, id: "test-ftp", pad: .decimalPad)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        labelled("Swim pace per 100 m (m:ss)") {
                            numberBox("1:50", text: $fields.swim, id: "test-swim", pad: .numbersAndPunctuation)
                        }
                        labelled("Weight (kg)") {
                            numberBox("70", text: $fields.weight, id: "test-weight", pad: .decimalPad)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        labelled("First day") {
                            DatePicker("First day", selection: $first, displayedComponents: .date)
                                .labelsHidden().environment(\.timeZone, utc)
                                .accessibilityIdentifier("test-first")
                        }
                        labelled("Last day") {
                            DatePicker("Last day", selection: $last, in: first..., displayedComponents: .date)
                                .labelsHidden().environment(\.timeZone, utc)
                                .accessibilityIdentifier("test-last")
                        }
                    }
                    labelled("Notes") {
                        TextField("Anything worth keeping", text: $fields.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .focused($focused)
                            .padding(10).background(box)
                            .accessibilityIdentifier("test-notes")
                    }
                    Text("Leave a box empty if that part was not tested; the zones keep the last number there is.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
                .padding(16).padding(.bottom, 90)
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
        .onChange(of: first) { _, new in if last < new { last = new } }
    }

    private func save() {
        var f = fields
        f.firstDay = dayKey(first) ?? ""
        f.lastDay = dayKey(last) ?? ""
        switch TestEntry.make(f, existing: store.tests) {
        case .failure(let p):
            problem = p.words
        case .success(let test):
            if store.recordTest(test) { dismiss() } else { problem = "The test could not be saved. Nothing was changed." }
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

/* The tests, newest first, for the zones page. */
struct TestsList: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(store.tests.reversed()), id: \.name) { test in
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(test.label).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        if test.hasNumbers {
                            Text(numbers(test)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text)
                        } else {
                            Text("No numbers entered yet").font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        if !test.notes.isEmpty {
                            Text(test.notes).font(.footnote).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("test-row")
            }
        }
        .accessibilityIdentifier("tests-list")
    }

    private func numbers(_ t: TestResult) -> String {
        var parts: [String] = []
        if let x = t.lthr { parts.append("Pulse " + jsNumberString(x)) }
        if let x = t.ftp { parts.append("FTP " + jsNumberString(x) + " W") }
        if let x = t.css { parts.append("Swim " + TestEntry.swimText(x)) }
        if let x = t.weight { parts.append(jsNumberString(x) + " kg") }
        return parts.joined(separator: "  ·  ")
    }
}
