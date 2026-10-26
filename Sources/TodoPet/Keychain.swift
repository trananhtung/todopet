import Foundation
import Security

/// Stores secrets (Todoist token, Anthropic API key) in the login Keychain, never in plain files.
enum Keychain {
    enum Item: String {
        case todoist = "todoist-api-token"
        case anthropic = "anthropic-api-key"
    }

    private static let service = "com.todopet.mochi"

    private static func baseQuery(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: item.rawValue]
    }

    static func read(_ item: Item = .todoist) -> String? {
        var q = baseQuery(item)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }

    @discardableResult
    static func save(_ secret: String, _ item: Item = .todoist) -> Bool {
        delete(item)
        var q = baseQuery(item)
        q[kSecValueData as String] = Data(secret.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ item: Item = .todoist) {
        SecItemDelete(baseQuery(item) as CFDictionary)
    }
}
