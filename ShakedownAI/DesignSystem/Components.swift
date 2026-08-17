import SwiftUI

// MARK: - Cassette

/// Vintage cassette with reels that spin while playing.
struct CassetteView: View {
    var isPlaying: Bool
    var labelTop: String
    var labelBottom: String

    @State private var spin = false

    var body: some View {
        ZStack {
            // Shell
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(red: 0.20, green: 0.18, blue: 0.15),
                                            Color(red: 0.12, green: 0.11, blue: 0.09)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1.5)
                )

            VStack(spacing: 10) {
                // Label
                VStack(spacing: 3) {
                    Text(labelTop)
                        .font(Theme.mono(13, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(Color(red: 0.2, green: 0.17, blue: 0.13))
                    Text(labelBottom)
                        .font(Theme.mono(10))
                        .lineLimit(1)
                        .foregroundStyle(Color(red: 0.35, green: 0.3, blue: 0.24))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.92, green: 0.88, blue: 0.80))
                )
                .padding(.horizontal, 22)

                // Window with reels
                HStack(spacing: 26) {
                    reel
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.32, green: 0.2, blue: 0.1))
                        .frame(height: 8)
                        .frame(maxWidth: 60)
                    reel
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
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
            Circle().fill(Color(red: 0.85, green: 0.82, blue: 0.75))
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(Color(red: 0.25, green: 0.22, blue: 0.18))
                    .frame(width: 3.5, height: 9)
                    .offset(y: -11)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle()
                .strokeBorder(Color(red: 0.3, green: 0.26, blue: 0.2), lineWidth: 3)
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(spin ? 360 : 0))
        .animation(spin ? .linear(duration: 2.4).repeatForever(autoreverses: false) : .default,
                   value: spin)
    }

    private var screw: some View {
        Circle()
            .fill(Color(red: 0.4, green: 0.36, blue: 0.3))
            .frame(width: 7, height: 7)
            .overlay(Rectangle().fill(Color.black.opacity(0.5)).frame(width: 6, height: 1))
    }
}

// MARK: - Rating dots

/// Five amber dots, like backlit meter lamps.
struct RatingDots: View {
    var rating: Double   // 0...5
    var showValue = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Double(i) < rating.rounded() ? Theme.accent : Theme.surfaceRaised)
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.5))
                    .frame(width: 7, height: 7)
            }
            if showValue {
                Text(String(format: "%.1f", rating))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", rating)) out of 5")
    }
}

// MARK: - Tags

struct TagPill: View {
    var text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(Theme.mono(11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Show row (reused by lists everywhere)

struct ShowRow: View {
    var show: Show

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(monthDay)
                    .font(Theme.mono(15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(yearText)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 56)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceRaised))

            VStack(alignment: .leading, spacing: 3) {
                Text(show.venue ?? show.title)
                    .font(Theme.headline)
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
        .padding(10)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var monthDay: String {
        guard let ds = show.dateString, ds.count == 10 else { return "—" }
        return String(ds.dropFirst(5)).replacingOccurrences(of: "-", with: "/")
    }

    private var yearText: String {
        show.year.map(String.init) ?? String(show.dateString?.prefix(4) ?? "")
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
                .font(Theme.mono(12))
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
                    Text("The Internet Archive is temporarily offline — the tapes will be back.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.rose.opacity(0.5)))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
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
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardStyle()
    }
}
