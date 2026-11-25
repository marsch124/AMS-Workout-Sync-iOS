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

    /* "Kept your plan" or "Chose: Tue bike: 60 → 40 min, easy". */
    var choiceWords: String {
        if let failure { return failure + ", the rule book's own pick stood" }
        guard let pick else { return "No usable answer, the rule book's own pick stood" }
        if pick == 0 { return "Kept your plan" }
        return "Chose: " + (menu.indices.contains(pick - 1) ? menu[pick - 1] : "choice \(pick)")
    }
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

    @Published private(set) var meter: ClaudeMeter
    @Published private(set) var log: [ClaudeLogEntry]
    @Published private(set) var keySaved: Bool
    @Published private(set) var rejectedKey = false

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
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
        keySaved = ClaudeKey.isSaved
        meter = (try? JSONDecoder().decode(ClaudeMeter.self, from: Data(contentsOf: Self.meterURL))) ?? .fresh()
        log = (try? JSONDecoder().decode([ClaudeLogEntry].self, from: Data(contentsOf: Self.logURL))) ?? []
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

    var monthLine: String {
        let m = meter.current()
        let n = m.answers == 1 ? "1 answer" : "\(m.answers) answers"
        return String(format: "This month: %.2f US dollars of %.2f · ", m.dollars, ClaudeMeter.defaultCap) + n
    }

    func keyChanged() {
        keySaved = ClaudeKey.isSaved
        rejectedKey = false
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
        if status == 401 { rejectedKey = true }
        guard status == 200 else {
            // An error reply is not billed: one line in the log, nothing on the meter.
            note(status == 401 ? "Anthropic did not accept the key (401)" : "Anthropic answered with error \(status)", menu: menu)
            return nil
        }

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

    /* One line in the log for an ask that brought no answer. */
    private func note(_ failure: String, menu: [String]) {
        let entry = ClaudeLogEntry(at: Date(), menu: menu, pick: nil, why: "", inputTokens: 0, outputTokens: 0,
                                   dollars: 0, failure: failure)
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

    /* One quiet retry for a busy or failing service. nil: nothing came back at all. */
    private func post(_ body: Data, key: String) async -> (Int, Data)? {
        for attempt in 0..<2 {
            var request = URLRequest(url: URL(string: ClaudePick.endpoint)!)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(ClaudePick.version, forHTTPHeaderField: "anthropic-version")
            request.setValue(ClaudePick.beta, forHTTPHeaderField: "anthropic-beta")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else { return nil }
            if (http.statusCode == 429 || http.statusCode >= 500) && attempt == 0 {
                guard (try? await Task.sleep(nanoseconds: 3_000_000_000)) != nil else { return nil }
                continue
            }
            return (http.statusCode, data)
        }
        return nil
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
