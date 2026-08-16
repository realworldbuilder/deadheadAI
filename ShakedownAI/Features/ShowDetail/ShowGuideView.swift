import SwiftUI

/// Renders an AI-generated listening guide.
struct ShowGuideView: View {
    let guide: ShowGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                Text("Listening Guide")
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                improvMeter
            }

            row(label: "Mood", text: guide.overallMood)
            row(label: "Context", text: guide.historicalContext)
            row(label: "Recording", text: guide.recordingNotes)
            row(label: "Accessibility", text: guide.accessibility)

            if !guide.musicalHighlights.isEmpty {
                bulletList(title: "Highlights", items: guide.musicalHighlights, icon: "star.fill")
            }
            if !guide.bestTransitions.isEmpty {
                bulletList(title: "Transitions", items: guide.bestTransitions, icon: "arrow.right.arrow.left")
            }
            if !guide.listenFor.isEmpty {
                bulletList(title: "Listen for", items: guide.listenFor, icon: "waveform")
            }
            row(label: "Fan consensus", text: guide.fanConsensus)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var improvMeter: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < guide.improvisationRating ? Theme.accent : Theme.surfaceRaised)
                    .frame(width: 5, height: 8 + CGFloat(i) * 3)
            }
        }
        .accessibilityLabel("Improvisation \(guide.improvisationRating) of 5")
    }

    private func row(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1.2)
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func bulletList(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1.2)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                    Text(item)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
