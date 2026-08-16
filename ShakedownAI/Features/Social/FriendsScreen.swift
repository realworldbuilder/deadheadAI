import SwiftUI

struct FriendsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var friends: [FriendProfile] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Demo circle — a real backend plugs into the same provider seam.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)

                    if isLoading {
                        LoadingLampView(text: "Finding your people…")
                    }
                    ForEach(friends) { friend in
                        FriendCard(friend: friend)
                    }

                    if env.playerEngine.hasContent {
                        NavigationLink(value: "session") {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Start a Listening Session")
                                        .font(Theme.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Spin what's playing now with friends, live chat included.")
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(14)
                            .cardStyle(raised: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Play a show to start a listening session with friends.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 8)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
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

private struct FriendCard: View {
    let friend: FriendProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: friend.avatarSystemImage)
                .font(.title)
                .foregroundStyle(Theme.accent)
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
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(compatibilityColor)
                Text("MATCH")
                    .font(Theme.mono(8, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(13)
        .cardStyle()
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
        ZStack {
            SpaceBackground()
            VStack(spacing: 0) {
                if let show = env.playerEngine.currentShow {
                    VStack(spacing: 4) {
                        Text("NOW SPINNING TOGETHER")
                            .font(Theme.mono(9, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .tracking(1.5)
                        Text(show.shortName)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(env.playerEngine.currentTrack?.title ?? "")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface)
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
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 10)
                .background(Theme.background)
            }
        }
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
        HStack(alignment: .top, spacing: 8) {
            if message.sender == "You" { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 2) {
                if message.sender != "You" {
                    Text(message.sender)
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                Text(message.text)
                    .font(message.isReaction ? .title2 : Theme.body)
                    .foregroundStyle(message.sender == "You" ? Color.black.opacity(0.85) : Theme.textPrimary)
            }
            .padding(.horizontal, message.isReaction ? 4 : 12)
            .padding(.vertical, message.isReaction ? 0 : 8)
            .background(
                message.isReaction
                ? AnyView(EmptyView())
                : AnyView(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(message.sender == "You"
                          ? AnyShapeStyle(Theme.accentGradient)
                          : AnyShapeStyle(Theme.surface)))
            )
            if message.sender != "You" { Spacer(minLength: 30) }
        }
    }
}
