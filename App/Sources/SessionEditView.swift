import SwiftUI
import WorkoutCore

/*
 * One page for changing a planned session and for adding a new one. Laid out
 * like the log form: small labelled boxes, Cancel at the top, the full-colour
 * Save at the bottom — never grey; when something is missing it says so in red.
 */
struct SessionEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /* The session being changed; nil when adding. */
    let key: String?
    /* Told after the session was taken out, so its own page can close. */
    var onRemoved: () -> Void = {}

    @State private var day: Date
    @State private var sport: String
    @State private var title: String
    @State private var minutes: String
    @State private var zone: String
    @State private var purpose: String
    @State private var isKey: Bool
    @State private var problem: String?
    @State private var asking = false
    @State private var repeatUntil: String?   // nil = does not repeat (the Repeat row)
    @State private var saved = false          // a second tap on Save while the page closes adds nothing again
    @FocusState private var focused: Bool
    private let initial: SessionDraft

    static let sports: [Discipline] = Disciplines.five + Disciplines.compound + [Disciplines.rest, Disciplines.other]

    init(key: String?, draft: SessionDraft, onRemoved: @escaping () -> Void = {}) {
        self.key = key
        self.onRemoved = onRemoved
        self.initial = draft
        _day = State(initialValue: parseDayKey(draft.dayKey) ?? Date())
        _sport = State(initialValue: draft.sport)
        _title = State(initialValue: draft.title)
        _minutes = State(initialValue: draft.minutes.map { jsNumberString($0) } ?? "")
        _zone = State(initialValue: draft.intensity)
        _purpose = State(initialValue: draft.purpose)
        _isKey = State(initialValue: draft.isKey)
    }

    private var adding: Bool { key == nil }
    @ObservedObject private var keeper = SuggestionKeeper.shared
    /* The grey line, worked out a moment after he stops typing, never on every keystroke. */
    @State private var ownNote: String?

    /* The page as it stands, for the grey line; the same draft Save would make. */
    private var liveDraft: SessionDraft {
        let typed = minutes.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return SessionDraft(dayKey: dayKey(day) ?? initial.dayKey, sport: sport,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            minutes: Double(typed) ?? (typed.isEmpty ? nil : initial.minutes),
                            intensity: zone.trimmingCharacters(in: .whitespacesAndNewlines),
                            purpose: purpose, isKey: isKey)
    }
    private var current: Discipline { Self.sports.first { $0.id == sport } ?? Disciplines.other }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if adding {
                        FavouritesBlock { f in
                            sport = f.sport; title = f.title; zone = f.zone; purpose = f.purpose
                            minutes = f.minutes.map { jsNumberString($0) } ?? ""
                        }
                    }
                    labelled("Day") {
                        DatePicker("Day", selection: $day, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
                            .accessibilityIdentifier("edit-day")
                    }
                    labelled("Sport") {
                        Menu {
                            ForEach(Self.sports, id: \.id) { d in
                                Button(d.label) { sport = d.id }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Glyph(name: Theme.icon(current), size: 16)
                                    .foregroundStyle(Theme.sportInk(current.id))
                                Text(current.label).font(.body).foregroundStyle(Theme.text)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(box)
                        }
                        .accessibilityIdentifier("edit-sport")
                    }
                    labelled("What you do") {
                        TextField("What the session is", text: $title, axis: .vertical)
                            .lineLimit(1...2)
                            .focused($focused)
                            .padding(10).background(box(title != initial.title))
                            .accessibilityIdentifier("edit-title")
                    }
                    HStack(alignment: .top, spacing: 12) {
                        labelled("Length (minutes)") {
                            TextField("40", text: $minutes)
                                .keyboardType(.decimalPad)
                                .focused($focused)
                                .padding(10).background(box(minutes != (initial.minutes.map { jsNumberString($0) } ?? "")))
                                .accessibilityIdentifier("edit-minutes")
                        }
                        labelled("Zone or effort") {
                            TextField("Like Z2 or Z4–Z5", text: $zone)
                                .autocorrectionDisabled()
                                .focused($focused)
                                .padding(10).background(box(zone != initial.intensity))
                                .accessibilityIdentifier("edit-zone")
                        }
                    }
                    labelled("Purpose") {
                        TextField("What it is for", text: $purpose, axis: .vertical)
                            .lineLimit(2...6)
                            .focused($focused)
                            .padding(10).background(box(purpose != initial.purpose))
                            .accessibilityIdentifier("edit-purpose")
                    }
                    Toggle("Key session", isOn: $isKey)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        .tint(Theme.plan)
                        .accessibilityIdentifier("edit-key")

                    if adding { RepeatSection(base: liveDraft, until: $repeatUntil).id("repeat-section") }

                    if !adding {
                        Button("Take out of the plan") { asking = true }
                            .settingsButton(tint: Theme.danger)
                            .padding(.top, 10)
                            .accessibilityIdentifier("edit-remove")
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            #if DEBUG
            .onAppear {
                if adding, ProcessInfo.processInfo.environment["AMSWS_REPEAT"] != nil {
                    repeatUntil = RepeatSession.defaultUntil(liveDraft.dayKey, store: store)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { proxy.scrollTo("repeat-section", anchor: .top) }
                }
            }
            #endif
            }
            .navigationTitle(adding ? "New session" : "Change session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("edit-cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }.accessibilityIdentifier("edit-keyboard-done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    // His own change against the rule book: one grey line, never a block.
                    OwnEditNote(text: ownNote)
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("edit-problem")
                    }
                    Button(action: save) {
                        Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                    .accessibilityIdentifier("edit-save")
                    // On the button that is always there: the note itself may be empty.
                    .task(id: liveDraft) {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        ownNote = keeper.note(forChanging: key, to: liveDraft)
                    }
                }
                .padding(16)
                .background(Theme.bg)
            }
            .confirmationDialog("Take this session out of the plan?", isPresented: $asking, titleVisibility: .visible) {
                Button("Take out", role: .destructive) { remove() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("It stays in Settings › Changes to the plan, where Undo brings it back.")
            }
        }
    }

    private func box(_ changed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(changed && !adding ? Theme.today : Theme.border, lineWidth: changed && !adding ? 2 : 1))
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func labelled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        let words = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty {
            problem = "Write a few words for the session first."
            return
        }
        let typed = minutes.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if !typed.isEmpty, Double(typed) == nil {
            problem = "The length must be a number of minutes."
            return
        }
        let draft = SessionDraft(dayKey: dayKey(day) ?? "", sport: sport, title: words,
                                 minutes: typed.isEmpty ? nil : Double(typed),
                                 intensity: zone, purpose: purpose, isKey: isKey)
        // The keyboard goes first: a page closed with it still up left the
        // swipe pages underneath stuck half-way between two tabs.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if let key {
            store.changeSession(key, to: draft)
            dismiss()
        } else if let until = repeatUntil {
            guard !saved else { return }
            if RepeatSession.save(draft, until: until, store: store, includingBase: true) { saved = true; dismiss() }
            else { problem = store.lastProblem ?? "The sessions could not be added." }
        } else if store.addSession(draft) != nil {
            dismiss()
        } else {
            problem = store.lastProblem ?? "The session could not be added."
        }
    }

    private func remove() {
        guard let key else { return }
        store.removeSession(key)
        dismiss()
        onRemoved()
    }
}
