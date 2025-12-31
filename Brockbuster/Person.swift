import Foundation

/// A model representing a person with identifiable and codable properties.
/// Conforms to `Identifiable`, `Codable`, `Hashable`, and `Sendable`.
public struct Person: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for the person.
    public let id: String
    /// Display name of the person.
    public let displayName: String
    /// Optional URL string of the person's avatar image.
    public let avatarURL: String?
    /// Optional description of the relationship with the person.
    public let relationship: String?
    
    /// Initializes a new `Person`.
    /// - Parameters:
    ///   - id: Unique identifier for the person.
    ///   - displayName: Display name of the person.
    ///   - avatarURL: Optional URL string of the person's avatar image. Defaults to `nil`.
    ///   - relationship: Optional description of the relationship with the person. Defaults to `nil`.
    public init(
        id: String,
        displayName: String,
        avatarURL: String? = nil,
        relationship: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.relationship = relationship
    }
    
    /// A static mock person for previews and tests.
    public static let mock = Person(
        id: "123",
        displayName: "John Doe",
        avatarURL: "https://example.com/avatar.jpg",
        relationship: "Friend"
    )
}
