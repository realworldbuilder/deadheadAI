import AVFoundation
import Foundation
import Observation

/// Central playback engine: one AVPlayer, an explicit track queue, and
/// observable state the whole UI hangs off.
@Observable
final class PlayerEngine {

    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    // MARK: - Observable state

    private(set) var state: PlaybackState = .idle
    private(set) var currentShow: Show?
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = 0
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    var isPresentingFullPlayer = false

    var currentTrack: Track? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    var isPlaying: Bool { state == .playing }
    var hasContent: Bool { currentShow != nil && !queue.isEmpty }

    var progress: Double {
        duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
    }

    // MARK: - Listening callbacks

    /// Fired when a track finishes or is abandoned: (show, track, secondsListened, completed).
    var onListeningEvent: ((Show, Track, Double, Bool) -> Void)?

    // MARK: - Internals

    private let player = AVPlayer()
    private let session = AudioSessionManager()
    private let streaming: any StreamingProvider
    private var nowPlaying: NowPlayingCoordinator?
    private var timeObserverToken: Any?
    private var endObserver: (any NSObjectProtocol)?
    private var failObserver: (any NSObjectProtocol)?
    private var statusObservation: NSKeyValueObservation?
    private var trackStartedAt: Date?
    private var accumulatedSeconds: Double = 0

    init(streaming: any StreamingProvider) {
        self.streaming = streaming
        self.nowPlaying = NowPlayingCoordinator(engine: self)
        session.onInterruptionBegan = { [weak self] in self?.pause() }
        session.onInterruptionEndedShouldResume = { [weak self] in self?.resume() }
        addPeriodicTimeObserver()
    }

    // MARK: - Public controls

    /// Loads a show's queue and starts playback at the given track index.
    func play(show: Show, tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty else {
            state = .failed("No streamable tracks on this recording.")
            return
        }
        session.activate()
        flushListeningEvent(completed: false)
        currentShow = show
        queue = tracks
        currentIndex = min(max(index, 0), tracks.count - 1)
        loadCurrentTrack(autoplay: true)
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        case .idle, .loading, .failed: break
        }
    }

    func pause() {
        guard state == .playing else { return }
        player.pause()
        state = .paused
        nowPlaying?.refresh()
    }

    func resume() {
        guard state == .paused else { return }
        session.activate()
        player.play()
        state = .playing
        nowPlaying?.refresh()
    }

    func next() {
        guard currentIndex + 1 < queue.count else { return }
        flushListeningEvent(completed: false)
        currentIndex += 1
        loadCurrentTrack(autoplay: true)
    }

    func previous() {
        // Standard behavior: restart the track unless we're near its start.
        if elapsed > 4 || currentIndex == 0 {
            seek(to: 0)
            return
        }
        flushListeningEvent(completed: false)
        currentIndex -= 1
        loadCurrentTrack(autoplay: true)
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = seconds
        nowPlaying?.refresh()
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        flushListeningEvent(completed: false)
        currentIndex = index
        loadCurrentTrack(autoplay: true)
    }

    func stop() {
        flushListeningEvent(completed: false)
        player.replaceCurrentItem(with: nil)
        removeItemObservers()
        currentShow = nil
        queue = []
        currentIndex = 0
        elapsed = 0
        duration = 0
        state = .idle
        nowPlaying?.clear()
    }

    // MARK: - Track loading

    private func loadCurrentTrack(autoplay: Bool) {
        guard let show = currentShow, let track = currentTrack,
              let url = streaming.streamURL(identifier: show.identifier, track: track) else {
            state = .failed("Couldn't build a stream URL for this track.")
            return
        }
        state = .loading
        elapsed = 0
        duration = track.durationSeconds ?? 0
        trackStartedAt = .now
        accumulatedSeconds = 0

        removeItemObservers()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        observeEnd(of: item)
        observeFailure(of: item)
        observeStatus(of: item)

        if autoplay {
            player.play()
            state = .playing
        }
        nowPlaying?.refresh()
    }

    private func observeEnd(of item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackDidFinish() }
        }
    }

    private func observeFailure(of item: AVPlayerItem) {
        failObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.state = .failed("Stream dropped. Try another source.") }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let errorText = observedItem.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .failed:
                    self.state = .failed(errorText ?? "This source wouldn't stream.")
                case .readyToPlay:
                    if self.state == .loading { self.state = self.player.rate > 0 ? .playing : .paused }
                    let itemDuration = self.player.currentItem?.duration.seconds ?? 0
                    if itemDuration.isFinite, itemDuration > 0 { self.duration = itemDuration }
                    self.nowPlaying?.refresh()
                default:
                    break
                }
            }
        }
    }

    private func removeItemObservers() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        endObserver = nil
        failObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
    }

    private func trackDidFinish() {
        flushListeningEvent(completed: true)
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            loadCurrentTrack(autoplay: true)
        } else {
            state = .paused
            nowPlaying?.refresh()
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.state == .playing else { return }
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                self.accumulatedSeconds = max(self.accumulatedSeconds, self.elapsed)
            }
        }
    }

    private func flushListeningEvent(completed: Bool) {
        guard let show = currentShow, let track = currentTrack, trackStartedAt != nil else { return }
        let seconds = completed ? (duration > 0 ? duration : accumulatedSeconds) : accumulatedSeconds
        if seconds > 15 {   // ignore instant skips
            onListeningEvent?(show, track, seconds, completed)
        }
        trackStartedAt = nil
        accumulatedSeconds = 0
    }
}
