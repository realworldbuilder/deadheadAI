import Foundation

/// Resolves the OpenAI API key bundled into this build. The key ships in the
/// app so AI features are free for users, but stays locked until the user
/// signs in with Apple — until then every AI call falls back to the offline
/// LocalKnowledgeAI brain. DEBUG builds skip the gate (Apple sign-in can't
/// complete in unsigned simulator builds); pass `--force-ai-gate` to exercise
/// the locked experience in development.
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
        #if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--force-ai-gate") { return true }
        #endif
        return UserDefaults.standard.bool(forKey: unlockDefaultsKey)
    }

    static func unlockAI() {
        UserDefaults.standard.set(true, forKey: unlockDefaultsKey)
    }

    static func lockAI() {
        UserDefaults.standard.removeObject(forKey: unlockDefaultsKey)
    }

    /// The gate's pure core, separated so tests can exercise the truth table
    /// without touching UserDefaults or build configuration.
    static func resolveAPIKey(bundled: String?, unlocked: Bool) -> String? {
        unlocked ? bundled : nil
    }

    /// The key AI calls should use; nil until Apple sign-in unlocks it.
    static func resolveAPIKey() -> String? {
        resolveAPIKey(bundled: bundledAPIKey, unlocked: aiUnlocked)
    }

    static var hasUsableKey: Bool { resolveAPIKey() != nil }

    /// A key ships in this build but the user hasn't signed in to unlock it.
    static var keyAwaitingUnlock: Bool { bundledAPIKey != nil && !aiUnlocked }
}
