import AuthenticationServices
import SwiftUI

/// One line under the shelves for a head riding along: sign in with Apple
/// and they follow you. Shows nothing when signed in, when there's no
/// notesfile, or when there's nothing on the shelf yet.
struct ShelvesSignInNudge: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonceHash: String?
    @State private var problem: String?

    var body: some View {
        if env.authProvider.currentAccount == nil, env.api != nil, !env.library.collections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in with Apple to keep your shelves on every device.")
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textSecondary)
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                    request.nonce = nonceHash
                } onCompletion: { result in
                    if case .success(let auth) = result,
                       let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                       let token = credential.identityToken {
                        Task {
                            do {
                                _ = try await env.authProvider.signInWithApple(identityToken: token, fullName: credential.fullName)
                            } catch {
                                problem = "Bummer — that sign-in didn't take. Try again from Settings."
                            }
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(nonceHash == nil)
                if let problem {
                    Text(problem)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .task { nonceHash = await env.authProvider.prepareAppleSignIn() }
        }
    }
}
