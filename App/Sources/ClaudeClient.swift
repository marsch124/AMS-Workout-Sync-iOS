import Foundation
import WorkoutCore

/* One answer, as kept in the log: never the key, never the plan itself. */
struct ClaudeLogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    let at: Date
    /* The menu's headlines: the rule book's pick first, then the other choices. */
    let menu: [String]
    /* 0 kept the plan, 1… a menu number; nil when no usable answer came back. */
    let pick: Int?
    let why: String
    let inputTokens: Int
    let outputTokens: Int
    let dollars: Double
    /* Why nothing came back, in a few plain words (never the key, never the reply itself). */
    var failure: String? = nil
    /* nil for a pick; "review" or "ask" for the week review and a question about the plan. */
    var kind: String? = nil
    /* What was done, for those two ("Wrote the week review"). */
    var label: String? = nil

    /* "Kept your plan" or "Chose: Tue bike: 60 → 40 min, easy". */
    var choiceWords: String {
        if let kind {
            if let failure { return failure }
            return label ?? (kind == "review" ? "Wrote the week review" : "Answered a question")
        }
        if let failure { return failure + ", the rule book's own pick stood" }
        guard let pick else { return "No usable answer, the rule book's own pick stood" }
        if pick == 0 { return "Kept your plan" }
        return "Chose: " + (menu.indices.contains(pick - 1) ? menu[pick - 1] : "choice \(pick)")
    }
}

/* What came of a review or a question: an answer that passed, one that did not, or nothing. */
enum ClaudeRun<T> {
    case answer(T)
    case notPassed
    case none
}

enum ClaudeCheck: Equatable {
    case ok
    case rejected
    case unreachable
}

/*
 * The one place that talks to Anthropic. It returns nil whenever it is off,
 * has no key, the month's cap is reached, or anything at all goes wrong — and
 * the caller then simply keeps the rule book's own pick.
 */
@MainActor
final class ClaudeClient: ObservableObject {
    static let shared = ClaudeClient()

    private static let onKey = "claude-on"
    private static let refusedKey = "claude-refused"

    @Published private(set) var meter: ClaudeMeter
    @Published private(set) var log: [ClaudeLogEntry]
    @Published private(set) var keySaved: Bool
    /* What Anthropic last refused for a reason that does not pass by itself; kept across restarts. */
    @Published private(set) var refused: ClaudeTrouble?

    private let session: URLSession

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var meterURL: URL { folder.appendingPathComponent("claude-meter.json") }
    private static var logURL: URL { folder.appendingPathComponent("claude-log.json") }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = ClaudePick.requestTimeout
        config.timeoutIntervalForResource = ClaudePick.requestTimeout
        session = URLSession(configuration: config)
        keySaved = ClaudeKey.isSaved
        meter = (try? JSONDecoder().decode(ClaudeMeter.self, from: Data(contentsOf: Self.meterURL))) ?? .fresh()
        log = (try? JSONDecoder().decode([ClaudeLogEntry].self, from: Data(contentsOf: Self.logURL))) ?? []
        refused = UserDefaults.standard.string(forKey: Self.refusedKey).flatMap(ClaudeTrouble.init(rawValue:))
        #if DEBUG
        if ClaudeKey.isFake {
            meter = ClaudeMeter(month: ClaudeMeter.monthKey(Date()), inputTokens: 7300, outputTokens: 420, dollars: 0.12, answers: 6)
            log = Self.invented()
        }
        #endif
    }

    /* The switch: off until he turns it on, and only usable with a key. */
    var isOn: Bool {
        get { keySaved && UserDefaults.standard.bool(forKey: Self.onKey) }
        set {
            UserDefaults.standard.set(newValue && keySaved, forKey: Self.onKey)
            objectWillChange.send()
        }
    }

    /*
     * Why Claude cannot choose just now, for the line on Settings → Claude and
     * on the suggestion card. nil while it is off (nothing to say) or all is well.
     */
    var trouble: ClaudeTrouble? {
        #if DEBUG
        // AMSWS_CLAUDE_TROUBLE=key|credit|cap shows the line for a picture.
        switch ProcessInfo.processInfo.environment["AMSWS_CLAUDE_TROUBLE"] {
        case "key": return .keyRefused
        case "credit": return .noCredit
        case "cap": return .capReached
        default: break
        }
        #endif
        guard isOn else { return nil }
        return refused ?? (meter.canSpend() ? nil : .capReached)
    }

    private func setRefused(_ trouble: ClaudeTrouble?) {
        guard refused != trouble else { return }
        refused = trouble
        UserDefaults.standard.set(trouble?.rawValue, forKey: Self.refusedKey)
    }

    var monthLine: String {
        let m = meter.current()
        let n = m.answers == 1 ? "1 answer" : "\(m.answers) answers"
        return String(format: "This month: %.2f US dollars of %.2f · ", m.dollars, ClaudeMeter.defaultCap) + n
    }

    func keyChanged() {
        keySaved = ClaudeKey.isSaved
        setRefused(nil)
        if !keySaved { UserDefaults.standard.set(false, forKey: Self.onKey) }
        objectWillChange.send()
    }

    /* Pick one item of the rule book's menu, or nil. */
    func pick(for suggestion: Suggestion, context: ClaudeContext) async -> ClaudeAnswer? {
        #if DEBUG
        if ClaudeKey.isFake {
            return ClaudeAnswer(pick: 1, why: "Why: a shorter, easier ride suits a week like this.",
                                usage: ClaudeUsage(input: 1200, output: 40))
        }
        #endif
        guard isOn, let key = ClaudeKey.read(), meter.canSpend() else { return nil }
        let request = ClaudePick.request(for: suggestion, context: context)
        let body = ClaudePick.body(system: request.system, user: request.user)
        let menu = [suggestion.choice.headline] + suggestion.otherChoices.map(\.headline)
        guard let (status, data) = await post(body, key: key) else {
            note("No answer from Anthropic (timed out or offline)", menu: menu)
            return nil
        }
        guard status == 200 else {
            // An error reply is not billed: one line in the log, nothing on the meter.
            // A refusal only he can set right is remembered and said on the page and the card; a hiccup is not.
            let trouble = ClaudeTrouble.read(status: status, body: data)
            if let trouble { setRefused(trouble) }
            note((trouble?.logWords ?? "Anthropic answered with an error") + " (\(status))", menu: menu)
            return nil
        }
        setRefused(nil)

        let answer = ClaudePick.read(data, menuCount: ClaudePick.menuCount(for: suggestion))
        // What was asked for is paid for, usable or not.
        let usage = answer?.usage ?? ClaudePick.usage(in: data) ?? ClaudeUsage()
        meter.add(usage: usage)
        save(meter, to: Self.meterURL)
        let entry = ClaudeLogEntry(at: Date(), menu: menu, pick: answer?.pick,
                                   why: answer?.why ?? "", inputTokens: usage.input + usage.cacheCreation + usage.cacheRead,
                                   outputTokens: usage.output, dollars: usage.dollars)
        log = Array(([entry] + log).prefix(200))
        save(log, to: Self.logURL)
        return answer
    }

    /*
     * The week review and "Ask about your plan" go through here and nowhere else:
     * the same key, the same month meter and cap, the same log, the same refused
     * state, the same 20-second single try. `read` is the answer check; what it
     * refuses is paid for and logged, and nothing is shown.
     */
    func run<T>(kind: String, label: String, detail: String = "", body: Data, fake: T, read: (Data) -> T?) async -> ClaudeRun<T> {
        #if DEBUG
        if ClaudeKey.isFake { return .answer(fake) }
        #endif
        guard isOn, let key = ClaudeKey.read(), meter.canSpend() else { return .none }
        guard let (status, data) = await post(body, key: key) else {
            note("No answer from Anthropic (timed out or offline)", menu: [], kind: kind, detail: detail)
            return .none
        }
        guard status == 200 else {
            let trouble = ClaudeTrouble.read(status: status, body: data)
            if let trouble { setRefused(trouble) }
            note((trouble?.logWords ?? "Anthropic answered with an error") + " (\(status))", menu: [], kind: kind, detail: detail)
            return .none
        }
        setRefused(nil)
        let value = read(data)
        let usage = ClaudePick.usage(in: data) ?? ClaudeUsage()
        meter.add(usage: usage)
        save(meter, to: Self.meterURL)
        let entry = ClaudeLogEntry(at: Date(), menu: [], pick: nil, why: detail,
                                   inputTokens: usage.input + usage.cacheCreation + usage.cacheRead,
                                   outputTokens: usage.output, dollars: usage.dollars,
                                   failure: value == nil ? "The answer did not pass the app\u{2019}s check, nothing shown" : nil,
                                   kind: kind, label: label)
        log = Array(([entry] + log).prefix(200))
        save(log, to: Self.logURL)
        if let value { return .answer(value) }
        return .notPassed
    }

    /* One line in the log for an ask that brought no answer. */
    private func note(_ failure: String, menu: [String], kind: String? = nil, detail: String = "") {
        let entry = ClaudeLogEntry(at: Date(), menu: menu, pick: nil, why: detail, inputTokens: 0, outputTokens: 0,
                                   dollars: 0, failure: failure, kind: kind)
        log = Array(([entry] + log).prefix(200))
        save(log, to: Self.logURL)
    }

    /* The tiny check of a typed key, before it is kept. */
    func check(_ key: String) async -> ClaudeCheck {
        #if DEBUG
        if ClaudeKey.isFake { return .ok }
        #endif
        guard let (status, _) = await post(ClaudePick.testBody(), key: key) else { return .unreachable }
        switch status {
        case 200: return .ok
        case 401, 403: return .rejected
        default: return .unreachable
        }
    }

    /* One try, no retry, at most 20 seconds: a late answer must not change the card under his finger. nil: nothing came back. */
    private func post(_ body: Data, key: String) async -> (Int, Data)? {
        var request = URLRequest(url: URL(string: ClaudePick.endpoint)!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = ClaudePick.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudePick.version, forHTTPHeaderField: "anthropic-version")
        request.setValue(ClaudePick.beta, forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) { try? data.write(to: url, options: .atomic) }
    }

    #if DEBUG
    private static func invented() -> [ClaudeLogEntry] {
        let now = Date()
        let menu = ["Tue bike: 60 → 40 min, easy", "Tue bike: rest (your choice)"]
        return [
            ClaudeLogEntry(at: now.addingTimeInterval(-3_600), menu: menu, pick: 1,
                           why: "Why: two poor mornings, so a shorter easy ride.", inputTokens: 1200, outputTokens: 40, dollars: 0.006),
            ClaudeLogEntry(at: now.addingTimeInterval(-90_000), menu: menu, pick: 0,
                           why: "Why: the week looks fine as it is.", inputTokens: 1180, outputTokens: 38, dollars: 0.005),
            ClaudeLogEntry(at: now.addingTimeInterval(-260_000), menu: menu, pick: 2,
                           why: "Why: a full rest day gives the legs a clean start.", inputTokens: 1210, outputTokens: 44, dollars: 0.006),
        ]
    }
    #endif
}
