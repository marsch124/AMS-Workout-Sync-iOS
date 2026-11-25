import Foundation
import Security

/*
 * His Anthropic key lives in the Keychain and nowhere else: not in the code,
 * not in the settings, not in a log, not in the meter. The repository is
 * public. Available after the first unlock, so a quiet answer can be asked
 * for while the phone is locked.
 */
enum ClaudeKey {
    private static let service = "com.schabbauer.AMSWorkoutSync.claude"
    private static let account = "anthropic-key"

    private static var match: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        remove()
        var item = match
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        var query = match
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static func remove() {
        SecItemDelete(match as CFDictionary)
    }

    /* The picture switch: a saved key, invented rows, and no network at all. */
    static var isFake: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_FAKE_CLAUDE"] != nil
        #else
        return false
        #endif
    }

    static var isSaved: Bool { isFake || read() != nil }

    /* What is shown instead of the key. */
    static let masked = "••••••••••••"
}
