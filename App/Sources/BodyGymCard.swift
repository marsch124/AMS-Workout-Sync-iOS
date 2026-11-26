import SwiftUI
import WorkoutCore

/* 2.9 lane "gym": the Gym sessions card (from AMS Workout Companion's file) and its reader. Placeholder: the lane fills this file. */
@MainActor
final class GymReader: ObservableObject {
    static let shared = GymReader()
    func readIfDue(today: String) async {}
    func read(today: String) async {}
}

struct GymCard: View {
    let day: String
    var body: some View { EmptyView() }
}
