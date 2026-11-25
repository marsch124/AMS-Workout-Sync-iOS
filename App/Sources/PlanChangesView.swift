import SwiftUI
import WorkoutCore

/*
 * Settings → Changes to the plan: every change made to the plan itself, newest
 * first — what was there before, what is there now — each with a way back.
 */
struct PlanChangesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Text("Changes to the plan")
    }
}
