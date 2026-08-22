import SwiftUI

/// "Add to playlist" picker for one or many tracks from a show page.
struct PlaylistPickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let show: Show
    let tracks: [Track]
    @State private var savedTo: String?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tracks.count == 1
                             ? (tracks.first?.title ?? "1 track")
                             : "\(tracks.count) tracks")
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(show.shortName)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(env.library.playlists, id: \.persistentModelID) { playlist in
                            let existing = Set((playlist.items ?? []).map(\.trackKey))
                            let alreadyIn = tracks.allSatisfy { existing.contains(show.identifier + "|" + $0.fileName) }
                            let saved = alreadyIn || savedTo == playlist.name
                            Button {
                                env.library.add(tracks: tracks, from: show, to: playlist)
                                withAnimation(.snappy) { savedTo = playlist.name }
                            } label: {
                                HStack {
                                    Image(systemName: playlist.iconName)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(playlist.name)
                                            .font(Theme.body)
                                            .foregroundStyle(Theme.textPrimary)
                                        Text("\(playlist.items?.count ?? 0) tracks")
                                            .font(Theme.mono(11))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(saved ? Theme.sage : Theme.textTertiary)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .padding(13)
                                .cardStyle()
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyIn)
                        }

                        HStack(spacing: 10) {
                            TextField("New playlist…", text: $newName)
                                .font(Theme.body)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                            Button {
                                let playlist = env.library.createPlaylist(name: newName)
                                env.library.add(tracks: tracks, from: show, to: playlist)
                                withAnimation(.snappy) { savedTo = playlist.name }
                                newName = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.accent)
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("Create playlist and add")
                        }
                        .padding(.top, 6)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: savedTo)
    }
}
