import Foundation
import SwiftUI
import AVKit
import AVFoundation

#if canImport(MediaPlayer)
import MediaPlayer
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Centralized playback manager that keeps an AVPlayer alive even when the
/// full-screen player UI is dismissed, enabling a "Now Playing" bar.
@MainActor
final class NowPlayingManager: ObservableObject {

    // MARK: - Media typing

    enum MediaKind: String, Codable {
        case movie
        case episode
        case other
    }

    struct EpisodeContext: Equatable, Codable {
        let seriesId: String
    }

    struct UpNextState: Equatable {
        let episodeId: String
        let seriesId: String?
        let seriesTitle: String
        let episodeTitle: String
        let subtitle: String
        let posterURL: URL?
        let startPositionTicks: Int
        let countdownSeconds: Int
        let createdAt: Date
    }

    struct IntroWindow: Equatable {
        let startTicks: Int
        let endTicks: Int
    }

    struct NowPlayingItem: Identifiable, Equatable {
        let id: String // Jellyfin itemId
        let title: String
        let subtitle: String?
        let posterURL: URL?
        let playbackContext: SessionStore.PlaybackContext
        let startPositionTicks: Int

        // Optional structured episode context (improves Now Playing + Dynamic Island display)
        let seriesTitle: String?
        let seasonNumber: Int?
        let episodeNumber: Int?
        let episodeTitle: String?

        // Episode-specific context (used for autoplay next episode).
        let mediaKind: MediaKind
        let episodeContext: EpisodeContext?
    }

    // MARK: - Published state

    /// The currently playing item (if any).
    @Published private(set) var item: NowPlayingItem?

    /// If present, the user is near the end of an episode and we are offering an
    /// autoplay transition to the next episode.
    @Published private(set) var upNext: UpNextState?

    /// Intro seek window (ticks) if Jellyfin provided intro segments.
    @Published private(set) var introWindow: IntroWindow?

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

    private var hasPreparedUpNext: Bool = false
    private var autoplayCancelled: Bool = false

    private weak var sessionRef: SessionStore?

    // MARK: - System Now Playing (Lock Screen / Control Center)
    //
    // NOTE:
    // - This is compiled only when MediaPlayer is available.
    // - UIKit usage is guarded for platforms that provide it.

    #if canImport(MediaPlayer)
    private var systemNowPlayingInfo: [String: Any] = [:]
    private var remoteCommandsConfigured: Bool = false
    private var artworkTask: Task<Void, Never>?
    #endif

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

        #if canImport(MediaPlayer)
        updateSystemNowPlayingInfo()
        #endif
    }

    /// Stop playback and clear state.
    func stop(playedToCompletion: Bool = false, failed: Bool = false) {
        Task {
            await reportStopped(playedToCompletion: playedToCompletion, failed: failed)
            teardownPlayer()

            #if canImport(MediaPlayer)
            clearSystemNowPlaying()
            #endif

            #if canImport(ActivityKit)
            LiveActivityManager.shared.end()
            #endif

            item = nil
            isPlayerPresented = false
            progress = 0
            currentPositionTicks = 0
            hasReportedStart = false
            lastProgressReportTicks = 0

            upNext = nil
            introWindow = nil
            hasPreparedUpNext = false
            autoplayCancelled = false

            #if canImport(MediaPlayer)
            clearSystemNowPlaying()
            #endif
        }
    }

    /// Begin playback for a Jellyfin item.
    func play(
        itemId: String,
        title: String,
        subtitle: String?,
        posterURL: URL?,
        startPositionTicks: Int,
        mediaKind: MediaKind = .other,
        seriesIdForEpisode: String? = nil,
        seriesTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        session: SessionStore
    ) {
        Task {
            do {
                self.sessionRef = session

                let context = try await session.playbackContext(for: itemId)
                let episodeContext: EpisodeContext? = {
                    guard mediaKind == .episode else { return nil }
                    guard let seriesIdForEpisode, !seriesIdForEpisode.isEmpty else { return nil }
                    return EpisodeContext(seriesId: seriesIdForEpisode)
                }()

                let newItem = NowPlayingItem(
                    id: itemId,
                    title: title,
                    subtitle: subtitle,
                    posterURL: posterURL,
                    playbackContext: context,
                    startPositionTicks: startPositionTicks,
                    seriesTitle: seriesTitle,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    episodeTitle: episodeTitle,
                    mediaKind: mediaKind,
                    episodeContext: episodeContext
                )

                // Replace any existing playback.
                #if canImport(MediaPlayer)
                clearSystemNowPlaying()
                #endif

                #if canImport(ActivityKit)
                LiveActivityManager.shared.end()
                #endif

                teardownPlayer()

                item = newItem
                upNext = nil
                introWindow = nil
                hasPreparedUpNext = false
                autoplayCancelled = false
                setupPlayer(url: context.url, startPositionTicks: startPositionTicks)
                isPlayerPresented = true

                #if canImport(MediaPlayer)
                configureAudioSessionForPlaybackIfPossible()
                configureRemoteCommandsIfNeeded()
                updateSystemNowPlayingInfo()
                updateSystemNowPlayingArtworkIfNeeded()
                #endif

                #if canImport(ActivityKit)
                let startSeconds = SessionStore.ticksToSeconds(startPositionTicks)
                LiveActivityManager.shared.startIfNeeded(
                    itemId: itemId,
                    posterURL: posterURL,
                    title: title,
                    subtitle: subtitle,
                    isPlaying: true,
                    positionSeconds: startSeconds,
                    durationSeconds: 0,
                    seriesTitle: seriesTitle,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    episodeTitle: episodeTitle
                )
                #endif

                // Best-effort: fetch intro segments for episodes.
                if mediaKind == .episode {
                    Task { await loadIntroWindowIfAvailable(itemId: itemId) }
                }

            } catch {
                // If we fail to start playback, clear any half-state.
                teardownPlayer()
                item = nil
                isPlayerPresented = false
            }
        }
    }

    /// User opted out of autoplay for the current episode.
    func cancelAutoplayNext() {
        autoplayCancelled = true
        upNext = nil
    }

    /// Immediately play the prepared next episode (if available).
    func playNextUpNow() {
        guard let next = upNext else { return }
        guard let session = sessionRef else { return }

        // Treat this as a completion of the current item.
        Task {
            await reportStopped(playedToCompletion: true, failed: false)
            await MainActor.run {
                teardownPlayer()
                item = nil
                progress = 0
                currentPositionTicks = 0
                hasReportedStart = false
                lastProgressReportTicks = 0
                hasPreparedUpNext = false
                autoplayCancelled = false
                introWindow = nil
                upNext = nil
            }

            // Start next episode.
            let effectivePoster = session.itemImageURL(itemId: next.seriesId ?? next.episodeId, kind: "Primary", maxWidth: 700)
                ?? session.itemImageURL(itemId: next.episodeId, kind: "Primary", maxWidth: 700)
                ?? next.posterURL

            await MainActor.run {
                self.play(
                    itemId: next.episodeId,
                    title: next.seriesTitle,
                    subtitle: next.subtitle,
                    posterURL: effectivePoster,
                    startPositionTicks: next.startPositionTicks,
                    mediaKind: .episode,
                    seriesIdForEpisode: next.seriesId,
                    session: session
                )
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

            #if canImport(MediaPlayer)
            self.updateSystemNowPlayingInfo()
            #endif

            #if canImport(ActivityKit)
            if let current = self.item {
                LiveActivityManager.shared.update(
                    title: current.seriesTitle ?? current.title,
                    subtitle: current.subtitle,
                    isPlaying: self.isPlaying,
                    positionSeconds: seconds,
                    durationSeconds: (player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? 0 : 0),
                    seriesTitle: current.seriesTitle,
                    seasonNumber: current.seasonNumber,
                    episodeNumber: current.episodeNumber,
                    episodeTitle: current.episodeTitle
                )
            }
            #endif

            // Autoplay next episode prompt (~15s remaining)
            self.maybePrepareUpNext(secondsElapsed: seconds, player: player)

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
            self?.handlePlaybackEnded()
        }
        notificationTokens.append(endToken)
    }

    private func maybePrepareUpNext(secondsElapsed: Double, player: AVPlayer) {
        guard let current = item else { return }
        guard current.mediaKind == .episode else { return }
        guard autoplayCancelled == false else { return }
        guard hasPreparedUpNext == false else { return }
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }

        let remaining = duration - secondsElapsed
        guard remaining <= 15.0, remaining > 0 else { return }

        hasPreparedUpNext = true
        Task { await prepareUpNextForCurrentEpisode() }
    }

    private func prepareUpNextForCurrentEpisode() async {
        guard let current = item else { return }
        guard current.mediaKind == .episode else { return }
        guard let seriesId = current.episodeContext?.seriesId else { return }
        guard let session = sessionRef else { return }

        do {
            guard let nextUp = try await session.fetchNextUpEpisode(seriesId: seriesId) else {
                // No next-up -> treat as last episode.
                await MainActor.run {
                    upNext = nil
                }
                return
            }

            let se = {
                var parts: [String] = []
                if let s = nextUp.parentIndexNumber, s > 0 { parts.append("S\(s)") }
                if let e = nextUp.indexNumber, e > 0 { parts.append("E\(e)") }
                return parts.joined(separator: " • ")
            }()
            let subtitle = [se, nextUp.name].filter { !$0.isEmpty }.joined(separator: " • ")
            let seriesTitle = nextUp.seriesName ?? current.title

            // Prefer series poster; fall back to episode primary.
            let poster = session.itemImageURL(itemId: nextUp.seriesId ?? nextUp.id, kind: "Primary", maxWidth: 700)

            await MainActor.run {
                upNext = UpNextState(
                    episodeId: nextUp.id,
                    seriesId: nextUp.seriesId ?? seriesId,
                    seriesTitle: seriesTitle,
                    episodeTitle: nextUp.name,
                    subtitle: subtitle,
                    posterURL: poster,
                    startPositionTicks: nextUp.userData?.playbackPositionTicks ?? 0,
                    countdownSeconds: 15,
                    createdAt: Date()
                )
            }
        } catch {
            await MainActor.run {
                upNext = nil
            }
        }
    }

    private func handlePlaybackEnded() {
        // If we're on an episode and have a next-up offer and the user didn't cancel,
        // autoplay immediately.
        if let _ = upNext, autoplayCancelled == false {
            playNextUpNow()
            return
        }

        // Otherwise stop and dismiss back to the underlying screen.
        stop(playedToCompletion: true, failed: false)
    }

    // MARK: - Skip Intro (media segments)

    private func loadIntroWindowIfAvailable(itemId: String) async {
        guard let session = sessionRef else { return }
        do {
            let segments = try await session.fetchMediaSegments(itemId: itemId)
            // Look for an intro segment.
            if let intro = segments.first(where: { ($0.type ?? "").lowercased() == "intro" }),
               let start = intro.startTicks,
               let end = intro.endTicks,
               end > start {
                await MainActor.run {
                    self.introWindow = IntroWindow(startTicks: start, endTicks: end)
                }
            }
        } catch {
            // No-op.
        }
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

    // MARK: - System Now Playing helpers (iOS/iPadOS)

    #if canImport(MediaPlayer)

    /// Configure an AVAudioSession category suitable for media playback.
    /// Safe to call repeatedly.
    private func configureAudioSessionForPlaybackIfPossible() {
        #if os(iOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // Best-effort only.
        }
        #endif
    }

    private func configureRemoteCommandsIfNeeded() {
        guard remoteCommandsConfigured == false else { return }
        remoteCommandsConfigured = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            guard let self, let p = self._player else { return .commandFailed }
            p.play()
            self.isPlaying = true
            self.updateSystemNowPlayingInfo()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, let p = self._player else { return .commandFailed }
            p.pause()
            self.isPlaying = false
            self.updateSystemNowPlayingInfo()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let e = event as? MPChangePlaybackPositionCommandEvent,
                  let p = self._player
            else { return .commandFailed }

            p.seek(to: CMTime(seconds: e.positionTime, preferredTimescale: 600))
            self.currentPositionTicks = SessionStore.secondsToTicks(e.positionTime)
            self.updateSystemNowPlayingInfo()
            return .success
        }
    }

    private func updateSystemNowPlayingInfo() {
        // Do not clear system Now Playing due to transient state changes (e.g. stream switching).
        // We only clear explicitly on stop.
        guard let item else { return }

        let elapsedSeconds = SessionStore.ticksToSeconds(currentPositionTicks)
        let durationSeconds: Double = {
            guard let p = _player,
                  let d = p.currentItem?.duration.seconds,
                  d.isFinite, d > 0
            else { return 0 }
            return d
        }()

        let displayTitle = item.seriesTitle ?? item.title

        var displaySubtitle: String = item.subtitle ?? ""
        if item.mediaKind == .episode {
            var seParts: [String] = []
            if let s = item.seasonNumber, s > 0 { seParts.append("S\(s)") }
            if let e = item.episodeNumber, e > 0 { seParts.append("E\(e)") }
            let se = seParts.joined(separator: " • ")

            if let epTitle = item.episodeTitle, !epTitle.isEmpty {
                displaySubtitle = se.isEmpty ? epTitle : "\(se) — \(epTitle)"
            } else if !se.isEmpty {
                displaySubtitle = se
            }
        }

        systemNowPlayingInfo[MPMediaItemPropertyTitle] = displayTitle
        systemNowPlayingInfo[MPMediaItemPropertyArtist] = displaySubtitle
        systemNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = durationSeconds
        systemNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedSeconds
        systemNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = systemNowPlayingInfo
    }

    private func updateSystemNowPlayingArtworkIfNeeded() {
        #if canImport(UIKit)
        guard let url = item?.posterURL else { return }

        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }

                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

                await MainActor.run {
                    guard let self else { return }
                    self.systemNowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = self.systemNowPlayingInfo
                }
            } catch {
                // Best-effort only.
            }
        }
        #endif
    }

    private func clearSystemNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        systemNowPlayingInfo = [:]
        artworkTask?.cancel()
        artworkTask = nil
    }

    #endif
}
