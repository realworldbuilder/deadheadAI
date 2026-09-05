import AuthenticationServices
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme
    @State private var aiActive = KeychainStore.hasUsableKey
    @State private var cacheSize = 0
    @State private var displayName = ""
    @State private var confirmingClearCache = false
    @State private var confirmingSignOut = false
    @State private var confirmingDeleteDownloads = false
    @State private var catalogStamp: String?
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.dark

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                accountSection
                aiSection
                providerSection
                downloadsSection
                cacheSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .withMiniPlayer()
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear the metadata cache?",
                isPresented: $confirmingClearCache,
                titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive) {
                    env.cache.clearAll()
                    cacheSize = env.cache.approximateSizeBytes
                }
            } message: {
                Text("Setlists and search results will re-download from the archive as you browse.")
            }
            .sensoryFeedback(.warning, trigger: confirmingClearCache) { !$0 && $1 }
            .confirmationDialog(
                "Delete all downloads?",
                isPresented: $confirmingDeleteDownloads,
                titleVisibility: .visible
            ) {
                Button("Delete All Downloads", role: .destructive) {
                    env.downloads.deleteAllDownloads()
                }
            } message: {
                Text("Every saved show is removed from this device. Streaming is unaffected, and you can download them again any time.")
            }
            .sensoryFeedback(.warning, trigger: confirmingDeleteDownloads) { !$0 && $1 }
            .confirmationDialog(
                "Sign out?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await env.authProvider.signOut()
                        NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
                    }
                }
            } message: {
                Text("iCloud syncing stops. Your shelves and journal stay on this device, and the copies already in iCloud stay there too.")
            }
        }
        .tint(Theme.textPrimary)
        .onAppear {
            cacheSize = env.cache.approximateSizeBytes
            aiActive = KeychainStore.hasUsableKey
        }
        .task {
            guard env.catalog.isAvailable else { return }
            let meta = await env.catalog.meta()
            if let shows = meta["show_count"], let generated = meta["generated_at"] {
                catalogStamp = "Show catalog: \(shows) shows · data as of \(String(generated.prefix(10)))"
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your device's light and dark setting.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Account

    private var signedInWithApple: Bool {
        env.authProvider.currentAccount?.appleUserID != nil
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: signedInWithApple
                      ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(signedInWithApple ? Theme.sage : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(env.authProvider.currentAccount?.displayName ?? "Not signed in")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                    Text(signedInWithApple ? "Signed in with Apple" : "Local, this device only")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if signedInWithApple {
                Button("Sign Out", role: .destructive) {
                    confirmingSignOut = true
                }
            } else {
                signInWithAppleRow
            }
        } header: {
            Text("Account")
        } footer: {
            Text(signedInWithApple
                 ? "Your shelves and journal sync to iCloud."
                 : "Sign in with Apple to keep your shelves and journal in iCloud.")
        }
        .listRowBackground(Theme.surface)
    }

    private var signInWithAppleRow: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName]
        } onCompletion: { result in
            if case .success(let auth) = result,
               let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                signInWithApple(credential: credential)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 44)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: aiActive ? "brain.filled.head.profile" : "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(aiActive ? Theme.sage : Theme.textSecondary)
                Text(aiStatusTitle)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
        } header: {
            Text("Intelligence")
        } footer: {
            Text(aiStatusDetail)
        }
        .listRowBackground(Theme.surface)
    }

    private var aiStatusTitle: String {
        aiActive ? "Nethead AI connected" : "Offline brain active"
    }

    private var aiStatusDetail: String {
        if aiActive {
            return "AI is on the house. Recommendations and chat are grounded in real archive data, with the offline brain as backup."
        }
        return "Everything works offline from the curated knowledge base. This build shipped without an AI key, so free-form chat runs locally."
    }

    private func signInWithApple(credential: ASAuthorizationAppleIDCredential) {
        let fallbackName = displayName.isEmpty ? "Nethead" : displayName
        Task {
            _ = try? await env.authProvider.signInWithApple(
                userID: credential.user,
                displayName: credential.fullName?.givenName ?? fallbackName)
            // Rebuild the environment so the cloud store reopens with sync on.
            NotificationCenter.default.post(name: .shakedownAuthChanged, object: nil)
        }
    }

    // MARK: - Providers

    private var providerSection: some View {
        Section {
            providerRow(name: "Recordings", value: "Internet Archive", icon: "building.columns")
            providerRow(name: "Streaming", value: "Direct from archive.org", icon: "dot.radiowaves.left.and.right")
            providerRow(name: "AI", value: env.aiProvider.name, icon: "sparkles")
        } header: {
            Text("Providers")
        } footer: {
            Text("Provider-based architecture: future versions can plug in official releases, Apple Music, or Relisten-compatible APIs.")
        }
        .listRowBackground(Theme.surface)
    }

    private func providerRow(name: String, value: String, icon: String) -> some View {
        LabeledContent {
            Text(value)
                .font(Theme.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        } label: {
            Label {
                Text(name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { env.downloads.wifiOnly },
                                 set: { env.downloads.wifiOnly = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wi-Fi only")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Shows run hundreds of megabytes — keep them off cellular.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            downloadsSizeRow
            Button("Delete All Downloads", role: .destructive) {
                confirmingDeleteDownloads = true
            }
        } header: {
            Text("Downloads")
        } footer: {
            Text("Downloaded shows are stored on this device for offline listening. The audio still comes straight from the archive — nothing is re-hosted.")
        }
        .listRowBackground(Theme.surface)
    }

    private var downloadsSizeRow: some View {
        // Reading the change token re-renders the row as downloads land.
        let _ = env.downloads.store.changeToken
        return LabeledContent("On this device",
                              value: ByteCountFormatter.string(fromByteCount: env.downloads.store.totalBytes,
                                                               countStyle: .file))
            .font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
    }

    // MARK: - Cache

    private var cacheSection: some View {
        Section {
            LabeledContent("Cache size",
                           value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Button("Clear Cache", role: .destructive) {
                confirmingClearCache = true
            }
        } header: {
            Text("Metadata cache")
        } footer: {
            Text("Setlists, reviews, and search results are cached so the app works offline and stays polite to the archive.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack(spacing: 10) {
                AppMark(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nethead")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("The music never stopped. Neither should discovering it.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recordings come directly from the Internet Archive's Grateful Dead collection, preserved by tapers and archivists over six decades. This app re-hosts no music — it streams (and saves for offline) straight from the archive, adding the intelligence layer.")
                if let stamp = catalogStamp {
                    Text(stamp)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }
}
