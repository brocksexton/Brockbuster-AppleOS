import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Starts and updates the Brockbuster "Now Playing" Live Activity.
///
/// Rendering requires a Widget Extension with an ActivityConfiguration.
/// This manager is safe to include in multi-platform builds; it compiles only
/// when ActivityKit is available (iOS 16.1+).
@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var activity: Activity<BrockbusterNowPlayingAttributes>?

    private init() {}

    func startIfNeeded(
        itemId: String,
        posterURL: URL?,
        title: String,
        subtitle: String?,
        isPlaying: Bool,
        positionSeconds: Double,
        durationSeconds: Double,
        seriesTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil
    ) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Reuse an existing activity if one is already running for this item.
        if let activity, activity.attributes.itemId == itemId {
            update(
                title: title,
                subtitle: subtitle,
                isPlaying: isPlaying,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                seriesTitle: seriesTitle,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                episodeTitle: episodeTitle
            )
            return
        }

        let attributes = BrockbusterNowPlayingAttributes(
            itemId: itemId,
            posterURLString: posterURL?.absoluteString
        )

        let state = BrockbusterNowPlayingAttributes.ContentState(
            title: title,
            subtitle: subtitle,
            isPlaying: isPlaying,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle
        )

        do {
            self.activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
        } catch {
            // Best-effort only.
            self.activity = nil
        }
    }

    func update(
        title: String,
        subtitle: String?,
        isPlaying: Bool,
        positionSeconds: Double,
        durationSeconds: Double,
        seriesTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil
    ) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }

        let newState = BrockbusterNowPlayingAttributes.ContentState(
            title: title,
            subtitle: subtitle,
            isPlaying: isPlaying,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle
        )

        Task {
            await activity.update(using: newState)
        }
    }

    func end() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }

        Task {
            await activity.end(dismissalPolicy: .immediate)
        }

        self.activity = nil
    }
}

#endif
