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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tracks.count == 1
                         ? (tracks.first?.title ?? "1 track")
                         : "\(tracks.count) tracks")
                        .font(Theme.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(show.shortName)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    let playlists = env.library.playlists
                    VStack(spacing: 0) {
                        ForEach(Array(playlists.enumerated()), id: \.element.persistentModelID) { index, playlist in
                            let existing = Set((playlist.items ?? []).map(\.trackKey))
                            let alreadyIn = tracks.allSatisfy { existing.contains(show.identifier + "|" + $0.fileName) }
                            let saved = alreadyIn || savedTo == playlist.name
                            Button {
                                env.library.add(tracks: tracks, from: show, to: playlist)
                                withAnimation(.snappy) { savedTo = playlist.name }
                            } label: {
                                HStack {
                                    Image(systemName: playlist.iconName)
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(playlist.name)
                                            .font(Theme.body)
                                            .foregroundStyle(Theme.textPrimary)
                                        Text("\(playlist.items?.count ?? 0) tracks")
                                            .font(Theme.caption)
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(saved ? Theme.sage : Theme.textTertiary)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .listRowStyle(divider: index < playlists.count - 1)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyIn)
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("New mix tape…", text: $newName)
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
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Create mix tape and add")
                    }
                    .padding(.top, 6)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.background)
            .navigationTitle("Add to Mix Tape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
        .sensoryFeedback(.success, trigger: savedTo)
    }
}
