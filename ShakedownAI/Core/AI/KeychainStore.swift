import Foundation

/// Resolves the OpenAI API key bundled into this build. The key ships in the
/// app so AI features are free for users, but it stays dormant until the user
/// signs in with Apple — that's the (soft) gate on our spend. The previous
/// user-supplied keychain flow was removed (see git history if it needs to
/// come back).
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

    /// The key AI calls should use; nil until Apple sign-in unlocks it.
    static func resolveAPIKey() -> String? { aiUnlocked ? bundledAPIKey : nil }

    static var hasUsableKey: Bool { resolveAPIKey() != nil }

    /// A key ships in this build but the user hasn't signed in to unlock it.
    static var keyAwaitingUnlock: Bool { bundledAPIKey != nil && !aiUnlocked }
}
