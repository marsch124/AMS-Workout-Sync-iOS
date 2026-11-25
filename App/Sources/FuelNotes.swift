import SwiftUI
import WorkoutCore

/* One answered "Stomach OK?" with the session it belongs to. */
struct FuelEntry: Identifiable, Equatable {
    var id: String
    var day: String
    var title: String
    var seconds: Double?
    var note: StomachNote
}

/*
 * "Fuel notes" — every answer to "Stomach OK?", newest first, under a head card that counts them.
 * For learning his own race fuel; it never advises, and the three answers have no colours of their own.
 */
struct FuelNotesPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    /* Invented entries for a picture; nil = the shelf's own. */
    var sample: [FuelEntry]?

    private var entries: [FuelEntry] {
        if let sample { return sample }
        guard let mapping = store.mapping else { return [] }
        return shelf.keys(prefix: LogExtrasKeys.prefix).compactMap { k in
            guard let wk = LogExtrasKeys.workoutKey(from: k, fact: "stomach"), let w = store.workout(wk),
                  let n = shelf.value(StomachNote.self, for: k) else { return nil }
            return FuelEntry(id: wk, day: w.dayKey, title: w.title,
                             seconds: ShareText.actualSeconds(w, mapping) ?? Plan.plannedSeconds(w, mapping), note: n)
        }
        .sorted { $0.day != $1.day ? $0.day > $1.day : $0.id < $1.id }
    }

    var body: some View {
        let list = entries
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FUEL NOTES").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                    Text(list.isEmpty ? "No long sessions noted yet" : FuelTally(list.map(\.note)).headline)
                        .font(.title3.weight(.bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Text("Your answers to “Stomach OK?” on sessions of 90 minutes or longer, newest first.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.plan))
                ForEach(list) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Dates.short(e.day).uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Theme.plan)
                            Text(e.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(e.note.answer?.word ?? "—").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                            if let s = e.seconds, s > 0 { Text(formatDuration(s)).font(.footnote).foregroundStyle(Theme.secondary) }
                        }
                        if !e.note.line.isEmpty {
                            Text(e.note.line).font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Fuel notes").navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain).accessibilityIdentifier("fuel-notes")
    }
}
