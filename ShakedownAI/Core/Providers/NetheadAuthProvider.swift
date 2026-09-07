import CryptoKit
import Foundation
import OSLog
import UIKit

extension Notification.Name {
    /// Posted after the phone gets on or off the bus, so the sync engine and
    /// the screens that show the handle can catch up.
    static let shakedownAuthChanged = Notification.Name("shakedownAuthChanged")
}

/// The real account seam: Sign in with Apple, backed by the notesfile. The
/// session token lives in the Keychain (via the API client); the account
/// itself in UserDefaults so the first frame already knows it.
@Observable
final class NetheadAuthProvider: AuthProvider {
    private nonisolated enum Keys {
        static let id = "nethead.account.id"
        static let handle = "nethead.account.handle"
        static let firstShow = "nethead.account.firstShow"
    }

    private let defaults: UserDefaults
    private let api: NetheadAPIClient?
    private let log = Logger(subsystem: "ai.deadheads", category: "auth")
    private(set) var currentAccount: NetheadAccount?
    /// The raw nonce behind the Apple request in flight.
    private var pendingNonce: String?

    init(api: NetheadAPIClient?, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        // No token means no session, whatever the defaults remember.
        if let api, api.hasToken, let account = Self.persistedAccount(in: defaults) {
            currentAccount = account
        } else {
            Self.forget(in: defaults)
        }
    }

    nonisolated static func persistedAccount(in defaults: UserDefaults = .standard) -> NetheadAccount? {
        guard let id = defaults.string(forKey: Keys.id), let handle = defaults.string(forKey: Keys.handle) else { return nil }
        return NetheadAccount(id: id, handle: handle, firstShow: defaults.string(forKey: Keys.firstShow))
    }

    private nonisolated static func forget(in defaults: UserDefaults) {
        defaults.removeObject(forKey: Keys.id)
        defaults.removeObject(forKey: Keys.handle)
        defaults.removeObject(forKey: Keys.firstShow)
    }

    var isConfigured: Bool { api != nil }

    func prepareAppleSignIn() async -> String? {
        guard let api else { return nil }
        guard let nonce = try? await api.appleNonce() else { return nil }
        pendingNonce = nonce
        return Self.sha256Hex(nonce)
    }

    func signInWithApple(identityToken: Data, fullName: PersonNameComponents?) async throws -> NetheadAccount {
        guard let api else { throw NetheadAPIError.notConfigured }
        guard let nonce = pendingNonce, let token = String(data: identityToken, encoding: .utf8) else {
            throw NetheadAPIError.message("That sign-in didn't line up. Try again.")
        }
        pendingNonce = nil
        let reply = try await api.signInWithApple(identityToken: token, nonce: nonce, name: fullName?.givenName, device: UIDevice.current.name)
        let account = NetheadAccount(id: reply.head.id, handle: reply.head.handle, firstShow: reply.head.firstShow)
        remember(account)
        NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
        return account
    }

    nonisolated static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func signOut() async {
        await api?.signOut()
        Self.forget(in: defaults)
        currentAccount = nil
        NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
    }

    func refresh() async {
        guard currentAccount != nil, let api else { return }
        do {
            let me = try await api.me()
            remember(NetheadAccount(id: me.head.id, handle: me.head.handle, firstShow: me.head.firstShow))
        } catch NetheadAPIError.notOnTheBus {
            log.notice("The notesfile no longer knows this phone; signing out")
            Self.forget(in: defaults)
            currentAccount = nil
            NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
        } catch {
            // Offline or a hiccup: keep riding.
        }
    }

    private func remember(_ account: NetheadAccount) {
        defaults.set(account.id, forKey: Keys.id)
        defaults.set(account.handle, forKey: Keys.handle)
        defaults.set(account.firstShow, forKey: Keys.firstShow)
        currentAccount = account
    }
}
