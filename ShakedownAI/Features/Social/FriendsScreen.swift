import SwiftUI

struct FriendsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var friends: [FriendProfile] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Demo circle — a real backend plugs into the same provider seam.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)

                if isLoading {
                    LoadingLampView(text: "Finding your people…")
                }
                VStack(spacing: 0) {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                        FriendRow(friend: friend, divider: index < friends.count - 1)
                    }
                }

                if env.playerEngine.hasContent {
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink(value: "session") {
                            Label("Start a Listening Session", systemImage: "person.3.fill")
                        }
                        .buttonStyle(.primary(fullWidth: true))
                        Text("Spin what's playing now with friends, live chat included.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 8)
                } else {
                    Text("Play a show to start a listening session with friends.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: String.self) { route in
            if route == "session" {
                ListeningSessionScreen()
            }
        }
        .task {
            friends = (try? await env.socialProvider.friends()) ?? []
            isLoading = false
        }
    }
}

private struct FriendRow: View {
    let friend: FriendProfile
    var divider = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: friend.avatarSystemImage)
                .font(.title)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let listening = friend.nowListeningTo {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.sage).frame(width: 6, height: 6)
                        Text("Listening to \(listening)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.sage)
                            .lineLimit(1)
                    }
                } else {
                    Text("Favorite era: \(friend.favoriteEra)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(Int(friend.compatibility * 100))%")
                    .font(Theme.subheadline.weight(.semibold))
                    .foregroundStyle(compatibilityColor)
                Text("Match")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .listRowStyle(divider: divider)
    }

    private var compatibilityColor: Color {
        friend.compatibility > 0.8 ? Theme.sage : friend.compatibility > 0.6 ? Theme.accent : Theme.textSecondary
    }
}

// MARK: - Listening session room

struct ListeningSessionScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var messages: [SessionChatMessage] = []
    @State private var draft = ""
    @State private var started = false

    var body: some View {
        VStack(spacing: 0) {
            if let show = env.playerEngine.currentShow {
                VStack(spacing: 4) {
                    Text("Now spinning together")
                        .eyebrowStyle()
                    Text(show.shortName)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(env.playerEngine.currentTrack?.title ?? "")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) { HairlineDivider() }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            sessionBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(Theme.screenPadding)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            HStack(spacing: 8) {
                ForEach(["🔥", "🌹", "⚡", "🐻", "💀"], id: \.self) { emoji in
                    Button {
                        Task { await env.socialProvider.send(message: emoji) }
                    } label: {
                        Text(emoji).font(.title3)
                    }
                    .accessibilityLabel("React with \(emoji)")
                }
                TextField("Say something…", text: $draft)
                    .font(Theme.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surfaceRaised))
                Button {
                    let text = draft
                    draft = ""
                    Task { await env.socialProvider.send(message: text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(draft.isEmpty ? Theme.textTertiary : Theme.accent)
                }
                .disabled(draft.isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 10)
            .background(Theme.background)
        }
        .background(Theme.background)
        .navigationTitle("Listening Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !started else { return }
            started = true
            if let show = env.playerEngine.currentShow {
                try? await env.socialProvider.startListeningSession(
                    showIdentifier: show.identifier, showName: show.shortName)
            }
            for await message in env.socialProvider.sessionMessages() {
                messages.append(message)
            }
        }
        .onDisappear {
            Task { await env.socialProvider.endSession() }
        }
    }

    private func sessionBubble(_ message: SessionChatMessage) -> some View {
        let isUser = message.sender == "You"
        let bubbled = isUser && !message.isReaction
        return HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 2) {
                if !isUser {
                    Text(message.sender)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(message.text)
                    .font(message.isReaction ? .title2 : Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, bubbled ? 14 : 0)
            .padding(.vertical, bubbled ? 10 : 0)
            .background {
                if bubbled {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.surfaceRaised)
                }
            }
            if !isUser { Spacer(minLength: 30) }
        }
    }
}
