import AuthenticationServices
import SwiftUI

/// First-launch welcome. Local account by default; the Sign in with Apple
/// button is present behind the AuthProvider seam (full flow needs a signed
/// build, so the local path is primary in this build).
struct OnboardingSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("displayName") private var storedName = ""
    @State private var name = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            AppMark(size: 72)

            VStack(spacing: 8) {
                Text("Nethead")
                    .font(Theme.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("When did the bus come by for you?")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                onboardRow(icon: "sparkles", text: "An old head who's spun every tape, riding shotgun.")
                onboardRow(icon: "dot.radiowaves.left.and.right", text: "Every tape on archive.org, '65 to '95 — boards, auds, matrixes. Nothing re-hosted.")
                onboardRow(icon: "book.closed", text: "The runs, the setlists, a journal, and thirty years of shows.")
            }
            .padding(.horizontal, 10)

            Spacer()

            TextField("What should we call you?", text: $name)
                .font(Theme.body)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))

            Button("Get on the Bus") {
                finish(with: name.isEmpty ? "Nethead" : name)
            }
            .buttonStyle(.primary(fullWidth: true))

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                        finish(with: name.isEmpty ? "Nethead" : name)
                        return
                    }
                    finishWithApple(credential: credential)
                case .failure:
                    // Unsigned simulator builds can't complete the Apple
                    // flow; fall back to the local account.
                    finish(with: name.isEmpty ? "Nethead" : name)
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Sign in with Apple to keep your shelves and journal in iCloud. Or skip it — everything stays on this device.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(Theme.background)
        .presentationBackground(Theme.background)
        .interactiveDismissDisabled()
    }

    private func onboardRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textSecondary)
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
            ? (credential.fullName?.givenName ?? "Nethead")
            : name
        storedName = chosenName
        Task {
            _ = try? await env.authProvider.signInWithApple(userID: credential.user,
                                                           displayName: chosenName)
            dismiss()
            // Rebuild the environment so the cloud store reopens with sync on.
            NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
        }
    }
}
