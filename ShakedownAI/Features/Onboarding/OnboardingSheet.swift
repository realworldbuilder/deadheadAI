import AuthenticationServices
import SwiftUI

/// First-launch welcome. Ride along with everything on this phone, or sign
/// in with Apple so your shelves are the same here and on the web. Unsigned
/// simulator builds can't finish the Apple flow and just ride along.
struct OnboardingSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonceHash: String?
    @State private var problem: String?

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
                onboardRow(icon: "book.closed", text: "The jams, the setlists, a journal, and thirty years of shows.")
            }
            .padding(.horizontal, 10)

            Spacer()

            if let problem {
                Text(problem)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
                request.nonce = nonceHash
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                    finishWithApple(credential: credential)
                case .failure:
                    // Cancelled, or an unsigned simulator build: nothing to do.
                    break
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(nonceHash == nil)

            Button("Just ride along") {
                dismiss()
            }
            .buttonStyle(.secondary)

            Text("Sign in with Apple to keep your shelves the same here and on the web. Or ride along — everything stays on this phone, and you can sign in later from Settings.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(Theme.background)
        .presentationBackground(Theme.background)
        .interactiveDismissDisabled()
        .task { nonceHash = await env.authProvider.prepareAppleSignIn() }
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

    private func finishWithApple(credential: ASAuthorizationAppleIDCredential) {
        guard let token = credential.identityToken else { return }
        Task {
            do {
                _ = try await env.authProvider.signInWithApple(identityToken: token, fullName: credential.fullName)
                dismiss()
            } catch NetheadAPIError.offline {
                problem = "The notesfile didn't answer. Check your connection, or ride along for now."
                nonceHash = await env.authProvider.prepareAppleSignIn()
            } catch {
                problem = "Bummer — that sign-in didn't take. Try again, or ride along for now."
                nonceHash = await env.authProvider.prepareAppleSignIn()
            }
        }
    }
}
