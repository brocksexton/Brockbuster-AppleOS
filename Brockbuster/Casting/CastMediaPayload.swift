import Foundation

/// Normalized payload for "cast this item" actions.
///
/// Note: For broad device compatibility we primarily pass a single, directly playable URL.
/// Many casting targets (DLNA, Roku deep-linking, etc.) cannot accept custom HTTP headers,
/// so authentication must be embedded in the URL (e.g., Jellyfin `api_key` query parameter).
struct CastMediaPayload: Equatable {
    let url: URL
    let title: String
    let subtitle: String?
    let posterURL: URL?
}
