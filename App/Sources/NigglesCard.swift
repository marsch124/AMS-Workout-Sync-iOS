import SwiftUI
import WorkoutCore

struct NiggleEntry: Identifiable, Equatable {
    var id: String
    var day: String
    var title: String
    var note: NiggleNote
}

/*
 * Progress: "Niggles" — each place with how often and since when, then every note by date.
 * A notebook, not a diagnosis: no advice, no warning colours. Hidden until he has noted one.
 */
struct NigglesCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    /* Invented entries for a picture; nil = the shelf's own. */
    var sample: [NiggleEntry]?
    private let shown = 12

    private var entries: [NiggleEntry] {
        if let sample { return sample }
        return shelf.keys(prefix: LogExtrasKeys.prefix).compactMap { k in
            guard let wk = LogExtrasKeys.workoutKey(from: k, fact: "niggle"), let w = store.workout(wk),
                  let n = shelf.value(NiggleNote.self, for: k) else { return nil }
            return NiggleEntry(id: wk, day: w.dayKey, title: w.title, note: n)
        }
        .sorted { $0.day != $1.day ? $0.day > $1.day : $0.id < $1.id }
    }

    var body: some View {
        let list = entries
        if !list.isEmpty {
            let spots = NiggleCount.spots(list.map { (day: $0.day, note: $0.note) })
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NIGGLES").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                    Text("\(list.count) noted on \(spots.count) place\(spots.count == 1 ? "" : "s")")
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.progress))
                ForEach(spots, id: \.label) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(s.label).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                        Text("· \(NiggleCount.countWords(s.count)) since \(Dates.short(s.sinceDay))")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
                Divider()
                ForEach(list.prefix(shown)) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Dates.short(e.day).uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Theme.progress)
                        Text(e.note.placeWords.prefix(1).uppercased() + e.note.placeWords.dropFirst() + (e.note.line.isEmpty ? "" : " — " + e.note.line))
                            .font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        Text(e.title).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                if list.count > shown {
                    Text("\(list.count - shown) earlier ones are kept.").font(.caption).foregroundStyle(Theme.secondary)
                }
                Text("If something hurts, the Stop sign page is under Not well?")
                    .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .accessibilityElement(children: .contain).accessibilityIdentifier("niggles-card")
        }
    }
}
