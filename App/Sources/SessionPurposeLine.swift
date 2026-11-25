import SwiftUI
import WorkoutCore

/*
 * "Why this session?" (round 28, pick 41): the one grey line under a planned
 * session's title. The rules are in Core (`SessionPurpose`); this only gathers
 * what they need from the plan.
 */
extension Store {
    func purposeLine(for w: Workout) -> String? {
        guard w.discipline.id != "rest", let view else { return nil }
        let sport = w.discipline.id
        let minutes = { (x: Workout) in Int(((Plan.plannedSeconds(x, view.mapping) ?? 0) / 60).rounded()) }
        let typical = SessionPurpose.typicalMinutes(view.plan.filter { $0.discipline.id == sport }.map(minutes))
        let monday = PlanView.weekStart(w.dayKey)
        let tag = book?.weeks.first { $0.monday == monday }.map { RuleBook.tag(of: $0, raceWeek: RuleBookSettings().raceWeek) }
        return SessionPurpose.line(PurposeInput(
            sport: sport, title: w.title, intensity: w.planned.intensity, plannedMin: minutes(w),
            phase: w.phase, isKey: w.isKey, typicalMin: typical, weekTag: tag))
    }
}

/* The line itself: grey, footnote size, under the title. Nothing when the rules cannot name the session. */
struct SessionWhyLine: View {
    @EnvironmentObject var store: Store
    let workout: Workout

    var body: some View {
        if let line = store.purposeLine(for: workout) {
            Text(line)
                .font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("session-why")
        }
    }
}
