import Foundation

/* The keys of the wide layout (iPad with a keyboard, and the Mac): what the "Keys" plate lists, and where ⌘N lands. */
public enum KeyGuide {
    public struct Row: Equatable {
        public let keys: String
        public let action: String
    }

    public static let rows: [Row] = [
        Row(keys: "\u{2318}1 \u{2026} \u{2318}6", action: "Open Today, Plan, Sessions, Body, Progress, Settings"),
        Row(keys: "\u{2318}N", action: "New session, on the day shown or today"),
        Row(keys: "\u{2190} \u{2192}", action: "On Plan: the week before or after (Week), the month before or after (Month)"),
        Row(keys: "\u{2318}T", action: "Jump to today"),
        Row(keys: "Space", action: "On an open session: Done as planned, where that button is"),
        Row(keys: "\u{2318}F", action: "Go to the search box, on a page that has one"),
        Row(keys: "Esc", action: "Close the open page without saving"),
        Row(keys: "? or \u{2318}/", action: "Show this list")
    ]

    /* The day a new session starts on: the week or month on show if it is not the current one, else today. */
    public static func newSessionDay(today: String, onPlan: Bool, mode: String, weekStart: String, month: String) -> String {
        guard onPlan else { return today }
        switch mode {
        case "week":
            guard !weekStart.isEmpty, weekStart != PlanView.weekStart(today) else { return today }
            return weekStart
        case "month":
            guard !month.isEmpty, month != String(today.prefix(7)) else { return today }
            return month + "-01"
        default:
            return today
        }
    }
}
