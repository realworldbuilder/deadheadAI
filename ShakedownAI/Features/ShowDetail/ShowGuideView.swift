import SwiftUI

/// Renders an AI-generated listening guide.
struct ShowGuideView: View {
    let guide: ShowGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.textSecondary)
                Text("Listening Notes")
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                improvMeter
            }

            row(label: "Mood", text: guide.overallMood)
            row(label: "Context", text: guide.historicalContext)
            row(label: "Recording", text: guide.recordingNotes)
            row(label: "Good first show?", text: guide.accessibility)

            if !guide.musicalHighlights.isEmpty {
                bulletList(title: "Highlights", items: guide.musicalHighlights, icon: "star.fill")
            }
            if !guide.bestTransitions.isEmpty {
                bulletList(title: "Transitions", items: guide.bestTransitions, icon: "arrow.right.arrow.left")
            }
            if !guide.listenFor.isEmpty {
                bulletList(title: "Listen for", items: guide.listenFor, icon: "waveform")
            }
            row(label: "What the heads say", text: guide.fanConsensus)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var improvMeter: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < guide.improvisationRating ? Theme.textPrimary : Theme.stroke)
                    .frame(width: 5, height: 8 + CGFloat(i) * 3)
            }
        }
        .accessibilityLabel("Improvisation \(guide.improvisationRating) of 5")
    }

    private func row(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).eyebrowStyle()
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func bulletList(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).eyebrowStyle()
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                    Text(item)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// The guide's marks on one track, in the same glyph vocabulary the
/// Listening Guide card uses for its bullets — so a ★ beside a setlist
/// row reads as "this is one of the Highlights" without a legend.
struct GuideMarkGlyphs: View {
    let marks: GuideMarks
    var size: CGFloat = 10

    var body: some View {
        if !marks.isEmpty {
            HStack(spacing: 4) {
                ForEach(Self.legend, id: \.symbol) { entry in
                    if marks.contains(entry.mark) {
                        Image(systemName: entry.symbol)
                            .font(.system(size: size))
                            .foregroundStyle(entry.tint)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.legend.filter { marks.contains($0.mark) }
                .map(\.label).joined(separator: ", "))
        }
    }

    struct LegendEntry {
        var mark: GuideMarks
        var symbol: String
        var label: String
        var tint: Color
    }

    static let legend: [LegendEntry] = [
        LegendEntry(mark: .highlight, symbol: "star.fill", label: "Highlight", tint: Theme.textSecondary),
        LegendEntry(mark: .transition, symbol: "arrow.right.arrow.left", label: "Transition", tint: Theme.denim),
        LegendEntry(mark: .listenFor, symbol: "waveform", label: "Listen for", tint: Theme.textSecondary),
    ]
}

/// One caption line explaining the glyphs, shown under the track list
/// whenever the guide resolved at least one mark.
struct GuideMarkLegend: View {
    let marks: GuideMarks

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GuideMarkGlyphs.legend, id: \.symbol) { entry in
                if marks.contains(entry.mark) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.symbol)
                            .font(.system(size: 9))
                            .foregroundStyle(entry.tint)
                        Text(entry.label)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}
