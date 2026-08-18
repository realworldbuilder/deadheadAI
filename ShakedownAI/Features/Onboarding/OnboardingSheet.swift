import AuthenticationServices
import SwiftUI

/// First-launch welcome. Local account by default; the Sign in with Apple
/// button is present behind the AuthProvider seam (full flow needs a signed
/// build, so the local path is primary in this build).
struct OnboardingSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @AppStorage("displayName") private var storedName = ""
    @State private var name = ""

    var body: some View {
        ZStack {
            SpaceBackground()
            VStack(spacing: 22) {
                Spacer()

                SpiralMandala(size: 110)

                VStack(spacing: 8) {
                    Text("DEADHEAD AI")
                        .font(Theme.display(34))
                        .kerning(1.5)
                        .chromeText()
                    Text("The music never stopped.\nNeither should discovering it.")
                        .font(.system(.body, design: .serif).italic())
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    onboardRow(icon: "sparkles", text: "An AI companion that knows every tape — and learns your ears.")
                    onboardRow(icon: "dot.radiowaves.left.and.right", text: "Streams straight from the Internet Archive's Grateful Dead collection.")
                    onboardRow(icon: "book.closed", text: "Journeys, journals, and thirty years to explore.")
                }
                .padding(.horizontal, 10)

                Spacer()

                TextField("What should we call you?", text: $name)
                    .font(Theme.body)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))

                Button {
                    finish(with: name.isEmpty ? "Deadhead" : name)
                } label: {
                    Text("Hop on the Bus")
                        .font(Theme.mono(15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentGradient))
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                            finish(with: name.isEmpty ? "Deadhead" : name)
                            return
                        }
                        finishWithApple(credential: credential)
                    case .failure:
                        // Unsigned simulator builds can't complete the Apple
                        // flow; fall back to the local account (offline brain).
                        finish(with: name.isEmpty ? "Deadhead" : name)
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .opacity(0.9)

                Text(KeychainStore.keyAwaitingUnlock
                     ? "Sign in with Apple to unlock the full AI brain and keep your shelves & journal in iCloud — free, on the house. Or hop on without an account; everything stays on this device."
                     : "No account required. Everything lives on this device.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
        .interactiveDismissDisabled()
    }

    private func onboardRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func finish(with chosenName: String) {
        storedName = chosenName
        Task {
            _ = try? await env.authProvider.signInLocally(displayName: chosenName)
            dismiss()
        }
    }

    private func finishWithApple(credential: ASAuthorizationAppleIDCredential) {
        let chosenName = name.isEmpty
            ? (credential.fullName?.givenName ?? "Deadhead")
            : name
        storedName = chosenName
        KeychainStore.unlockAI()
        Task {
            _ = try? await env.authProvider.signInWithApple(userID: credential.user,
                                                           displayName: chosenName)
            dismiss()
            // Rebuild the environment so the cloud store reopens with sync on.
            NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
        }
    }
}
