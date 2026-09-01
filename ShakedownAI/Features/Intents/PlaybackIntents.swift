import AppIntents
import Foundation

// Siri / Shortcuts entry points. AudioPlaybackIntent launches the app in
// the background and starts audio without foregrounding — "Hey Siri, play
// tonight's show in TapeTree" works from the road.

struct PlayTonightsShowIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Tonight's Show"
    static let description = IntentDescription("Plays TapeTree's featured Grateful Dead show of the day.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let env = AppEnvironment.current else {
            return .result(dialog: "TapeTree isn't ready yet — open the app once and try again.")
        }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        guard let hero = env.knowledgeBase.heroShow(dayOfYear: dayOfYear,
                                                   taste: env.history.tasteSnapshot),
              let recording = try await env.recordingProvider.recordings(forDate: hero.date).first else {
            return .result(dialog: "Couldn't pick tonight's show. Open TapeTree and try from Home.")
        }
        let detail = try await env.metadataProvider.detail(for: recording.identifier)
        guard !detail.tracks.isEmpty else {
            return .result(dialog: "That tape wouldn't stream. Open TapeTree to pick another.")
        }
        env.playerEngine.play(show: recording, tracks: detail.tracks)
        return .result(dialog: "Playing \(hero.venue), \(recording.displayDate).")
    }
}

struct PlayShowOnDateIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Show by Date"
    static let description = IntentDescription("Plays the best tape of the Grateful Dead show from a given date.")

    @Parameter(title: "Date")
    var date: Date

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let env = AppEnvironment.current else {
            return .result(dialog: "TapeTree isn't ready yet — open the app once and try again.")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let day = formatter.string(from: date)
        guard let best = try await env.recordingProvider.recordings(forDate: day).first else {
            return .result(dialog: "No tape of a Grateful Dead show on \(day) — try another date.")
        }
        let detail = try await env.metadataProvider.detail(for: best.identifier)
        guard !detail.tracks.isEmpty else {
            return .result(dialog: "The tape from \(day) wouldn't stream. Open TapeTree to pick another source.")
        }
        env.playerEngine.play(show: best, tracks: detail.tracks)
        return .result(dialog: "Playing \(best.displayDate) at \(best.venue ?? "an unknown venue").")
    }
}

struct TapeTreeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayTonightsShowIntent(),
            phrases: [
                "Play tonight's show in \(.applicationName)",
                "Play the \(.applicationName) show of the day",
            ],
            shortTitle: "Tonight's Show",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PlayShowOnDateIntent(),
            phrases: [
                "Play a show in \(.applicationName)",
                "Play a Grateful Dead show in \(.applicationName)",
            ],
            shortTitle: "Play a Date",
            systemImageName: "calendar"
        )
    }
}
