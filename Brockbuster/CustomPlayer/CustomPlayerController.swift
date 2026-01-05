import Foundation
import AVFoundation
import AVKit
import SwiftUI

/// Playback engine backing Brockbuster's fully custom player UI (iOS/iPadOS).
///
/// Notes
/// - We intentionally do **not** use `AVPlayerViewController` for iOS/iPadOS, because its
///   built-in chrome competes with custom overlays.
/// - tvOS continues to use `AVPlayerViewController` elsewhere in the codebase for best
///   Siri Remote ergonomics.
final class CustomPlayerController: NSObject, ObservableObject {

    // MARK: - Main-thread helper

    /// Ensures state mutations that drive SwiftUI happen on the main thread.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - Published state

    @Published var isReadyToPlay: Bool = false
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var bufferedTime: Double = 0

    @Published var legibleOptions: [AVMediaSelectionOption] = []
    @Published var audibleOptions: [AVMediaSelectionOption] = []
    @Published var selectedLegible: AVMediaSelectionOption? = nil
    @Published var selectedAudible: AVMediaSelectionOption? = nil

    @Published var pipIsPossible: Bool = false
    @Published var pipIsActive: Bool = false

    // MARK: - Private

    let player: AVPlayer
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var loadedTimeRangesObserver: NSKeyValueObservation?
    private var itemDidEndObserver: NSObjectProtocol?

    #if os(iOS)
    private var pipController: AVPictureInPictureController?
    private weak var playerLayer: AVPlayerLayer?
    #endif

    var onEnded: (() -> Void)?
    var onFailedToPlayToEnd: ((Error?) -> Void)?

    init(url: URL, startPositionSeconds: Double = 0) {
        let item = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: item)
        super.init()

        configureObservers()
        if startPositionSeconds > 0 {
            seek(to: startPositionSeconds, shouldPlayAfter: true)
        }
    }

    deinit {
        teardown()
    }

    func replace(url: URL, startPositionSeconds: Double = 0, autoPlay: Bool = true) {
        teardownItemObserversOnly()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        configureItemObservers()
        if startPositionSeconds > 0 {
            seek(to: startPositionSeconds, shouldPlayAfter: autoPlay)
        } else if autoPlay {
            play()
        }
    }

    // MARK: - Commands

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double, shouldPlayAfter: Bool? = nil) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            self.currentTime = clamped
            if let shouldPlayAfter {
                shouldPlayAfter ? self.play() : self.pause()
            }
        }
    }

    func skip(by delta: Double) {
        seek(to: currentTime + delta)
    }

    // MARK: - Tracks

    func refreshTracks() {
        guard let item = player.currentItem else {
            legibleOptions = []
            audibleOptions = []
            selectedLegible = nil
            selectedAudible = nil
            return
        }

        let asset = item.asset
        if let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            legibleOptions = group.options
            selectedLegible = item.currentMediaSelection.selectedMediaOption(in: group)
        } else {
            legibleOptions = []
            selectedLegible = nil
        }

        if let group = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            audibleOptions = group.options
            selectedAudible = item.currentMediaSelection.selectedMediaOption(in: group)
        } else {
            audibleOptions = []
            selectedAudible = nil
        }
    }

    func selectLegible(_ option: AVMediaSelectionOption?) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return
        }

        if let option {
            item.select(option, in: group)
            selectedLegible = option
        } else {
            item.select(nil, in: group)
            selectedLegible = nil
        }
    }

    func selectAudible(_ option: AVMediaSelectionOption?) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return
        }

        if let option {
            item.select(option, in: group)
            selectedAudible = option
        } else {
            // Selecting nil for audio is unusual; keep current selection.
        }
    }

    // MARK: - PiP

    #if os(iOS)
    func attachPlayerLayerForPiP(_ layer: AVPlayerLayer) {
        playerLayer = layer
        rebuildPiPControllerIfPossible()
    }

    private func rebuildPiPControllerIfPossible() {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let layer = playerLayer else {
            pipController = nil
            pipIsPossible = false
            return
        }

        pipController = AVPictureInPictureController(playerLayer: layer)
        pipController?.delegate = self
        pipIsPossible = pipController != nil
    }

    func togglePiP() {
        guard let pipController, pipIsPossible else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }
    #endif

    // MARK: - Observers

    private func configureObservers() {
        configureItemObservers()

        timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            guard let self else { return }
            self.onMain {
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                case .paused:
                    self.isBuffering = false
                    self.isPlaying = false
                case .playing:
                    self.isBuffering = false
                    self.isPlaying = true
                @unknown default:
                    break
                }
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = max(0, seconds)
        }
    }

    private func configureItemObservers() {
        guard let item = player.currentItem else { return }

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            self.onMain {
                switch item.status {
                case .readyToPlay:
                    self.isReadyToPlay = true
                    let dur = item.duration.seconds
                    self.duration = dur.isFinite ? dur : 0
                    self.refreshTracks()
                    // Autoplay, but only once the item is ready.
                    self.play()
                case .failed:
                    self.isReadyToPlay = false
                    self.onFailedToPlayToEnd?(item.error)
                case .unknown:
                    self.isReadyToPlay = false
                @unknown default:
                    break
                }
            }
        }

        loadedTimeRangesObserver = item.observe(\.loadedTimeRanges, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            self.onMain {
                guard let range = item.loadedTimeRanges.first?.timeRangeValue else {
                    self.bufferedTime = 0
                    return
                }
                let end = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
                self.bufferedTime = end.isFinite ? end : 0
            }
        }

        itemDidEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.onEnded?()
        }
    }

    private func teardownItemObserversOnly() {
        statusObserver?.invalidate()
        statusObserver = nil
        loadedTimeRangesObserver?.invalidate()
        loadedTimeRangesObserver = nil
        if let itemDidEndObserver {
            NotificationCenter.default.removeObserver(itemDidEndObserver)
            self.itemDidEndObserver = nil
        }
    }

    private func teardown() {
        teardownItemObserversOnly()

        timeControlObserver?.invalidate()
        timeControlObserver = nil

        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }

        #if os(iOS)
        pipController?.delegate = nil
        pipController = nil
        #endif
    }
}

#if os(iOS)
extension CustomPlayerController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipIsActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipIsActive = false
    }
}
#endif

extension CustomPlayerController {
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
