import Foundation
import Security

/// Small secrets (the ElevenLabs key pasted in the app, the login token) in the Keychain,
/// so they never live in source code, UserDefaults or git.
nonisolated enum KeychainStore {
    static let elevenLabs = (service: "ElevenLabs", account: "api-key")
    static let backendToken = (service: "Backend", account: "token")

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func load(service: String = elevenLabs.service, account: String = elevenLabs.account) -> String {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String, service: String = elevenLabs.service, account: String = elevenLabs.account) {
        let query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
