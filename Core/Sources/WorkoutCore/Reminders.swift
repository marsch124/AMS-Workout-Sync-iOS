import Foundation

/*
 * Reminders (round 28): what the app tells him, and when. Pure counting: given
 * the plan's sessions, today, the clock and his switches, the list of local
 * notifications to schedule, and the card on Today for next week. Nothing here
 * touches iOS, the plan or any file; the app schedules the list on the device
 * and works it out again whenever the plan changes or the app comes to the front.
 *
 * Three kinds:
 *   - the evening reminder: tomorrow's session(s) in one line;
 *   - the Sunday card: next week in one line, and a card on Today from then
 *     until Monday morning;
 *   - the missed-session question: the morning after a planned session whose day
 *     ended with no log and no "missed".
 * While a pause or an illness is on, nothing is scheduled at all (no nagging).
 */

public struct ReminderSettings: Equatable, Codable, Sendable {
    public var eveningOn = false
    /* Minutes after midnight. */
    public var eveningMinutes = 20 * 60
    public var sundayOn = false
    public var sundayMinutes = 18 * 60
    public var missedOn = false
    public var missedMinutes = 8 * 60

    public init(eveningOn: Bool = false, eveningMinutes: Int = 20 * 60, sundayOn: Bool = false,
                sundayMinutes: Int = 18 * 60, missedOn: Bool = false, missedMinutes: Int = 8 * 60) {
        self.eveningOn = eveningOn; self.eveningMinutes = eveningMinutes
        self.sundayOn = sundayOn; self.sundayMinutes = sundayMinutes
        self.missedOn = missedOn; self.missedMinutes = missedMinutes
    }

    public var anyOn: Bool { eveningOn || sundayOn || missedOn }
}

/* A session as the reminders see it: no cells, no sheet. */
public struct ReminderSession: Equatable, Sendable {
    public var key: String
    public var dayKey: String
    public var disciplineId: String
    public var sport: String
    public var title: String
    /* The easy / hard word of the plan ("easy", "Z2" ...), may be empty. */
    public var intensity: String
    public var seconds: Double?
    public var done: Bool
    public var missed: Bool
    /* The app's own Move to the fire day is allowed for this session (the plan can be changed and the rule book has no objection). */
    public var moveToTodayAllowed: Bool

    public init(key: String, dayKey: String, disciplineId: String, sport: String, title: String = "",
                intensity: String = "", seconds: Double? = nil, done: Bool = false, missed: Bool = false,
                moveToTodayAllowed: Bool = true) {
        self.key = key; self.dayKey = dayKey; self.disciplineId = disciplineId; self.sport = sport
        self.title = title; self.intensity = intensity; self.seconds = seconds
        self.done = done; self.missed = missed; self.moveToTodayAllowed = moveToTodayAllowed
    }

    public var isRest: Bool { disciplineId == "rest" }
}

public struct ReminderWeek: Equatable, Sendable {
    public var monday: String
    public var phase: String
    public var isEasy: Bool
    public var isTest: Bool
    public init(monday: String, phase: String, isEasy: Bool = false, isTest: Bool = false) {
        self.monday = monday; self.phase = phase; self.isEasy = isEasy; self.isTest = isTest
    }
}

public enum ReminderAction: String, Equatable, Sendable {
    case skip = "reminder-skip"
    case moveToToday = "reminder-move"
    case itIsDone = "reminder-done"

    public var title: String {
        switch self {
        case .skip: return "Skip it"
        case .moveToToday: return "Move to today"
        case .itIsDone: return "It is done"
        }
    }
}

public enum ReminderKind: String, Equatable, Sendable { case evening, sunday, missed }

public struct PlannedReminder: Equatable, Sendable {
    public var id: String
    public var kind: ReminderKind
    /* The day it fires and the minute of that day. */
    public var day: String
    public var minutes: Int
    public var title: String
    public var body: String
    public var actions: [ReminderAction]
    /* The session a missed question is about. */
    public var sessionKey: String?
}

public struct SundayCard: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var dayKey: String
        public var disciplineId: String
        public var title: String
        public var seconds: Double?
    }
    public var monday: String
    public var rows: [Row]
    public var totalSeconds: Double
    public var phase: String
    /* "E" or "T" as the season bars mark the week, or nil. */
    public var letter: String?
    public var weekWord: String? { letter == "T" ? "test week" : (letter == "E" ? "easy week" : nil) }
}

public enum Reminders {

    public static let idPrefix = "reminder-"
    /* Days of evening reminders laid ahead, so the app need not be opened every day. */
    public static let eveningDaysAhead = 7
    /* The Sunday card stays until this minute on Monday. */
    public static let cardUntilMinutes = 8 * 60

    // MARK: words

    /* "45 min" under an hour, else his usual "1h 05m". */
    public static func lengthWords(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        return formatDuration(seconds)
    }

    /* "Tomorrow: Run · 45 min easy", "Tomorrow: Swim 40 min · Strength 30 min", "Tomorrow: rest day"; nil when nothing is planned. */
    public static func tomorrowLine(_ sessions: [ReminderSession]) -> String? {
        let training = sessions.filter { !$0.isRest }
        if training.isEmpty { return sessions.isEmpty ? nil : "Tomorrow: rest day" }
        if training.count == 1 {
            let s = training[0]
            var line = "Tomorrow: " + s.sport
            let tail = [lengthWords(s.seconds), s.intensity.trimmingCharacters(in: .whitespaces).lowercased()]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            if !tail.isEmpty { line += " \u{00B7} " + tail }
            return line
        }
        let parts = training.map { s in ([s.sport, lengthWords(s.seconds)].compactMap { $0 }).joined(separator: " ") }
        return "Tomorrow: " + parts.joined(separator: " \u{00B7} ")
    }

    /* "Next week: 7 sessions · 8h 40m". */
    public static func sundayLine(_ sessions: [ReminderSession]) -> String {
        let training = sessions.filter { !$0.isRest }
        let total = training.reduce(0) { $0 + ($1.seconds ?? 0) }
        let count = "\(training.count) session\(training.count == 1 ? "" : "s")"
        return total > 0 ? "Next week: \(count) \u{00B7} \(formatDuration(total))" : "Next week: \(count)"
    }

    public static func missedLine(_ s: ReminderSession) -> String { "Yesterday\u{2019}s \(s.sport) was not logged." }

    // MARK: days

    public static func isSunday(_ day: String) -> Bool { PlanView.addDays(PlanView.weekStart(day), 6) == day }
    public static func isMonday(_ day: String) -> Bool { PlanView.weekStart(day) == day }

    // MARK: the schedule

    /*
     * Every notification to have waiting, soonest first. `nowMinutes` is the
     * clock today in minutes after midnight: a time already gone is not laid.
     * While `paused` (stop sign or illness) the answer is empty.
     */
    public static func schedule(sessions: [ReminderSession], today: String, nowMinutes: Int,
                                settings: ReminderSettings, paused: Bool) -> [PlannedReminder] {
        guard !paused, settings.anyOn else { return [] }
        var out: [PlannedReminder] = []
        func future(_ day: String, _ minutes: Int) -> Bool { day > today || (day == today && minutes > nowMinutes) }

        if settings.eveningOn {
            for offset in 0..<eveningDaysAhead {
                let day = PlanView.addDays(today, offset)
                guard future(day, settings.eveningMinutes) else { continue }
                let tomorrow = PlanView.addDays(day, 1)
                guard let line = tomorrowLine(sessions.filter { $0.dayKey == tomorrow }) else { continue }
                out.append(PlannedReminder(id: idPrefix + "evening-" + day, kind: .evening, day: day,
                                           minutes: settings.eveningMinutes, title: "Training", body: line,
                                           actions: [], sessionKey: nil))
            }
        }

        if settings.sundayOn {
            // This coming Sunday (today when it is Sunday and the time has not passed) and the one after.
            let firstSunday = PlanView.addDays(PlanView.weekStart(today), 6)
            for sunday in [firstSunday, PlanView.addDays(firstSunday, 7)] {
                guard future(sunday, settings.sundayMinutes) else { continue }
                let monday = PlanView.addDays(sunday, 1)
                let week = sessions.filter { $0.dayKey >= monday && $0.dayKey <= PlanView.addDays(monday, 6) }
                guard week.contains(where: { !$0.isRest }) else { continue }
                out.append(PlannedReminder(id: idPrefix + "sunday-" + sunday, kind: .sunday, day: sunday,
                                           minutes: settings.sundayMinutes, title: "Next week", body: sundayLine(week),
                                           actions: [], sessionKey: nil))
            }
        }

        if settings.missedOn {
            // The morning after a day: asked about yesterday's sessions at the fire time of today or tomorrow.
            for fireDay in [today, PlanView.addDays(today, 1)] {
                guard future(fireDay, settings.missedMinutes) else { continue }
                let yesterday = PlanView.addDays(fireDay, -1)
                // Days older than yesterday that were never answered are asked once, today only.
                let open = sessions.filter { s in
                    !s.isRest && !s.done && !s.missed &&
                    (fireDay == today ? s.dayKey < today && s.dayKey >= PlanView.addDays(today, -1) : s.dayKey == yesterday)
                }
                for s in open.prefix(3) {
                    var actions: [ReminderAction] = [.skip]
                    if s.moveToTodayAllowed { actions.append(.moveToToday) }
                    actions.append(.itIsDone)
                    out.append(PlannedReminder(id: idPrefix + "missed-" + fireDay + "-" + s.key, kind: .missed, day: fireDay,
                                               minutes: settings.missedMinutes, title: "Training", body: missedLine(s),
                                               actions: actions, sessionKey: s.key))
                }
            }
        }
        return out.sorted { ($0.day, $0.minutes, $0.id) < ($1.day, $1.minutes, $1.id) }
    }

    // MARK: the card on Today

    /* The Monday of the week the card is about while it shows (Sunday from its time until Monday morning), else nil. */
    public static func cardWeek(today: String, nowMinutes: Int, settings: ReminderSettings) -> String? {
        guard settings.sundayOn else { return nil }
        if isSunday(today), nowMinutes >= settings.sundayMinutes { return PlanView.addDays(today, 1) }
        if isMonday(today), nowMinutes < cardUntilMinutes { return today }
        return nil
    }

    /* Next week's sessions day by day, the total, the phase and E / T. Rest days stay out; nil when the week has no session. */
    public static func card(monday: String, sessions: [ReminderSession], weeks: [ReminderWeek]) -> SundayCard? {
        let last = PlanView.addDays(monday, 6)
        let training = sessions.filter { !$0.isRest && $0.dayKey >= monday && $0.dayKey <= last }
            .sorted { ($0.dayKey, $0.key) < ($1.dayKey, $1.key) }
        guard !training.isEmpty else { return nil }
        let week = weeks.first { $0.monday == monday }
        return SundayCard(
            monday: monday,
            rows: training.map { .init(dayKey: $0.dayKey, disciplineId: $0.disciplineId, title: $0.title, seconds: $0.seconds) },
            totalSeconds: training.reduce(0) { $0 + ($1.seconds ?? 0) },
            phase: week?.phase ?? "",
            letter: week.flatMap { PlanOverview.weekLetter(isEasy: $0.isEasy, isTest: $0.isTest) })
    }
}
