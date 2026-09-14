import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

/*
 * Dropbox, spoken directly — the native counterpart of js/dropbox.js.
 *
 * OAuth with PKCE, as the web app does it and for the same reason: there is no
 * server of ours to keep a secret in, so a proof key is made per sign-in and
 * never leaves the phone, and the app key is public by design. The sign-in
 * sheet returns through native-auth.html on the web app's site (Dropbox only
 * returns to registered addresses), which hands the code on to
 * amsworkoutsync://oauth.
 *
 * The refresh token is kept in the Keychain, not in UserDefaults: it is the
 * key to his Dropbox, and the Keychain is where iOS keeps such things.
 */
enum DropboxError: LocalizedError {
    case notConnected, cancelled, refused(String), http(Int, String), conflict, badResponse

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Dropbox."
        case .cancelled: return "Sign-in was cancelled."
        case .refused(let why): return "Dropbox refused the connection: \(why)"
        case .http(let code, let body): return "Dropbox answered \(code). \(body.prefix(160))"
        case .conflict: return "The workbook changed in Dropbox since it was read."
        case .badResponse: return "Dropbox sent an answer the app could not read."
        }
    }
}

struct DropboxFile: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String        // path_display, for showing
    let pathLower: String   // path_lower, for asking
    let isFolder: Bool
}

@MainActor
final class Dropbox: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Dropbox()

    static let appKey = "fvjprux9drkn7kp"
    static let redirectURI = "https://marsch124.github.io/AMS-Workout-Sync/native-auth.html"
    static let callbackScheme = "amsworkoutsync"

    private let authURL = "https://www.dropbox.com/oauth2/authorize"
    private let tokenURL = "https://api.dropboxapi.com/oauth2/token"
    private let apiURL = "https://api.dropboxapi.com/2"
    private let contentURL = "https://content.dropboxapi.com/2"

    private var accessToken: String?
    private var accessExpires = Date.distantPast
    private var session: ASWebAuthenticationSession?

    var isConnected: Bool { Keychain.read("dropbox.refresh") != nil }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    // MARK: sign-in

    func connect() async throws -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = String(Self.base64URL(Data(bytes)).prefix(128))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var stateBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, stateBytes.count, &stateBytes)
        let state = Self.base64URL(Data(stateBytes))

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.appKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "state", value: state)
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: Self.callbackScheme) { url, error in
                if let url { continuation.resume(returning: url); return }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: DropboxError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? DropboxError.badResponse)
                }
            }
            session.presentationContextProvider = self
            // Share Safari's cookies, so a Dropbox login he already has is used.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") { throw DropboxError.refused(value("error_description") ?? error) }
        guard value("state") == state else { throw DropboxError.refused("the answer did not belong to this sign-in") }
        guard let code = value("code") else { throw DropboxError.badResponse }

        let tokens = try await form(tokenURL, [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": Self.appKey,
            "code_verifier": verifier,
            "redirect_uri": Self.redirectURI
        ])
        guard let refresh = tokens["refresh_token"] as? String else { throw DropboxError.badResponse }
        Keychain.write("dropbox.refresh", refresh)
        remember(tokens)

        let who = try await rpc("users/get_current_account", nil)
        let name = ((who["name"] as? [String: Any])?["display_name"] as? String) ?? ""
        let email = who["email"] as? String ?? ""
        UserDefaults.standard.set(email.isEmpty ? name : email, forKey: "dropbox.account")
        return email.isEmpty ? name : email
    }

    func disconnect() {
        Keychain.delete("dropbox.refresh")
        accessToken = nil
        UserDefaults.standard.removeObject(forKey: "dropbox.account")
    }

    var account: String { UserDefaults.standard.string(forKey: "dropbox.account") ?? "" }

    // MARK: tokens

    private func remember(_ tokens: [String: Any]) {
        accessToken = tokens["access_token"] as? String
        let seconds = (tokens["expires_in"] as? Double) ?? 14400
        accessExpires = Date().addingTimeInterval(seconds - 60)
    }

    private func token() async throws -> String {
        if let accessToken, Date() < accessExpires { return accessToken }
        guard let refresh = Keychain.read("dropbox.refresh") else { throw DropboxError.notConnected }
        let tokens = try await form(tokenURL, ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": Self.appKey])
        remember(tokens)
        guard let accessToken else { throw DropboxError.badResponse }
        return accessToken
    }

    // MARK: files

    func list(_ path: String) async throws -> [DropboxFile] {
        var result = try await rpc("files/list_folder", ["path": path, "limit": 500])
        var entries = result["entries"] as? [[String: Any]] ?? []
        while result["has_more"] as? Bool == true, let cursor = result["cursor"] as? String {
            result = try await rpc("files/list_folder/continue", ["cursor": cursor])
            entries += result["entries"] as? [[String: Any]] ?? []
        }
        return entries.compactMap { e in
            guard let name = e["name"] as? String, let lower = e["path_lower"] as? String else { return nil }
            let isFolder = e[".tag"] as? String == "folder"
            guard isFolder || name.lowercased().hasSuffix(".xlsx") else { return nil }
            return DropboxFile(name: name, path: e["path_display"] as? String ?? lower, pathLower: lower, isFolder: isFolder)
        }.sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
    }

    /* The file and the revision it is at — the revision is what makes a later upload safe. */
    func download(_ path: String) async throws -> (data: Data, rev: String, name: String) {
        var request = URLRequest(url: URL(string: contentURL + "/files/download")!, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiArg(["path": path]), forHTTPHeaderField: "Dropbox-API-Arg")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 else { throw DropboxError.http(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let header = http.value(forHTTPHeaderField: "Dropbox-API-Result"),
              let meta = try JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any],
              let rev = meta["rev"] as? String else { throw DropboxError.badResponse }
        return (data, rev, meta["name"] as? String ?? "")
    }

    // MARK: plumbing

    private func rpc(_ endpoint: String, _ body: [String: Any]?) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: apiURL + "/" + endpoint)!, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 else { throw DropboxError.http(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func form(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 else { throw DropboxError.http(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DropboxError.badResponse }
        return json
    }

    /* Dropbox-API-Arg is JSON in a header, so anything outside ASCII must be escaped as \uXXXX. */
    static func apiArg(_ object: [String: Any]) -> String {
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        var out = ""
        for unit in json.utf16 {
            if unit < 0x80 { out.unicodeScalars.append(UnicodeScalar(unit)!) }
            else { out += String(format: "\\u%04x", unit) }
        }
        return out
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.schabbauer.AMSWorkoutSync",
         kSecAttrAccount as String: key]
    }

    static func write(_ key: String, _ value: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
