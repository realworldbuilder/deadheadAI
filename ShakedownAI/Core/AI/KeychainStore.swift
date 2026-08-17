import Foundation

/// Resolves the OpenAI API key bundled into this build. The key ships in the
/// app so AI features are free for users and is active whenever present —
/// the earlier Sign-in-with-Apple soft gate is disabled (see git history to
/// restore it). The previous user-supplied keychain flow was also removed.
nonisolated enum KeychainStore {
    private static let unlockDefaultsKey = "aiAccessUnlocked"

    /// Build-time key injected from Config/Secrets.xcconfig via Info.plist;
    /// nil in clean checkouts and keyless CI builds.
    static var bundledAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String,
              !key.isEmpty else { return nil }
        return key
    }

    /// True once the user has completed Sign in with Apple on this device.
    static var aiUnlocked: Bool {
        UserDefaults.standard.bool(forKey: unlockDefaultsKey)
    }

    static func unlockAI() {
        UserDefaults.standard.set(true, forKey: unlockDefaultsKey)
    }

    static func lockAI() {
        UserDefaults.standard.removeObject(forKey: unlockDefaultsKey)
    }

    /// The key AI calls should use; the bundled key, whenever one ships.
    static func resolveAPIKey() -> String? { bundledAPIKey }

    static var hasUsableKey: Bool { resolveAPIKey() != nil }

    /// Always false while the sign-in gate is disabled — keeps the
    /// "sign in to unlock" UI hidden without touching its call sites.
    static var keyAwaitingUnlock: Bool { false }
}
