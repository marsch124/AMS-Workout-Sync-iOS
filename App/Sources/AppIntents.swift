import AppIntents
import WorkoutCore

/*
 * Round 28, "system": Siri and Shortcuts. Three questions or one tap, never a change to the plan:
 * today's (or tomorrow's) session, "Done as planned" for today's one session of a sport, and the week's hours.
 * There is no intent that moves, removes or edits a session.
 *
 * The plan is loaded the way the app loads it at launch (the shared Store). If it cannot be read in the
 * background, the intent opens the app instead of guessing.
 */

enum DayChoice: String, AppEnum {
    case today, tomorrow
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Day")
    static var caseDisplayRepresentations: [DayChoice: DisplayRepresentation] = [
        .today: "Today", .tomorrow: "Tomorrow"
    ]
}

enum SportChoice: String, AppEnum {
    case swim, bike, run, strength, mobility
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sport")
    static var caseDisplayRepresentations: [SportChoice: DisplayRepresentation] = [
        .swim: "Swim", .bike: "Bike", .run: "Run", .strength: "Strength", .mobility: "Mobility"
    ]
}

private let planNotReady = IntentDialog("The plan is not ready yet. Open Triathlon and ask again.")

extension ForegroundContinuableIntent {
    /* The shared Store with its plan; if the plan cannot be read in the background, the app is opened to read it, never guessed. */
    @MainActor func storeWithPlan() async throws -> Store? {
        let store = IntentStore.shared
        if store.view == nil { try await requestToContinueInForeground(planNotReady) }
        return store.view == nil ? nil : store
    }
}

struct TodaysSessionIntent: AppIntent, ForegroundContinuableIntent {
    /* Round 28 safety: only on an unlocked device, so the plan's files can be read (never a half-read plan). */
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var title: LocalizedStringResource = "What is my session"
    static var description = IntentDescription("Says today's or tomorrow's session, or that it is a rest day.")

    @Parameter(title: "Day", default: .today) var day: DayChoice

    init() {}
    init(day: DayChoice) { self.day = day }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = try await storeWithPlan() else { return .result(dialog: planNotReady) }
        let key = day == .today ? store.today : PlanView.addDays(store.today, 1)
        let text = SystemWords.spokenDay(store.briefs, day: key, word: day == .today ? "Today" : "Tomorrow")
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct LogTodaysSessionIntent: AppIntent, ForegroundContinuableIntent {
    /* Round 28 safety: only on an unlocked device, so the plan's files can be read (never a half-read plan). */
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var title: LocalizedStringResource = "Log today's session as done"
    static var description = IntentDescription("Logs today's planned session of one sport as done as planned. Nothing else is changed.")

    @Parameter(title: "Sport") var sport: SportChoice

    init() {}
    init(sport: SportChoice) { self.sport = sport }

    static var parameterSummary: some ParameterSummary {
        Summary("Log today's \(\.$sport) as done")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = try await storeWithPlan() else { return .result(dialog: planNotReady) }
        let label = SportChoice.caseDisplayRepresentations[sport].map { String(localized: $0.title) } ?? sport.rawValue
        let pick = SystemWords.pickToLog(store.briefs, today: store.today, sportID: sport.rawValue)
        guard case .log(let brief) = pick, let workout = store.workout(brief.key) else {
            return .result(dialog: IntentDialog(stringLiteral: SystemWords.refusal(pick, sport: label)))
        }
        // The same function the in-app "Done as planned" button calls; it refuses where logging is not allowed here.
        guard store.canLog else {
            return .result(dialog: "Logging is not possible from here. Open Triathlon and tap Done as planned. Nothing was logged.")
        }
        store.logAsPlanned(workout)
        guard store.isWaiting(brief.key) || store.workout(brief.key)?.logged == true else {
            return .result(dialog: "Nothing was logged. Open Triathlon and try there.")
        }
        return .result(dialog: IntentDialog(stringLiteral: SystemWords.loggedWords(brief)))
    }
}

struct HowIsMyWeekIntent: AppIntent, ForegroundContinuableIntent {
    /* Round 28 safety: only on an unlocked device, so the plan's files can be read (never a half-read plan). */
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var title: LocalizedStringResource = "How is my week"
    static var description = IntentDescription("Says this week's hours done of the hours planned.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = try await storeWithPlan(), let mapping = store.mapping else { return .result(dialog: planNotReady) }
        let monday = PlanView.weekStart(store.today)
        let hours = PlanOverview.hours(store.displayed, mapping, from: monday, to: PlanView.addDays(monday, 6))
        return .result(dialog: IntentDialog(stringLiteral: SystemWords.spokenWeek(doneSeconds: hours.done, plannedSeconds: hours.planned)))
    }
}

struct TriathlonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodaysSessionIntent(day: .today),
                    phrases: ["What's my session today in \(.applicationName)",
                              "What is my session today in \(.applicationName)"],
                    shortTitle: "Today's session", systemImageName: "figure.run")
        AppShortcut(intent: TodaysSessionIntent(day: .tomorrow),
                    phrases: ["What's my session tomorrow in \(.applicationName)",
                              "What is my session tomorrow in \(.applicationName)"],
                    shortTitle: "Tomorrow's session", systemImageName: "calendar")
        AppShortcut(intent: LogTodaysSessionIntent(),
                    phrases: ["Log today's \(\.$sport) as done in \(.applicationName)"],
                    shortTitle: "Log today as done", systemImageName: "checkmark")
        AppShortcut(intent: HowIsMyWeekIntent(),
                    phrases: ["How is my week in \(.applicationName)"],
                    shortTitle: "My week", systemImageName: "chart.bar")
    }
}
