import SwiftUI
import WorkoutCore

/*
 * Search on the Sessions page (round 28, pick 21). The matching is Core's
 * (`SessionSearch`); this builds the entries from the plan and draws the field
 * and the answer, with the app's own session and extra rows.
 */

extension Store {
    /* Every session still in the plan and every extra, as plain words for the search. */
    func searchEntries() -> [SearchEntry] {
        guard let view else { return [] }
        var out: [SearchEntry] = []
        for w in view.plan where w.discipline.id != "rest" {
            let group: SearchEntry.Group = w.state == .done ? .done : (w.state == .missed ? .missed : .toCome)
            var description = w.sections.map { $0.text }
            if !w.planned.description.isEmpty { description.append(w.planned.description) }
            if !w.planned.intensity.isEmpty { description.append(w.planned.intensity) }
            var notes = [w.results["notes"]?.text, w.pending?.notes].compactMap { $0 }.filter { !$0.isEmpty }
            if let first = notes.first, notes.count == 2, notes[1] == first { notes.removeLast() }
            // What the "Done" cell holds when it is more than a tick: his own words about a miss or a change.
            let doneText = w.results["done"]?.text ?? ""
            let letters = doneText.filter(\.isLetter).count
            let logged = letters >= 5 && !["done", "completed", "missed"].contains(normalise(doneText)) ? doneText : ""
            out.append(SearchEntry(id: "s:" + w.key, kind: .session, dayKey: w.dayKey, group: group,
                                   sportId: w.discipline.id, sportLabel: w.discipline.label, title: w.title,
                                   description: description.joined(separator: "\n"),
                                   notes: notes.joined(separator: "\n"), logged: logged))
        }
        for x in view.extras {
            out.append(SearchEntry(id: "x:" + x.id, kind: .extra, dayKey: x.dayKey, group: .done,
                                   sportId: x.activity, sportLabel: x.label + " extra",
                                   title: x.what.isEmpty ? x.label : x.what, notes: x.notes))
        }
        return out
    }
}

/* The field. On the Mac, \u{2318}F puts the cursor in it. */
struct SessionSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    /* A picture switch: AMSWS_SEARCH=<word> opens the Sessions page already searching for it. */
    static var startWords: String {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_SEARCH"] ?? ""
        #else
        return ""
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Search sessions", text: $query)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("session-search")
            if !query.isEmpty {
                Button("Clear") { query = "" }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("search-clear")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.plan.opacity(focused ? 0.9 : 0.35), lineWidth: focused ? 2 : 1))
        .background {
            // The keyboard shortcut lives on a button nobody sees.
            Button("Search sessions") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

/* The answer: To come, Done and Missed groups, newest first, each row the app's own row with the found words under it. */
struct SessionSearchResults: View {
    @EnvironmentObject var store: Store
    let query: String
    let openExtra: (ExtraSummary) -> Void

    var body: some View {
        let groups = SessionSearch.results(query, in: store.searchEntries())
        VStack(alignment: .leading, spacing: 12) {
            if groups.isEmpty {
                Text("Nothing found for '\(query.trimmingCharacters(in: .whitespaces))'.")
                    .font(.callout).foregroundStyle(Theme.secondary).padding(.top, 12)
                    .accessibilityIdentifier("search-empty")
            }
            let flat = groups.flatMap(\.hits)
            ForEach(groups, id: \.group) { group in
                SectionHeading(text: group.group.rawValue)
                ForEach(group.hits) { hit in
                    let n = flat.firstIndex(where: { $0.id == hit.id }) ?? 0
                    row(hit)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("search-result-\(n)")
                }
            }
        }
    }

    @ViewBuilder private func row(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch hit.entry.kind {
            case .session:
                if let w = store.workout(String(hit.entry.id.dropFirst(2))), let mapping = store.mapping {
                    NavigationLink(value: w.key) {
                        SessionCard(workout: w, mapping: mapping, showDay: true)
                    }
                    .buttonStyle(.plain)
                }
            case .extra:
                if let x = store.allExtras.first(where: { "x:" + $0.id == hit.entry.id }) {
                    Button { openExtra(x) } label: { ExtraCard(extra: x) }
                        .buttonStyle(.plain)
                }
            }
            let line = (hit.entry.kind == .extra ? Dates.short(hit.entry.dayKey) + " \u{00B7} " : "") + hit.found
            if !line.isEmpty {
                Text(line).font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}
