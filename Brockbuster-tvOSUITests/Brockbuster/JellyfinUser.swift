import Foundation

/// Represents a user returned from Jellyfin's authentication endpoint.  Only a
/// subset of available properties are included; additional fields can be added
/// depending on what information is needed in the UI.
struct JellyfinUser: Identifiable, Codable {
    /// The Jellyfin user ID.  This is used to identify the user in subsequent
    /// requests.
    let id: String
    /// The user's display name (username).
    let name: String
    /// Tag used to fetch the user's primary profile image.  Jellyfin
    /// associates a tag with an image so that clients can construct the image URL
    /// and avoid fetching outdated images.  This may be nil if the user has no
    /// custom image.
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case primaryImageTag = "PrimaryImageTag"
    }
}
