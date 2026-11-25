import Foundation

/*
 * Why Claude could not choose, when the reason does not pass by itself and
 * he is the only one who can set it right: the key is no longer accepted,
 * the Anthropic account has no credit left, or this app's own month cap is
 * reached. The app then says so in one line — on Settings → Claude and on the
 * suggestion card — so there is nothing for him to remember. A hiccup (no
 * network, Anthropic busy) is none of these: it gets a line in the log only.
 */
public enum ClaudeTrouble: String, Codable, Sendable, Equatable, CaseIterable {
    case keyRefused, noCredit, capReached

    /* What Anthropic's reply means. nil: an answer, or a hiccup that passes by itself. */
    public static func read(status: Int, body: Data) -> ClaudeTrouble? {
        guard status != 200 else { return nil }
        var type = "", message = ""
        if let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
           let error = root["error"] as? [String: Any] {
            type = (error["type"] as? String) ?? ""
            message = ((error["message"] as? String) ?? "").lowercased()
        }
        // Asked first: Anthropic has reported an empty account under more than one status.
        if status == 402 || type == "billing_error" || message.contains("credit balance") { return .noCredit }
        if status == 401 || status == 403 { return .keyRefused }
        return nil
    }

    /* Settings → Claude, under the key. */
    public var pageLine: String {
        switch self {
        case .keyRefused:
            return "Anthropic no longer accepts this key. It may have ended or been removed. Until you type a new one, the rule book chooses alone."
        case .noCredit:
            return "Your Anthropic account has no credit left. Until you add credit at Anthropic, the rule book chooses alone."
        case .capReached:
            return "This month\u{2019}s 5 US dollars are used. Claude chooses again next month. Until then the rule book chooses alone."
        }
    }

    /* On the suggestion card, under the reason. */
    public var cardLine: String {
        switch self {
        case .keyRefused: return "Claude could not choose: Anthropic no longer accepts your key. Settings \u{2192} Claude."
        case .noCredit: return "Claude could not choose: your Anthropic account has no credit left. Settings \u{2192} Claude."
        case .capReached: return "Claude could not choose: this month\u{2019}s 5 US dollars are used."
        }
    }

    /* The end of the row in Settings: "On, but not choosing · …". */
    public var rowWords: String {
        switch self {
        case .keyRefused: return "key no longer accepted"
        case .noCredit: return "no credit left at Anthropic"
        case .capReached: return "this month\u{2019}s 5 US dollars are used"
        }
    }

    /* One line for the log under "What Claude answered". */
    public var logWords: String {
        switch self {
        case .keyRefused: return "Anthropic did not accept the key"
        case .noCredit: return "Anthropic says the account has no credit left"
        case .capReached: return "This month\u{2019}s 5 US dollars are used"
        }
    }

    /* Only he can set these right; the month cap ends by itself. */
    public var needsHim: Bool { self != .capReached }
}
