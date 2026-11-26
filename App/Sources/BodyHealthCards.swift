import SwiftUI
import WorkoutCore

/* 2.9 lane "health": the Sleep debt, Weight, Energy and Water cards and their reader. Placeholder: the lane fills this file. */
@MainActor
final class BodyHealthReader: ObservableObject {
    static let shared = BodyHealthReader()
    func readIfDue(today: String) async {}
    func read(today: String) async {}
}

struct SleepDebtCard: View {
    let day: String
    var body: some View { EmptyView() }
}

struct WeightCard: View {
    let day: String
    var body: some View { EmptyView() }
}

struct EnergyCard: View {
    let day: String
    var body: some View { EmptyView() }
}

struct WaterCard: View {
    let day: String
    var body: some View { EmptyView() }
}
