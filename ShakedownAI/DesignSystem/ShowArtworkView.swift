import SwiftUI

/// Cover art for a show: the archive's real photo or ticket-stub scan when
/// one exists (waveform junk filtered out), the generated stub otherwise.
struct ShowArtworkView: View {
    let show: Show
    var size: CGFloat = 96
    var cornerRadius: CGFloat = 12

    @State private var archiveImage: UIImage?

    var body: some View {
        Image(uiImage: archiveImage ?? StubArtwork.image(for: show))
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .task(id: show.identifier) {
                archiveImage = await ArchiveArtwork.shared.thumbnail(for: show.identifier)
            }
            .accessibilityHidden(true)
    }
}
