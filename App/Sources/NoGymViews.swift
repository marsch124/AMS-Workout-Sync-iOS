import SwiftUI
import WorkoutCore

/*
 * No-gym strength (round 28, pick 20): on a strength session's page, a word
 * button "No-gym version". It opens a card with a body-weight circuit sized to
 * the session's planned length. TEXT ONLY: nothing in the plan changes and he
 * logs the strength session as usual. The app's own strength sessions normally
 * point to his other app Workouts (that link stays); this is for no gym.
 */
struct NoGymEntry: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    let workout: Workout
    let minutes: Int
    @State private var showing = false

    private var firstChoice: Bool {
        guard let p = AwayStore.current(today: store.today), p.contains(workout.dayKey) else { return false }
        return Away.lacking(Away.need(sport: .strength, text: workout.title), in: p) != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Button("No-gym version") { showing = true }
                .settingsButton(tint: Theme.sportInk("strength"), filled: firstChoice)
                .accessibilityIdentifier("nogym-open")
            if firstChoice {
                Text("First choice while away without a gym").font(.footnote).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("nogym-first-choice")
            }
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showing) { NoGymCard(minutes: minutes) }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["AMSWS_NOGYM"] != nil { showing = true } }
        #endif
    }
}

struct NoGymCard: View {
    let minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = NoGymCircuit.build(plannedMinutes: minutes)
        let tint = Theme.sportInk("strength")
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NO-GYM VERSION").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(c.rounds)").font(.largeTitle.weight(.bold))
                        Text(c.rounds == 1 ? "round" : "rounds").font(.subheadline.weight(.semibold))
                    }
                    Text("\(c.moves.count) moves \u{00B7} about \(minutes) min planned").font(.footnote).opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))

                line(c.warmUp)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(c.moves.enumerated()), id: \.offset) { _, m in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(m.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(m.amount).font(.subheadline).foregroundStyle(Theme.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                    Text(c.roundsLine).font(.footnote.weight(.semibold)).foregroundStyle(tint).padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                line(c.coolDown)

                Text("Move at a pace you can hold; stop a move that hurts and do an easier one. This changes nothing in your plan: log the strength session as usual.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 76)
        }
        .background(tint.opacity(0.07).background(Theme.bg).ignoresSafeArea())
        .overlay(alignment: .bottom) {
            Button { dismiss() } label: {
                Text("Done").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.mainButton))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(12)
            .accessibilityIdentifier("nogym-done")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nogym-card")
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}
