import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Shared attributes for the Brockbuster "Now Playing" Live Activity.
///
/// A Widget Extension (with an ActivityConfiguration) is required to render the
/// Live Activity on the Lock Screen and in the Dynamic Island.
public struct BrockbusterNowPlayingAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        public var title: String
        public var subtitle: String?
        public var isPlaying: Bool
        public var positionSeconds: Double
        public var durationSeconds: Double

        public init(
            title: String,
            subtitle: String?,
            isPlaying: Bool,
            positionSeconds: Double,
            durationSeconds: Double
        ) {
            self.title = title
            self.subtitle = subtitle
            self.isPlaying = isPlaying
            self.positionSeconds = positionSeconds
            self.durationSeconds = durationSeconds
        }
    }

    public var itemId: String
    public var posterURLString: String?

    public init(itemId: String, posterURLString: String?) {
        self.itemId = itemId
        self.posterURLString = posterURLString
    }
}

#endif
