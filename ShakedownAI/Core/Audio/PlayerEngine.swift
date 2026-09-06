import AVFoundation
import Foundation
import Observation

/// One element of the playback queue: a track together with the show it
/// belongs to, so queues can mix recordings (playlists, runs, single shows).
nonisolated struct PlayerQueueEntry: Hashable, Identifiable, Sendable {
    var show: Show
    var track: Track

    /// Stable across shows even when two tapes share a file name.
    var id: String { show.identifier + "|" + track.fileName }
}

/// Central playback engine: one AVPlayer, an explicit track queue, and
/// observable state the whole UI hangs off.
@Observable
final class PlayerEngine {

    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        /// The last track of the queue played to its end; play restarts the show.
        case finished
        case failed(String)
    }

    // MARK: - Observable state

    private(set) var state: PlaybackState = .idle
    private(set) var queue: [PlayerQueueEntry] = []
    private(set) var currentIndex: Int = 0
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    var isPresentingFullPlayer = false

    var currentEntry: PlayerQueueEntry? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    /// The show the *current* entry belongs to — a queue may span many shows.
    var currentShow: Show? { currentEntry?.show }

    var currentTrack: Track? { currentEntry?.track }

    var isPlaying: Bool { state == .playing }
    var hasContent: Bool { !queue.isEmpty }

    /// True when the queue mixes tracks from more than one recording.
    var queueSpansMultipleShows: Bool {
        Set(queue.map(\.show.identifier)).count > 1
    }

    var progress: Double {
        duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
    }

    // MARK: - Sleep timer

    enum SleepTimer: Hashable {
        case off
        case minutes(Int)
        case endOfTrack
    }

    private(set) var sleepTimer: SleepTimer = .off
    /// When a minutes timer is armed, the wall-clock moment it fires.
    private(set) var sleepDeadline: Date?
    private var sleepTask: Task<Void, Never>?

    func setSleepTimer(_ timer: SleepTimer) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepDeadline = nil
        sleepTimer = timer
        if case .minutes(let minutes) = timer {
            let deadline = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
            sleepDeadline = deadline
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                await self?.fadeOutAndPause()
            }
        }
    }

    /// Gentle fade instead of a hard stop — it's a sleep timer.
    private func fadeOutAndPause() async {
        for step in stride(from: 0.8, through: 0.0, by: -0.2) {
            player.volume = Float(step)
            try? await Task.sleep(for: .milliseconds(600))
        }
        pause()
        player.volume = 1
        sleepTimer = .off
        sleepDeadline = nil
    }

    // MARK: - Listening callbacks

    /// Fired when a track finishes or is abandoned: (show, track, secondsListened, completed).
    var onListeningEvent: ((Show, Track, Double, Bool) -> Void)?
    /// Fired when a track starts playing (a fresh load or a gapless roll-over).
    var onTrackStarted: ((Show, Track) -> Void)?

    // MARK: - Internals

    // AVQueuePlayer with the next track preloaded is what makes segues
    // gapless: at a natural track boundary it rolls into the buffered next
    // item itself, and we just catch up our own state.
    private let player = AVQueuePlayer()
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
        session.onRouteDisconnected = { [weak self] in self?.pause() }
        addPeriodicTimeObserver()
    }

    // MARK: - Public controls

    /// Loads a show's queue and starts playback at the given track index.
    func play(show: Show, tracks: [Track], startAt index: Int = 0) {
        play(entries: tracks.map { PlayerQueueEntry(show: show, track: $0) }, startAt: index)
    }

    /// Loads an arbitrary queue — entries may come from different shows
    /// (playlists) — and starts playback at the given index.
    func play(entries: [PlayerQueueEntry], startAt index: Int = 0) {
        guard !entries.isEmpty else {
            state = .failed("No streamable tracks on this recording.")
            return
        }
        session.activate()
        flushListeningEvent(completed: false)
        queue = entries
        currentIndex = min(max(index, 0), entries.count - 1)
        loadCurrentTrack(autoplay: true)
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused, .finished: resume()
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
        if state == .finished {
            // Show's over — spin the tape back to the top and play it again.
            session.activate()
            currentIndex = 0
            loadCurrentTrack(autoplay: true)
            return
        }
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
        player.removeAllItems()
        removeItemObservers()
        queue = []
        currentIndex = 0
        elapsed = 0
        duration = 0
        state = .idle
        nowPlaying?.clear()
    }

    // MARK: - Track loading

    private func loadCurrentTrack(autoplay: Bool) {
        guard let entry = currentEntry,
              let url = streaming.streamURL(identifier: entry.show.identifier, track: entry.track) else {
            state = .failed("Couldn't build a stream URL for this track.")
            return
        }
        state = .loading
        elapsed = 0
        duration = entry.track.durationSeconds ?? 0
        trackStartedAt = .now
        accumulatedSeconds = 0

        removeItemObservers()
        player.removeAllItems()
        let item = AVPlayerItem(url: url)
        player.insert(item, after: nil)
        preloadNextItem()
        observeEnd(of: item)
        observeFailure(of: item)
        observeStatus(of: item)

        if autoplay {
            player.play()
            state = .playing
            onTrackStarted?(entry.show, entry.track)
        }
        nowPlaying?.refresh()
    }

    /// Buffers the following track behind the current one so the queue
    /// player can roll straight into it at the boundary — no segue gap.
    private func preloadNextItem() {
        guard player.items().count < 2,
              queue.indices.contains(currentIndex + 1) else { return }
        let entry = queue[currentIndex + 1]
        guard let url = streaming.streamURL(identifier: entry.show.identifier, track: entry.track) else { return }
        player.insert(AVPlayerItem(url: url), after: player.items().last)
    }

    /// After the queue player advanced on its own, catch our state up to
    /// the already-playing preloaded item.
    private func adoptAdvancedItem() {
        guard let item = player.currentItem, let entry = currentEntry else {
            // The preload was missing (URL failure) — rebuild explicitly.
            loadCurrentTrack(autoplay: true)
            return
        }
        elapsed = 0
        duration = entry.track.durationSeconds ?? 0
        trackStartedAt = .now
        accumulatedSeconds = 0
        removeItemObservers()
        observeEnd(of: item)
        observeFailure(of: item)
        observeStatus(of: item)
        preloadNextItem()
        state = .playing
        onTrackStarted?(entry.show, entry.track)
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

    // Internal (not private) so tests can drive end-of-track transitions
    // without a real stream playing to its end.
    func trackDidFinish() {
        flushListeningEvent(completed: true)
        guard currentIndex + 1 < queue.count else {
            state = .finished
            nowPlaying?.refresh()
            return
        }
        currentIndex += 1
        if sleepTimer == .endOfTrack {
            // Boundary reached: park at the top of the next track.
            sleepTimer = .off
            player.pause()
            adoptAdvancedItem()
            seek(to: 0)
            state = .paused
            nowPlaying?.refresh()
            return
        }
        adoptAdvancedItem()
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
        guard let entry = currentEntry, trackStartedAt != nil else { return }
        let seconds = completed ? (duration > 0 ? duration : accumulatedSeconds) : accumulatedSeconds
        if seconds > 15 {   // ignore instant skips
            onListeningEvent?(entry.show, entry.track, seconds, completed)
        }
        trackStartedAt = nil
        accumulatedSeconds = 0
    }
}
