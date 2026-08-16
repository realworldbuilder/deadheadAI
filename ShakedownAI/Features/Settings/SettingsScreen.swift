import SwiftUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var apiKeyField = ""
    @State private var hasKey = KeychainStore.hasAPIKey
    private let hasBundledKey = KeychainStore.bundledAPIKey != nil
    @State private var showingKeySaved = false
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
        .onAppear { cacheSize = env.cache.approximateSizeBytes }
    }

    // MARK: - AI

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intelligence").sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 12) {
                let aiActive = hasKey || hasBundledKey
                HStack {
                    Image(systemName: aiActive ? "brain.filled.head.profile" : "brain.head.profile")
                        .foregroundStyle(aiActive ? Theme.sage : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aiActive ? "OpenAI connected" : "Offline brain active")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(hasKey
                             ? "Recommendations and chat use your OpenAI key, grounded in real archive data."
                             : hasBundledKey
                             ? "Recommendations and chat use this build's included OpenAI key, grounded in real archive data. Paste your own key below to use it instead."
                             : "Everything works offline from the curated knowledge base. Add an OpenAI key to upgrade the prose and free-form chat.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if hasKey {
                    Button(role: .destructive) {
                        KeychainStore.deleteAPIKey()
                        hasKey = false
                    } label: {
                        Text("Remove API Key")
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.rose)
                    }
                } else {
                    SecureField("Paste your OpenAI API key (sk-…)", text: $apiKeyField)
                        .font(Theme.mono(13))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
                    Button {
                        KeychainStore.saveAPIKey(apiKeyField)
                        apiKeyField = ""
                        hasKey = KeychainStore.hasAPIKey
                        showingKeySaved = hasKey
                    } label: {
                        Text("Save Key")
                            .font(Theme.mono(13, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.accentGradient))
                    }
                    .disabled(apiKeyField.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Stored in the Keychain, sent only to api.openai.com.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .alert("Key saved", isPresented: $showingKeySaved) {
            Button("Right on", role: .cancel) {}
        } message: {
            Text("AI features will now use OpenAI, with the offline brain as backup.")
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
                Text("DEADHEADS.AI")
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
