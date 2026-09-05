import SwiftUI

// MARK: - Cassette

/// The tape in the deck: a black cassette with a cream sticker, the way a
/// home dub wears the label of whoever made it. The sticker carries the
/// Nethead mark, the track, and the night, over a red-and-blue stripe
/// borrowed from the bolt on the icon's screen. Reels turn while it plays.
struct CassetteView: View {
    var isPlaying: Bool
    var labelTop: String
    var labelBottom: String

    @State private var spin = false

    private let shellStroke = Color.white.opacity(0.10)
    private let sticker = Color(red: 0.96, green: 0.94, blue: 0.88)
    private let stickerInk = Color(red: 0.08, green: 0.08, blue: 0.08)
    private let stickerInkSoft = Color(red: 0.38, green: 0.36, blue: 0.33)
    private let boltRed = Color(red: 0.88, green: 0.16, blue: 0.13)
    private let boltBlue = Color(red: 0.12, green: 0.36, blue: 0.84)

    var body: some View {
        ZStack {
            // Shell: black plastic, a touch lighter at the top where the light hits.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(shellStroke, lineWidth: 1.5)
                )

            VStack(spacing: 10) {
                // Sticker
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        AppMark(size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(labelTop)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(stickerInk)
                            Text(labelBottom)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(stickerInkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    HStack(spacing: 0) {
                        boltRed
                        boltBlue
                    }
                    .frame(height: 4)
                }
                .background(sticker)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(stickerInk.opacity(0.85), lineWidth: 1)
                )
                .padding(.horizontal, 22)

                // Window with reels
                HStack(spacing: 26) {
                    reel
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.24))
                        .frame(height: 8)
                        .frame(maxWidth: 60)
                    reel
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(shellStroke))
                )
                .padding(.horizontal, 30)

                // Screws
                HStack {
                    screw; Spacer(); screw
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 14)
        }
        .aspectRatio(1.62, contentMode: .fit)
        .onAppear { spin = isPlaying }
        .onChange(of: isPlaying) { _, playing in spin = playing }
    }

    private var reel: some View {
        ZStack {
            Circle().fill(Color(white: 0.92))
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(Color(white: 0.12))
                    .frame(width: 3.5, height: 9)
                    .offset(y: -11)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle()
                .strokeBorder(Color(white: 0.30), lineWidth: 3)
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(spin ? 360 : 0))
        .animation(spin ? .linear(duration: 2.4).repeatForever(autoreverses: false) : .default,
                   value: spin)
    }

    private var screw: some View {
        Circle()
            .fill(Color(white: 0.34))
            .frame(width: 7, height: 7)
            .overlay(Rectangle().fill(Color.black.opacity(0.6)).frame(width: 6, height: 1))
    }
}

// MARK: - Rating dots

/// Five dots, lit in the accent up to the rating.
struct RatingDots: View {
    var rating: Double   // 0...5
    var showValue = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Double(i) < rating.rounded() ? Theme.accent : Theme.stroke)
                    .frame(width: 7, height: 7)
            }
            if showValue {
                Text(String(format: "%.1f", rating))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", rating)) out of 5")
    }
}

// MARK: - Tags

/// A quiet outlined chip. Neutral by default; pass a tint (sage for a
/// soundboard, denim for an audience tape) when the tag carries meaning.
struct TagPill: View {
    var text: String
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(Theme.caption.weight(.medium))
            .foregroundStyle(tint ?? Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(tint?.opacity(0.5) ?? Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Show row (reused by lists everywhere)

/// A show as a hairline row: its cover on the left, date, venue and
/// location, then a chevron. Stack them in a `VStack(spacing: 0)`; each
/// draws its own rule.
struct ShowRow: View {
    var show: Show
    var divider = true

    var body: some View {
        HStack(spacing: 12) {
            ShowThumbnail(show: show, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(show.displayDate)
                    .font(Theme.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(show.venue ?? show.title)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let location = show.location {
                        Text(location)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    if show.isSoundboard {
                        TagPill(text: "SBD", tint: Theme.sage)
                    }
                }
                if let rating = show.avgRating, rating > 0 {
                    RatingDots(rating: rating)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowStyle(divider: divider)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Loading & error states

struct LoadingLampView: View {
    var text: String
    @State private var glow = false

    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 12, height: 12)
                .shadow(color: Theme.accent.opacity(glow ? 0.9 : 0.2), radius: glow ? 14 : 3)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: glow)
                .onAppear { glow = true }
            Text(text)
                .font(Theme.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// App-wide pill shown while archive.org itself is down. Driven by
/// `ArchiveHealth`; appears over every tab and clears itself when the
/// archive answers again.
struct ArchiveOfflineBanner: View {
    private let health = ArchiveHealth.shared

    var body: some View {
        ZStack(alignment: .top) {
            if health.isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Theme.rose)
                    Text("archive.org is down right now. The tapes will be back.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .padding(.horizontal, Theme.screenPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: health.isOffline)
        .allowsHitTesting(false)
    }
}

struct ErrorCard: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundStyle(Theme.rose)
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry)
                    .font(Theme.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardStyle()
    }
}
