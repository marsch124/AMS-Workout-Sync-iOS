import SwiftUI
import WorkoutCore

/* 2.9 lane "load": the Training load and Fitness cards and their reader. Placeholder: the lane fills this file. */
@MainActor
final class BodyLoadReader: ObservableObject {
    static let shared = BodyLoadReader()
    func readIfDue(today: String) async {}
    func read(today: String) async {}
}

struct TrainingLoadCard: View {
    let day: String
    var body: some View { EmptyView() }
}

struct FitnessCard: View {
    let day: String
    var body: some View { EmptyView() }
}
