import Foundation

/// Resolves the OpenAI API key bundled into this build. The key ships in the
/// app so AI features are free for every user with no sign-in; the spend
/// ceiling is the hard budget limit on the OpenAI project, not anything in the
/// client. Sign in with Apple is unrelated to AI — it only turns on iCloud sync.
nonisolated enum KeychainStore {
    /// Build-time key injected from Config/Secrets.xcconfig via Info.plist;
    /// nil in clean checkouts and keyless CI builds.
    static var bundledAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String,
              !key.isEmpty else { return nil }
        return key
    }

    /// The key AI calls should use; nil when the build shipped without one.
    static func resolveAPIKey() -> String? { bundledAPIKey }

    static var hasUsableKey: Bool { resolveAPIKey() != nil }
}
