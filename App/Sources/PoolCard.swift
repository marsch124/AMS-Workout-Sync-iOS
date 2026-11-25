import SwiftUI
import WorkoutCore

/*
 * The pool card (round 28, pick 24): a swim session's set in very large type
 * for the pool side, one step per row, with big Back and Next zones.
 *
 * This is the one place in the app where type is deliberately large. It still
 * uses the system's text styles (.largeTitle, .title) so it grows with the
 * phone's own text size, never a fixed number of points.
 */

extension Workout {
    /* The session's own words read as a set: its sections first, its title when the sections hold no distance. */
    var swimSet: SwimSet {
        var set = SwimSet.parse(sections: sections.map { ($0.label, $0.text) })
        if !set.hasDistance {
            let fromTitle = SwimSet.parse(title)
            if fromTitle.hasDistance { set = SwimSet(steps: fromTitle.steps + set.steps) }
        }
        if set.steps.isEmpty { set = SwimSet(steps: [SwimStep(line: title, understood: false)]) }
        return set
    }
}

/* The button on a swim session's page. */
struct PoolCardButton: View {
    let workout: Workout
    @State private var open = false

    var body: some View {
        Button("Pool card") { open = true }
            .settingsButton(tint: Theme.plan)
            .accessibilityIdentifier("pool-card-open")
            .fullScreenCover(isPresented: $open) {
                PoolCardView(title: workout.title, set: workout.swimSet, close: { open = false })
            }
    }
}

struct PoolCardView: View {
    let title: String
    let set: SwimSet
    let close: () -> Void
    @State private var current = 0

    private var swim: Color { Theme.sport("swim") }
    private var last: Int { max(0, set.steps.count - 1) }

    var body: some View {
        VStack(spacing: 0) {
            top
            rows
            zones
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pool-card")
        // The screen stays lit while the card is open, and goes back to its own timing when it is left.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var top: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.hasDistance ? "Whole set" : title).font(.headline).foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
                if set.hasDistance {
                    Text(SwimSet.metresText(set.totalMetres)).font(.largeTitle.weight(.heavy).monospacedDigit())
                        .foregroundStyle(Color(uiColor: .label))
                        .accessibilityIdentifier("pool-total")
                }
            }
            Spacer(minLength: 0)
            Button("Done", action: close)
                .font(.title3.weight(.bold))
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.mainButton)
                .accessibilityIdentifier("pool-done")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(set.steps.enumerated()), id: \.offset) { index, step in
                        let on = index == current
                        VStack(alignment: .leading, spacing: 2) {
                            if let heading = step.heading, index == 0 || set.steps[index - 1].heading != heading {
                                Text(heading.uppercased()).font(.headline).tracking(0.8)
                                    .foregroundStyle(on ? Color.white.opacity(0.85) : Color(uiColor: .secondaryLabel))
                            }
                            Text(step.line)
                                .font(.title.weight(on ? .heavy : .semibold))
                                .foregroundStyle(on ? Color.white : Color(uiColor: .label))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? swim : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture { current = index }
                        .id(index)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pool-row-\(index)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 12)
            }
            .onChange(of: current) { _, now in withAnimation { proxy.scrollTo(now, anchor: .center) } }
        }
    }

    /* Two big zones under the thumb: Back on the left, Next on the right. */
    private var zones: some View {
        HStack(spacing: 10) {
            Button { if current > 0 { current -= 1 } } label: {
                Text("Back").font(.largeTitle.weight(.bold)).foregroundStyle(Color(uiColor: .label))
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(uiColor: .secondarySystemFill)))
            }
            .buttonStyle(.plain)
            .opacity(current == 0 ? 0.45 : 1)
            .accessibilityIdentifier("pool-back")
            Button { if current < last { current += 1 } } label: {
                Text("Next").font(.largeTitle.weight(.bold)).foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(swim))
            }
            .buttonStyle(.plain)
            .opacity(current == last ? 0.45 : 1)
            .accessibilityIdentifier("pool-next")
        }
        .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 4)
    }
}
