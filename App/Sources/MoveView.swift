import SwiftUI
import WorkoutCore

/*
 * Two ways to move a session, because there are two situations: it simply
 * happens on another day (move it), or you did today's other session instead
 * and the two want exchanging (swap them). A swap keeps the week's shape.
 *
 * The date and the button share a line, half each, in the order they are
 * used — the web app learned that a full-width green button reads as the
 * whole task and the date above it as a caption (v1.61.0).
 *
 * The swap list offers only sessions not yet done, nearest first and the one
 * still ahead first on a tie: on 14 September the done long run from two days
 * back sat first and was swapped onto today with its results.
 */
struct MoveView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout

    @State private var day: Date
    @State private var swapWith: Workout?

    init(workout: Workout) {
        self.workout = workout
        _day = State(initialValue: parseDayKey(workout.dayKey) ?? Date())
    }

    private var chosenKey: String { dayKey(day) ?? workout.dayKey }
    private var candidates: [(workout: Workout, gap: Int)] { Sync.swapCandidates(for: workout, in: store.displayed) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SessionCard(workout: workout, mapping: store.mapping!)

                    SectionHeading(text: "Move it to")
                    HStack(spacing: 10) {
                        DatePicker("New day", selection: $day, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                        Button {
                            store.move(workout, to: chosenKey)
                            dismiss()
                        } label: {
                            Text("Move the session").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.today)
                        .disabled(chosenKey == workout.dayKey)
                    }
                    Text(chosenKey == workout.dayKey
                         ? "Pick a different day first."
                         : "Only the date is rewritten. The session keeps its place in every weekly total, because your sheet counts by week number and sport, never by date.")
                        .font(.caption).foregroundStyle(Theme.secondary)

                    if !candidates.isEmpty {
                        SectionHeading(text: "Or swap it with")
                        Text("Exchanges the two days — for when you did one session in the other’s place. Only sessions still to do are offered.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                        ForEach(candidates, id: \.workout.key) { c in
                            Button { swapWith = c.workout } label: {
                                HStack(spacing: 12) {
                                    SportBadge(discipline: c.workout.discipline, size: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.workout.title).font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(Dates.short(c.workout.dayKey) + " · " + gapText(c.gap))
                                            .font(.caption).foregroundStyle(Theme.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog(swapTitle, isPresented: Binding(get: { swapWith != nil }, set: { if !$0 { swapWith = nil } }), titleVisibility: .visible) {
                Button("Swap these two") {
                    if let other = swapWith { store.swap(workout, other) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { swapWith = nil }
            }
        }
    }

    private var swapTitle: String {
        guard let other = swapWith else { return "" }
        return "\(workout.discipline.label) → \(Dates.short(other.dayKey))\n\(other.discipline.label) → \(Dates.short(workout.dayKey))"
    }

    private func gapText(_ gap: Int) -> String {
        if gap == 0 { return "same day" }
        if gap > 0 { return "in \(gap) day\(gap == 1 ? "" : "s")" }
        return "\(-gap) day\(gap == -1 ? "" : "s") ago"
    }
}
