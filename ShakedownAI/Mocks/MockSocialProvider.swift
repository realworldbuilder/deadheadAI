import Foundation

/// Simulated social layer. The protocol seam means a real backend can swap in
/// without touching any UI.
final class MockSocialProvider: SocialProvider {

    private let mockFriends: [FriendProfile] = [
        FriendProfile(id: "f1", name: "Cassidy R.", avatarSystemImage: "person.crop.circle.badge.moon",
                      nowListeningTo: "5/8/77 — Barton Hall", favoriteEra: "Hiatus & the Return", compatibility: 0.91),
        FriendProfile(id: "f2", name: "August W.", avatarSystemImage: "person.crop.circle.badge.clock",
                      nowListeningTo: nil, favoriteEra: "Europe '72 & the Wall", compatibility: 0.78),
        FriendProfile(id: "f3", name: "Stella B.", avatarSystemImage: "person.crop.circle.badge.checkmark",
                      nowListeningTo: "8/27/72 — Veneta", favoriteEra: "The Brent Years", compatibility: 0.66),
        FriendProfile(id: "f4", name: "Cody M.", avatarSystemImage: "person.crop.circle.badge.questionmark",
                      nowListeningTo: nil, favoriteEra: "Primal Dead", compatibility: 0.54),
    ]

    private var sessionShowName: String?
    private var messageContinuation: AsyncStream<SessionChatMessage>.Continuation?
    private var chatterTask: Task<Void, Never>?

    func friends() async throws -> [FriendProfile] {
        try? await Task.sleep(for: .milliseconds(350))
        return mockFriends
    }

    func startListeningSession(showIdentifier: String, showName: String) async throws {
        sessionShowName = showName
    }

    func sessionMessages() -> AsyncStream<SessionChatMessage> {
        let showName = sessionShowName ?? "the show"
        let script: [(String, String, Bool)] = [
            ("Cassidy R.", "ohh good pick", false),
            ("Cassidy R.", "🔥", true),
            ("August W.", "wait for this Loser, Jerry takes his time with it", false),
            ("Stella B.", "the tape hiss on this transfer is part of the charm honestly", false),
            ("August W.", "🐢⚡", true),
            ("Cassidy R.", "every time I hear \(showName) I find something new", false),
            ("Stella B.", "Phil is SO loud in this mix and I'm not complaining", false),
            ("August W.", "this is why we tape", false),
        ]
        return AsyncStream { continuation in
            self.messageContinuation = continuation
            self.chatterTask = Task {
                for (sender, text, isReaction) in script {
                    let delay = Double.random(in: 4...9)
                    try? await Task.sleep(for: .seconds(delay))
                    if Task.isCancelled { break }
                    continuation.yield(SessionChatMessage(id: UUID(), sender: sender, text: text, isReaction: isReaction))
                }
            }
            continuation.onTermination = { [chatterTask] _ in
                chatterTask?.cancel()
            }
        }
    }

    func send(message: String) async {
        messageContinuation?.yield(SessionChatMessage(id: UUID(), sender: "You", text: message, isReaction: false))
    }

    func endSession() async {
        chatterTask?.cancel()
        messageContinuation?.finish()
        messageContinuation = nil
        sessionShowName = nil
    }
}
