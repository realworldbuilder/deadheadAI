import Foundation

/// Resolves the OpenAI API key bundled into this build. The app ships its
/// own key so AI features are free for users; the previous user-supplied
/// keychain flow was removed (see git history if it needs to come back).
nonisolated enum KeychainStore {
    /// Build-time key injected from Config/Secrets.xcconfig via Info.plist;
    /// nil in clean checkouts and keyless CI builds.
    static var bundledAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String,
              !key.isEmpty else { return nil }
        return key
    }

    /// The key AI calls should use.
    static func resolveAPIKey() -> String? { bundledAPIKey }

    static var hasUsableKey: Bool { resolveAPIKey() != nil }
}
