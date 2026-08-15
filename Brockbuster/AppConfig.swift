import Foundation

/// Central build-time configuration for a Brockbuster deployment.
///
/// Out of the box every value is nil and the app behaves as a generic Jellyfin
/// client: users are asked for their server address on first launch, the
/// companion-service features (Server Health, Friends, People, Social) stay
/// hidden, and in-app bug reporting is disabled.
///
/// To ship a build tailored to your own community, fill in the values below.
enum AppConfig {

    /// Jellyfin server URL to pre-configure for white-label builds.
    ///
    /// When set, the app skips the server-setup screen and goes straight to
    /// login against this server (users can still change it later). When nil,
    /// first launch shows `ServerSetupView` and asks for a server address.
    static let defaultServerURL: URL? = nil

    /// Base URL of an optional companion "service layer" (NOT Jellyfin).
    ///
    /// This is a separate web service that powers the community features:
    /// Server Health dashboard, Friends, and the People directory. The client
    /// authenticates against it with the user's Jellyfin token; the expected
    /// endpoints and response shapes are documented in docs/SERVICE_API.md.
    ///
    /// When nil, all of these features are hidden from the UI and
    /// `BrockbusterAPI` refuses to make requests.
    static let serviceBaseURL: URL? = nil

    /// Discord webhook that receives in-app bug reports.
    ///
    /// When nil, the "Report a Bug" entry and the shake-to-report gesture are
    /// disabled. Note that anything compiled into a public build is public:
    /// prefer proxying reports through your own server rather than shipping a
    /// raw webhook URL to users.
    static let bugReportWebhookURL: URL? = nil

    /// Convenience: whether the companion service layer is configured.
    static var serviceFeaturesEnabled: Bool { serviceBaseURL != nil }

    /// Convenience: whether in-app bug reporting is configured.
    static var bugReportingEnabled: Bool { bugReportWebhookURL != nil }
}
