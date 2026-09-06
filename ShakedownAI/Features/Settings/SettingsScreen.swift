import SwiftUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme
    @State private var aiActive = KeychainStore.hasUsableKey
    @State private var cacheSize = 0
    @State private var confirmingClearCache = false
    @State private var confirmingSignOut = false
    @State private var showingPair = false
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
                notesfileSection
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
                    Task { await env.authProvider.signOut() }
                }
            } message: {
                Text("Your shelves, mix tapes and journal stay on this phone. The notesfile keeps its copy; get back on any time with a new code.")
            }
            .sheet(isPresented: $showingPair) {
                PairSheet()
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

    private var accountSection: some View {
        Section {
            if let account = env.authProvider.currentAccount {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title3)
                        .foregroundStyle(Theme.sage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.handle)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                        Text(syncLine)
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Button("Sync now") {
                    Task { await env.sync.syncNow() }
                }
                .disabled(env.sync.status == .syncing)
                if let page = env.api?.url(path: "/heads/\(account.handle)") {
                    Link("Your page on the notesfile", destination: page)
                }
                Button("Sign Out", role: .destructive) {
                    confirmingSignOut = true
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Riding along")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Shelves and journal live on this phone only")
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if env.api != nil {
                    Button("Get on the Bus") {
                        showingPair = true
                    }
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(env.authProvider.currentAccount != nil
                 ? "Shelves, mix tapes and the journal are the same here and on the notesfile. The phone shows up in the lot while it's spinning."
                 : "A handle from the notesfile keeps your shelves, mix tapes and journal the same here and on the web.")
        }
        .listRowBackground(Theme.surface)
    }

    private var syncLine: String {
        switch env.sync.status {
        case .syncing: return "Syncing with the notesfile…"
        case .offline: return "Offline — changes go up when you're back"
        case .failed(let text): return text
        case .idle:
            if let at = env.sync.lastSyncedAt {
                return "In step with the notesfile · \(at.formatted(.relative(presentation: .named)))"
            }
            return "On the bus"
        }
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
            Text("The Brain")
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
            return "AI's on the house. Every pick is grounded in real tapes and real setlists, with the offline brain as backup."
        }
        return "This build shipped without an AI key, so chat runs off the built-in knowledge base. Everything still works, all of it offline."
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

    // MARK: - The Notesfile

    /// The Dead conference, back up on the web: RDVAX::GRATEFUL. Every show
    /// is a topic, heads write notes, tape lists get passed around as trees.
    private var notesfileSection: some View {
        Section {
            Link(destination: URL(string: "https://nethead.nethead-web.workers.dev")!) {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Notesfile")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        Text("RDVAX::GRATEFUL on the web. Notes on every show, tape lists, the lot.")
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        } header: {
            Text("The Notesfile")
        } footer: {
            Text("Get on the bus there with a handle like PHISH::HUSSEY and a passkey. No email, no password.")
        }
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
                    Text("Every tape on the archive, and a head who's spun them all.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Every tape comes straight from the Internet Archive's Grateful Dead collection — pulled by tapers, traded for decades, kept by the archive. Nethead re-hosts nothing and sells nothing. It streams from archive.org (and saves tapes for offline) and adds a head who knows the collection.")
                if let stamp = catalogStamp {
                    Text(stamp)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }
}
