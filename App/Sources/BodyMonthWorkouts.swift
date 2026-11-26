import SwiftUI
import WorkoutCore

/* 2.9 lane "workouts": every Garmin workout of the month, and its reader. Placeholder: the lane fills this file. */
@MainActor
final class MonthWorkoutsReader: ObservableObject {
    static let shared = MonthWorkoutsReader()
    func readIfDue(today: String) async {}
    func read(today: String) async {}
}

struct MonthWorkoutsCard: View {
    let day: String
    /* Opens a workout as a tap on the curve does: (the workout, all of that day's workouts, that day "yyyy-MM-dd"). */
    let open: (BodyDay.Workout, [BodyDay.Workout], String) -> Void
    var body: some View { EmptyView() }
}
