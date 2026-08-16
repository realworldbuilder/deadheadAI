import AuthenticationServices
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var aiActive = KeychainStore.hasUsableKey
    @State private var cacheSize = 0
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        aiSection
                        providerSection
                        cacheSection
                        aboutSection
                    }
                    .padding(Theme.screenPadding)
                }
                .withMiniPlayer()
            }
            .navigationTitle("Settings")
        }
        .tint(Theme.accent)
        .onAppear {
            cacheSize = env.cache.approximateSizeBytes
            aiActive = KeychainStore.hasUsableKey
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intelligence").sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: aiActive ? "brain.filled.head.profile" : "brain.head.profile")
                        .foregroundStyle(aiActive ? Theme.sage : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aiStatusTitle)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(aiStatusDetail)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if KeychainStore.keyAwaitingUnlock {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        if case .success(let auth) = result,
                           let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                            unlockAI(credential: credential)
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private var aiStatusTitle: String {
        if aiActive { return "Deadhead AI connected" }
        if KeychainStore.keyAwaitingUnlock { return "Full AI brain locked" }
        return "Offline brain active"
    }

    private var aiStatusDetail: String {
        if aiActive {
            return "AI is on the house. Recommendations and chat are grounded in real archive data, with the offline brain as backup."
        }
        if KeychainStore.keyAwaitingUnlock {
            return "Sign in with Apple to unlock free AI recommendations and chat. Until then, everything runs on the offline brain."
        }
        return "Everything works offline from the curated knowledge base. This build shipped without an AI key, so free-form chat runs locally."
    }

    private func unlockAI(credential: ASAuthorizationAppleIDCredential) {
        KeychainStore.unlockAI()
        aiActive = KeychainStore.hasUsableKey
        let fallbackName = displayName.isEmpty ? "Deadhead" : displayName
        Task {
            _ = try? await env.authProvider.signInWithApple(
                userID: credential.user,
                displayName: credential.fullName?.givenName ?? fallbackName)
        }
    }

    // MARK: - Providers

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Providers").sectionHeaderStyle()
            VStack(spacing: 0) {
                providerRow(name: "Recordings", value: "Internet Archive", icon: "building.columns")
                Divider().overlay(Theme.stroke.opacity(0.5))
                providerRow(name: "Streaming", value: "Direct from archive.org", icon: "dot.radiowaves.left.and.right")
                Divider().overlay(Theme.stroke.opacity(0.5))
                providerRow(name: "AI", value: env.aiProvider.name, icon: "sparkles")
            }
            .cardStyle()
            Text("Provider-based architecture: future versions can plug in official releases, Apple Music, or Relisten-compatible APIs.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func providerRow(name: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            Text(name)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(13)
    }

    // MARK: - Cache

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata Cache").sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 10) {
                Text("Setlists, reviews, and search results are cached so the app works offline and stays polite to the archive. Audio is never stored.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                        .font(Theme.mono(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Clear Cache") {
                        env.cache.clearAll()
                        cacheSize = env.cache.approximateSizeBytes
                    }
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.rose)
                }
            }
            .padding(Theme.cardPadding)
            .cardStyle()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About").sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 8) {
                Text("DEADHEAD AI")
                    .font(Theme.display(22))
                    .kerning(1)
                    .chromeText()
                Text("The music never stopped. Neither should discovering it.")
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(Theme.textSecondary)
                Text("Recordings stream directly from the Internet Archive's Grateful Dead collection, preserved by tapers and archivists over six decades. This app hosts no music — it adds the intelligence layer.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}
