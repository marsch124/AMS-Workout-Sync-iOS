import SwiftUI

/*
 * How the plan in iCloud stands on this device. Always shown as a dot WITH
 * its words — the dot alone never carries the meaning.
 */
enum SyncStatus: Equatable {
    case off                 // iCloud is off, or this device is not signed in
    case working             // on its way up or down
    case same(Date?)         // the same on all devices; when they last met
    case problem(String)     // the words say which

    var words: String {
        switch self {
        case .off: return "iCloud is off"
        case .working: return "On its way"
        case .same: return "Same on all devices"
        case .problem(let why): return why
        }
    }

    var tint: Color {
        switch self {
        case .off: return Theme.secondary
        case .working: return Theme.extraHour
        case .same: return Theme.today
        case .problem: return Theme.danger
        }
    }
}
