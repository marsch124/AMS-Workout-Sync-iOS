import SwiftUI
import WorkoutCore

/*
 * 2.9: the Garmin Board's cards that the Body page lacked, in two parts under the tiles:
 * Training (training load, fitness age, gym sessions, the month's workouts) and Health
 * (sleep debt, weight, energy, water). Each card lives in its own file with its own reader;
 * this file only places them and asks every reader to read.
 *
 * On the iPhone two small cards share a row and the big ones stand full width; on the iPad
 * and the Mac every pair shares a row.
 */
struct BodyMoreCards: View {
    let day: String
    let wide: Bool
    /* A workout from the month's list opens as one on the curve does: its session, its extra or its own facts. */
    let open: (BodyDay.Workout, [BodyDay.Workout], String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BodyPartTitle(text: "Training", id: "body-part-training")
            // 2.10: every card in a colour of its own (BodyHues.swift).
            side { TrainingLoadCard(day: day).bodyHue(.load) } _: { FitnessCard(day: day).bodyHue(.fitness) }
            stack { GymCard(day: day).bodyHue(.gym) } _: { MonthWorkoutsCard(day: day, open: open).bodyHue(.workouts) }
            BodyPartTitle(text: "Health", id: "body-part-health")
            stack { SleepDebtCard(day: day).bodyHue(.sleep) } _: { WeightCard(day: day).bodyHue(.weight) }
            side { EnergyCard(day: day).bodyHue(.energy) } _: { WaterCard(day: day).bodyHue(.water) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-more")
    }

    /* Two cards side by side, as tall as the taller one. */
    private func side<A: View, B: View>(@ViewBuilder _ a: () -> A, @ViewBuilder _ b: () -> B) -> some View {
        HStack(alignment: .top, spacing: 8) {
            a().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            b().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /* Two big cards: one under the other on the iPhone, side by side on the iPad and the Mac. */
    @ViewBuilder
    private func stack<A: View, B: View>(@ViewBuilder _ a: () -> A, @ViewBuilder _ b: () -> B) -> some View {
        if wide {
            side(a, b)
        } else {
            VStack(spacing: 8) { a(); b() }
        }
    }

    /* Every card's reader, when the page appears or comes back (each keeps its own 30-minute rule). */
    static func readIfDue(today: String) async {
        await BodyLoadReader.shared.readIfDue(today: today)
        await BodyHealthReader.shared.readIfDue(today: today)
        await GymReader.shared.readIfDue(today: today)
        await MonthWorkoutsReader.shared.readIfDue(today: today)
    }

    /* Every card's reader at once, when he pulls the page down. */
    static func read(today: String) async {
        await BodyLoadReader.shared.read(today: today)
        await BodyHealthReader.shared.read(today: today)
        await GymReader.shared.read(today: today)
        await MonthWorkoutsReader.shared.read(today: today)
    }
}

/* A part's name on the Body page: Body's colour, left, a step smaller than the page's heading. */
struct BodyPartTitle: View {
    let text: String
    let id: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold)).foregroundStyle(Theme.body)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10).padding(.leading, 2)
    }
}
