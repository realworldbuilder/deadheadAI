import SwiftUI

// MARK: - Mini player bar

struct MiniPlayerBar: View {
    @Environment(PlayerEngine.self) private var engine

    var body: some View {
        if engine.hasContent {
            Button {
                engine.isPresentingFullPlayer = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "recordingtape")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.currentTrack?.title ?? "")
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(engine.currentShow?.shortName ?? "")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    if engine.state == .loading {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Button {
                            engine.togglePlayPause()
                        } label: {
                            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.surfaceRaised)
                        .overlay(
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Theme.accent.opacity(0.18))
                                    .frame(width: geo.size.width * engine.progress)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Adds the mini player above the tab bar on every tab root.
struct MiniPlayerInset: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar()
                .padding(.bottom, 4)
        }
    }
}

extension View {
    func withMiniPlayer() -> some View { modifier(MiniPlayerInset()) }
}

// MARK: - Full player

struct PlayerScreen: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var skipCount = 0

    var body: some View {
        ZStack {
            SpaceBackground()

            VStack(spacing: 24) {
                if let show = engine.currentShow {
                    VStack(spacing: 4) {
                        Text(show.displayDate)
                            .font(Theme.mono(14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(show.displayVenue)
                            .font(Theme.title)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, Theme.screenPadding)
                }

                CassetteView(
                    isPlaying: engine.isPlaying,
                    labelTop: engine.currentTrack?.title ?? "—",
                    labelBottom: engine.currentShow?.displayDate ?? ""
                )
                .padding(.horizontal, 34)

                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { scrubbing ? scrubValue : engine.elapsed },
                            set: { scrubValue = $0 }
                        ),
                        in: 0...max(engine.duration, 1),
                        onEditingChanged: { editing in
                            if editing {
                                scrubValue = engine.elapsed
                                scrubbing = true
                            } else {
                                engine.seek(to: scrubValue)
                                scrubbing = false
                            }
                        }
                    )
                    .tint(Theme.accent)

                    HStack {
                        Text(timeString(scrubbing ? scrubValue : engine.elapsed))
                        Spacer()
                        Text(timeString(engine.duration))
                    }
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Theme.screenPadding)

                HStack(spacing: 44) {
                    Button {
                        engine.previous()
                        skipCount += 1
                    } label: {
                        Image(systemName: "backward.fill").font(.title)
                    }
                    .accessibilityLabel("Previous track")
                    Button { engine.togglePlayPause() } label: {
                        ZStack {
                            Circle()
                                .fill(Theme.accentGradient)
                                .frame(width: 74, height: 74)
                            if engine.state == .loading {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.black.opacity(0.8))
                            }
                        }
                    }
                    .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
                    Button {
                        engine.next()
                        skipCount += 1
                    } label: {
                        Image(systemName: "forward.fill").font(.title)
                    }
                    .accessibilityLabel("Next track")
                }
                .foregroundStyle(Theme.textPrimary)

                if case .failed(let message) = engine.state {
                    Text(message)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.rose)
                        .padding(.horizontal)
                }

                // Up next
                if !engine.queue.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, track in
                                    Button { engine.jump(to: index) } label: {
                                        HStack {
                                            Text("\(index + 1)")
                                                .font(Theme.mono(11))
                                                .foregroundStyle(Theme.textTertiary)
                                                .frame(width: 24)
                                            Text(track.title)
                                                .font(index == engine.currentIndex ? Theme.mono(13, weight: .bold) : Theme.mono(13))
                                                .foregroundStyle(index == engine.currentIndex ? Theme.accent : Theme.textSecondary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(track.displayDuration)
                                                .font(Theme.mono(11))
                                                .foregroundStyle(Theme.textTertiary)
                                        }
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(index == engine.currentIndex ? Theme.surfaceRaised : .clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Play \(track.title)")
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, Theme.screenPadding)
                        }
                        .onAppear { proxy.scrollTo(engine.currentIndex, anchor: .center) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 26)
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close player")
            .padding(.leading, 8)
        }
        .sensoryFeedback(.selection, trigger: skipCount)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
