import SwiftUI

/// The best picture we have for a night, sized by whoever places it: the
/// ticket or poster scan when the catalog has one, the archive's photo of
/// the tape, or a scan borrowed from the nearest night — and the flat
/// date tile while that loads or when nothing exists. Layout-neutral: it
/// fills the frame it's given and never inflates its container.
struct DateCover: View {
    @Environment(AppEnvironment.self) private var env
    let date: String
    var identifier: String? = nil
    var venue: String? = nil
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkPlaceholder(date: LocalKnowledgeAI.prettyDate(date),
                                       shortDate: LocalKnowledgeAI.prettyDate(date),
                                       venue: venue)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1))
            .task(id: date + (identifier ?? "")) {
                image = await ArchiveArtwork.shared.cover(date: date, identifier: identifier, catalog: env.catalog)
            }
            .accessibilityHidden(true)
    }
}

/// A row of nights' scans, equal widths, for putting a face on anything
/// that spans several shows: an era, a journey, a tour.
struct CoverStrip: View {
    let dates: [String]
    var height: CGFloat = 92
    var spacing: CGFloat = 6
    var cornerRadius: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(dates, id: \.self) { date in
                DateCover(date: date, cornerRadius: cornerRadius)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        CoverStrip(dates: ["1977-05-08", "1972-08-27", "1970-02-13"])
        DateCover(date: "1977-05-08", venue: "Barton Hall")
            .frame(width: 56, height: 56)
    }
    .padding()
    .environment(AppEnvironment.mock())
}
