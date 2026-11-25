import Foundation
import Security

/*
 * His Garmin key lives in the Keychain and nowhere else: not in the code, not
 * in the settings, not in a log, not in the file of morning numbers. The
 * repository is public, so the key is never written into anything that is
 * kept. Available after the first unlock, so the morning read can run while
 * the phone is locked.
 */
enum GarminKey {
    private static let service = "com.schabbauer.AMSWorkoutSync.garmin"
    private static let account = "personal-key"

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

    /* The picture switch gives invented numbers and needs no key at all. */
    static var isFake: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_FAKE_GARMIN"] != nil
        #else
        return false
        #endif
    }

    static var isSaved: Bool { isFake || read() != nil }
}
