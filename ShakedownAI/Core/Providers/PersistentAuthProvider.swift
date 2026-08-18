import AuthenticationServices
import Foundation
import OSLog

extension Notification.Name {
    /// Posted after sign-in/sign-out persists, so the app can rebuild its
    /// environment (and with it the cloud store's sync mode).
    static let shakedownAuthChanged = Notification.Name("shakedownAuthChanged")
}

/// The real auth seam: a UserDefaults-backed account that survives relaunch.
/// Apple sign-in is the key that unlocks the bundled AI brain and iCloud sync
/// of shelves & journal; a local account keeps everything on-device.
@Observable
final class PersistentAuthProvider: AuthProvider {
    private nonisolated enum Keys {
        static let displayName = "account.displayName"
        static let appleUserID = "account.appleUserID"
        static let isLocal = "account.isLocal"
    }

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "ai.deadheads", category: "auth")
    private(set) var currentAccount: UserAccount?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let name = defaults.string(forKey: Keys.displayName) {
            currentAccount = UserAccount(displayName: name,
                                         appleUserID: defaults.string(forKey: Keys.appleUserID))
        }
    }

    /// Readable before the ModelContainer exists — this is the single source
    /// of truth for whether the cloud store opens with CloudKit sync on.
    nonisolated static func persistedAppleUserID(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: Keys.appleUserID)
    }

    func signInLocally(displayName: String) async throws -> UserAccount {
        let account = UserAccount(displayName: displayName, appleUserID: nil)
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.removeObject(forKey: Keys.appleUserID)
        defaults.set(true, forKey: Keys.isLocal)
        currentAccount = account
        return account
    }

    func signInWithApple(userID: String, displayName: String) async throws -> UserAccount {
        let account = UserAccount(displayName: displayName, appleUserID: userID)
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.set(userID, forKey: Keys.appleUserID)
        defaults.set(false, forKey: Keys.isLocal)
        currentAccount = account
        return account
    }

    func signOut() async {
        defaults.removeObject(forKey: Keys.displayName)
        defaults.removeObject(forKey: Keys.appleUserID)
        defaults.removeObject(forKey: Keys.isLocal)
        currentAccount = nil
        KeychainStore.lockAI()
    }

    /// A revoked Apple ID (user removed the app under Settings > Apple ID)
    /// must relock AI and stop sync. Called once at launch.
    func validateAppleCredentialAtLaunch() async {
        guard let userID = currentAccount?.appleUserID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        switch state {
        case .revoked, .notFound:
            log.notice("Apple credential no longer valid (\(String(describing: state), privacy: .public)); signing out")
            await signOut()
            NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
        default:
            break
        }
    }
}
