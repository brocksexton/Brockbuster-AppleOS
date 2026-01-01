import Foundation
import SwiftUI
import AVKit

/// Centralized playback manager that keeps an AVPlayer alive even when the
/// full-screen player UI is dismissed, enabling a "Now Playing" bar.
@MainActor
final class NowPlayingManager: ObservableObject {

    struct NowPlayingItem: Identifiable, Equatable {
        let id: String // Jellyfin itemId
        let title: String
        let subtitle: String?
        let posterURL: URL?
        let playbackContext: SessionStore.PlaybackContext
        let startPositionTicks: Int
    }

    // MARK: - Published state

    /// The currently playing item (if any).
    @Published private(set) var item: NowPlayingItem?

    // MARK: - Compatibility shims

    /// Back-compat for earlier iterations that referenced `currentItem`.
    var currentItem: NowPlayingItem? { item }
    @Published var isPlayerPresented: Bool = false
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var progress: Double = 0 // 0...1
    @Published private(set) var currentPositionTicks: Int = 0

    // MARK: - Private

    private var _player: AVPlayer?

    /// Back-compat for earlier iterations that referenced `nowPlaying.player`.
    /// Prefer `currentPlayer()` for read-only access.
    var player: AVPlayer? { _player }
    private var timeObserverToken: Any?
    private var notificationTokens: [NSObjectProtocol] = []

    private var lastProgressReportTicks: Int = 0
    private var hasReportedStart: Bool = false

    private weak var sessionRef: SessionStore?

    // MARK: - Public API

    var hasActiveItem: Bool { item != nil }

    func currentPlayer() -> AVPlayer? { _player }

    func presentPlayer() {
        guard item != nil else { return }
        isPlayerPresented = true
    }

    func minimizePlayer() {
        isPlayerPresented = false
    }

    func togglePlayPause() {
        guard let p = _player else { return }
        if p.timeControlStatus == .playing {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    /// Stop playback and clear state.
    func stop(playedToCompletion: Bool = false, failed: Bool = false) {
        Task {
            await reportStopped(playedToCompletion: playedToCompletion, failed: failed)
            teardownPlayer()
            item = nil
            isPlayerPresented = false
            progress = 0
            currentPositionTicks = 0
            hasReportedStart = false
            lastProgressReportTicks = 0
        }
    }

    /// Begin playback for a Jellyfin item.
    func play(
        itemId: String,
        title: String,
        subtitle: String?,
        posterURL: URL?,
        startPositionTicks: Int,
        session: SessionStore
    ) {
        Task {
            do {
                self.sessionRef = session

                let context = try await session.playbackContext(for: itemId)
                let newItem = NowPlayingItem(
                    id: itemId,
                    title: title,
                    subtitle: subtitle,
                    posterURL: posterURL,
                    playbackContext: context,
                    startPositionTicks: startPositionTicks
                )

                // Replace any existing playback.
                teardownPlayer()

                item = newItem
                setupPlayer(url: context.url, startPositionTicks: startPositionTicks)
                isPlayerPresented = true

            } catch {
                // If we fail to start playback, clear any half-state.
                teardownPlayer()
                item = nil
                isPlayerPresented = false
            }
        }
    }

    // MARK: - Player setup

    private func setupPlayer(url: URL, startPositionTicks: Int) {
        let player = AVPlayer(url: url)
        self._player = player

        attachObservers(to: player)

        // Seek before playing if needed.
        if startPositionTicks > 0 {
            let seconds = SessionStore.ticksToSeconds(startPositionTicks)
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            currentPositionTicks = startPositionTicks
        }

        player.play()
        isPlaying = true

        // Report start immediately once we have a player.
        Task { await reportStartedIfNeeded() }
    }

    private func attachObservers(to player: AVPlayer) {
        // Periodic progress
        let interval = CMTime(seconds: 1, preferredTimescale: 2)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            let ticks = SessionStore.secondsToTicks(seconds)
            self.currentPositionTicks = ticks

            if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
                self.progress = min(max(seconds / duration, 0), 1)
            } else {
                self.progress = 0
            }

            self.isPlaying = player.timeControlStatus == .playing

            // Jellyfin progress reporting every ~5 seconds.
            if abs(ticks - self.lastProgressReportTicks) >= SessionStore.secondsToTicks(5) {
                self.lastProgressReportTicks = ticks
                Task { await self.reportProgress() }
            }
        }

        // Playback ended
        let endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.stop(playedToCompletion: true, failed: false)
        }
        notificationTokens.append(endToken)
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let p = _player {
            p.removeTimeObserver(token)
        }
        timeObserverToken = nil

        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()

        _player?.pause()
        _player = nil

        isPlaying = false
    }

    // MARK: - Jellyfin reporting

    private func reportStartedIfNeeded() async {
        guard !hasReportedStart else { return }
        guard let item else { return }
        guard let session = sessionRef else { return }

        hasReportedStart = true
        await session.reportPlaybackStarted(
            context: item.playbackContext,
            itemId: item.id,
            positionTicks: currentPositionTicks,
            isPaused: false
        )
    }

    private func reportProgress() async {
        guard let item else { return }
        guard let session = sessionRef else { return }

        await reportStartedIfNeeded()
        await session.reportPlaybackProgress(
            context: item.playbackContext,
            itemId: item.id,
            positionTicks: currentPositionTicks,
            isPaused: !isPlaying
        )
    }

    private func reportStopped(playedToCompletion: Bool, failed: Bool) async {
        guard let item else { return }
        guard let session = sessionRef else { return }

        await session.reportPlaybackStopped(
            context: item.playbackContext,
            itemId: item.id,
            positionTicks: currentPositionTicks,
            playedToCompletion: playedToCompletion,
            failed: failed
        )
    }
}
