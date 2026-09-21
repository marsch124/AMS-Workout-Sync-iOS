import Foundation
import WorkoutCore

/*
 * Sessions whose numbers were filled from Apple Health on this phone. Only a
 * hint for what the session screen offers — the session screen also checks the
 * recorded numbers against Health, so a new phone reaches the same answer.
 */
enum HealthMark {
    private static let key = "healthFilled"

    private static func id(_ w: Workout) -> String { w.key + "|" + w.dayKey }

    static func used(_ w: Workout) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id(w))
    }

    static func remember(_ w: Workout) {
        var all = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !all.contains(id(w)) else { return }
        all.append(id(w))
        UserDefaults.standard.set(Array(all.suffix(800)), forKey: key)
    }

    static func forgetAll() { UserDefaults.standard.removeObject(forKey: key) }
}
