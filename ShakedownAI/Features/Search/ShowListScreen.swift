import SwiftUI

/// Reusable list of shows with a loader. Used by browse, search results,
/// era pages, and On This Day.
struct ShowListScreen: View {
    let title: String
    let subtitle: String?
    let loader: () async throws -> [Show]

    @State private var shows: [Show] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.bottom, 4)
                    }
                    if isLoading && shows.isEmpty {
                        LoadingLampView(text: "Searching the vault…")
                    } else if let errorMessage, shows.isEmpty {
                        ErrorCard(message: errorMessage) { Task { await load() } }
                    } else {
                        ForEach(shows) { show in
                            NavigationLink(value: show) {
                                ShowRow(show: show)
                            }
                            .buttonStyle(.plain)
                        }
                        if shows.isEmpty && !isLoading {
                            Text("Nothing surfaced. The vault is deep — try another angle.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 30)
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        guard shows.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            shows = try await loader()
        } catch HTTPError.serviceUnavailable {
            errorMessage = ArchiveHealth.outageMessage
        } catch {
            errorMessage = "The archive didn't answer. It happens — give it another try."
        }
        isLoading = false
    }
}
