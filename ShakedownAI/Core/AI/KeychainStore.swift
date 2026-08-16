import Foundation
import Security

/// Minimal keychain wrapper for the OpenAI API key.
nonisolated enum KeychainStore {
    private static let service = "ai.deadheads.openai"
    private static let account = "api-key"

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteAPIKey()
        guard !trimmed.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasAPIKey: Bool { loadAPIKey() != nil }

    /// Build-time key injected from Config/Secrets.xcconfig via Info.plist;
    /// nil in clean checkouts and CI builds.
    static var bundledAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String,
              !key.isEmpty else { return nil }
        return key
    }

    /// The key AI calls should use: the user's keychain key wins, then the bundled one.
    static func resolveAPIKey() -> String? { loadAPIKey() ?? bundledAPIKey }

    static var hasUsableKey: Bool { resolveAPIKey() != nil }
}
