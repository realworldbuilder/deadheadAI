import AVKit
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
                        .foregroundStyle(Theme.textSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.currentTrack?.displayTitle ?? "")
                            .font(Theme.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(engine.currentShow?.shortName ?? "")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    if engine.state == .loading {
                        ProgressView().tint(Theme.textSecondary)
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
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 8)
                .background(Theme.surface)
                .overlay(alignment: .top) { HairlineDivider() }
                .overlay(alignment: .bottomLeading) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * engine.progress, height: 2)
                    }
                    .frame(height: 2)
                }
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
        VStack(spacing: 24) {
                if let show = engine.currentShow {
                    VStack(spacing: 4) {
                        Text(show.displayDate)
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)
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
                    .tint(Theme.textPrimary)

                    HStack {
                        Text(timeString(scrubbing ? scrubValue : engine.elapsed))
                        Spacer()
                        Text(timeString(engine.duration))
                    }
                    .font(Theme.timecode)
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
                                .fill(Theme.textPrimary)
                                .frame(width: 74, height: 74)
                            if engine.state == .loading {
                                ProgressView().tint(Theme.background)
                            } else {
                                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(Theme.background)
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

                // Secondary row: route audio, doze off gracefully.
                HStack(spacing: 40) {
                    AirPlayRoutePicker()
                        .frame(width: 30, height: 30)
                    Menu {
                        Picker("Sleep Timer", selection: Binding(
                            get: { engine.sleepTimer },
                            set: { engine.setSleepTimer($0) }
                        )) {
                            Text("Off").tag(PlayerEngine.SleepTimer.off)
                            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                                Text("\(minutes) minutes").tag(PlayerEngine.SleepTimer.minutes(minutes))
                            }
                            Text("End of track").tag(PlayerEngine.SleepTimer.endOfTrack)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: engine.sleepTimer == .off ? "moon.zzz" : "moon.zzz.fill")
                                .font(.system(size: 17))
                            if let deadline = engine.sleepDeadline {
                                Text(deadline, style: .timer)
                                    .font(Theme.timecode)
                            } else if engine.sleepTimer == .endOfTrack {
                                Text("track end")
                                    .font(Theme.caption)
                            }
                        }
                        .foregroundStyle(engine.sleepTimer == .off ? Theme.textTertiary : Theme.textPrimary)
                        .frame(minWidth: 30, minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Sleep timer")
                }

                if case .failed(let message) = engine.state {
                    Text(message)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.rose)
                        .padding(.horizontal)
                }

                // Up next
                if !engine.queue.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                let spansShows = engine.queueSpansMultipleShows
                                ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, entry in
                                    Button { engine.jump(to: index) } label: {
                                        HStack {
                                            Text("\(index + 1)")
                                                .font(Theme.timecode)
                                                .foregroundStyle(Theme.textTertiary)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(entry.track.displayTitle)
                                                    .font(index == engine.currentIndex ? Theme.subheadline.weight(.semibold) : Theme.subheadline)
                                                    .foregroundStyle(index == engine.currentIndex ? Theme.textPrimary : Theme.textSecondary)
                                                    .lineLimit(1)
                                                if spansShows {
                                                    Text(entry.show.displayDate)
                                                        .font(.caption2)
                                                        .foregroundStyle(Theme.textTertiary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()
                                            Text(entry.track.displayDuration)
                                                .font(Theme.timecode)
                                                .foregroundStyle(Theme.textTertiary)
                                        }
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(index == engine.currentIndex ? Theme.surface : .clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Play \(entry.track.displayTitle)")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .presentationBackground(Theme.background)
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
        .overlay(alignment: .topTrailing) {
            if let show = engine.currentShow {
                let track = engine.currentTrack
                ShareLink(
                    item: track.map { show.shareURL(for: $0) } ?? show.shareURL,
                    subject: Text(show.shortName),
                    message: Text(show.shareText(track: track))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share")
                .padding(.trailing, 8)
            }
        }
        .sensoryFeedback(.selection, trigger: skipCount)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// System AirPlay route picker, themed to sit with the transport icons.
struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = Theme.accentUIColor
        view.tintColor = .secondaryLabel
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
