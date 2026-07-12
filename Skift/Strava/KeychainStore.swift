import Foundation
import Security

/// Minimal Keychain Services wrapper for the small secrets `StravaAccount`
/// needs (client secret, OAuth tokens, athlete name) — not a general-purpose
/// wrapper. All items share one service name so they're easy to find (and
/// wipe) together; `account` distinguishes the item within that service.
enum KeychainStore {
    static let service = "org.skift.strava"

    static func setData(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Delete-then-add avoids dealing with SecItemUpdate's separate
        // query/attributes split for what is always a full overwrite here.
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func data(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - String convenience

    static func setString(_ value: String, account: String) {
        setData(Data(value.utf8), account: account)
    }

    static func string(account: String) -> String? {
        data(account: account).flatMap { String(data: $0, encoding: .utf8) }
    }
}
