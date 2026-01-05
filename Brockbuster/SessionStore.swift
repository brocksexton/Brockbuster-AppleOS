import Foundation
import SwiftUI

/// Captures codec/container information used to decide whether an offline download
/// should be requested as a direct file or a server-side compatibility transcode.
struct OfflineCompatibilityReport {
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let requiresTranscode: Bool
}

/// Shared application state managing the connection to the Jellyfin server,
/// authentication token and current user.  Views can observe this object to
/// automatically react to changes (e.g. showing login when the user logs out).
@MainActor
final class SessionStore: ObservableObject {

    // MARK: - Connectivity

    enum ConnectionState: String, Codable {
        case unknown
        case online
        case offline
    }

    /// Tracks whether the Brockbuster (Jellyfin) server is reachable.
    ///
    /// This is intentionally conservative and only reflects basic connectivity to the
    /// server's health endpoint.
    @Published var connectionState: ConnectionState = .unknown

    /// Sticky offline-first mode.
    ///
    /// When we detect that Brockbuster/Jellyfin is unreachable, we keep the user
    /// in an offline-first experience (Downloads) until the user explicitly
    /// retries and the server health check succeeds. This prevents "offline"
    /// UI flicker / boot-looping when connectivity is intermittent.
    @Published var offlineModeEnabled: Bool = false

    /// A human-friendly description of the last connectivity failure (if any).
    @Published var lastConnectionError: String? = nil

    // MARK: - Playback Context

    struct PlaybackContext: Sendable, Equatable {
        let url: URL
        let mediaSourceId: String?
        let playSessionId: String?
    }

    /// Converts seconds to Jellyfin ticks (10,000,000 ticks = 1 second).
    static func secondsToTicks(_ seconds: Double) -> Int {
        Int(seconds * 10_000_000.0)
    }

    /// Converts Jellyfin ticks to seconds.
    /// (10,000,000 ticks = 1 second)
    static func ticksToSeconds(_ ticks: Int) -> Double {
        Double(ticks) / 10_000_000.0
    }

    // The default server URL used when the user has not provided one.  This is
    // configured for the Brockbuster service, but can be overridden by users via
    // the server setup screen.
    static let defaultServerURL: URL = URL(string: "https://vcr.brockbuster.lol")!
    // Keys for persisting server and token in UserDefaults
    private struct Keys {
        static let serverURL = "SessionStore.serverURL"
        static let accessToken = "SessionStore.accessToken"
        static let userData = "SessionStore.userData"
        static let joinDate = "SessionStore.joinDate"
    }

    /// The current server URL.  Changes are saved to UserDefaults.  When this
    /// property is updated the client property is recreated with the new URL.
    @Published var serverURL: URL {
        didSet {
            // Persist the new server URL when it changes.  The network client
            // should be updated explicitly in validateServer or resetServer.
            UserDefaults.standard.set(serverURL.absoluteString, forKey: Keys.serverURL)
        }
    }
    /// The currently authenticated user.  If nil then the login screen is shown.
    @Published var currentUser: JellyfinUser? {
        didSet {
            if let user = currentUser {
                // Persist user data as JSON
                if let data = try? JSONEncoder().encode(user) {
                    UserDefaults.standard.set(data, forKey: Keys.userData)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.userData)
            }
        }
    }
    /// The authentication token.  At present this is stored only in memory.  If
    /// persisting tokens, store them in the Keychain for security.  You may
    /// persist it similarly to the user data if desired.
    @Published var accessToken: String?

    /// The date when the user first logged in (member since).  This value is persisted
    /// in UserDefaults.  If nil, the user has not yet logged in.
    @Published var joinDate: Date?
    /// The underlying network client.  When the server URL changes this is
    /// recreated.
    private var client: JellyfinClient

    /// The list of libraries (views) available to the authenticated user.  This
    /// will be populated after calling `fetchLibraries()`.  Views correspond to
    /// top-level libraries such as Movies, TV Shows, Music and so on.
    @Published var libraries: [JellyfinClient.LibraryView] = []
    /// Indicates whether libraries are currently being fetched.  Use this to show
    /// loading indicators in the UI.
    @Published var isFetchingLibraries: Bool = false

    /// A simple in-memory cache of items per library.  The key is the library's
    /// id and the value is the array of items previously fetched.  This cache
    /// persists for the duration of the session and is cleared on logout or when
    /// the server is reset.
    private var itemCache: [String: [JellyfinClient.LibraryItem]] = [:]

    /// Computed property returning whether the user is logged in.
    var isLoggedIn: Bool {
        return currentUser != nil && accessToken != nil
    }

    init() {
        // Determine the initial server URL without referencing `self` to avoid
        // accessing properties before all stored properties are initialised.
        let initialURL: URL
        if let savedString = UserDefaults.standard.string(forKey: Keys.serverURL), let url = URL(string: savedString) {
            initialURL = url
        } else {
            initialURL = Self.defaultServerURL
        }
        // Assign stored properties using the computed initialURL and loaded user
        self.serverURL = initialURL
        if let data = UserDefaults.standard.data(forKey: Keys.userData), let user = try? JSONDecoder().decode(JellyfinUser.self, from: data) {
            self.currentUser = user
        } else {
            self.currentUser = nil
        }
        self.accessToken = nil
        // Load persisted join date if available
        if let timestamp = UserDefaults.standard.object(forKey: Keys.joinDate) as? TimeInterval {
            self.joinDate = Date(timeIntervalSince1970: timestamp)
        } else {
            self.joinDate = nil
        }
        self.client = JellyfinClient(baseURL: initialURL)
        self.libraries = []
        self.isFetchingLibraries = false
        self.itemCache = [:]

        // Perform a lightweight connectivity check on startup.
        Task { [weak self] in
            await self?.refreshConnectionStatus()
        }
    }

    /// Performs a lightweight reachability check against the server health endpoint.
    ///
    /// This should be called on app launch and when returning to foreground.
    func refreshConnectionStatus(userInitiated: Bool = false) async {
        // Avoid spamming the server if views call this frequently.
        // A simple debounce is sufficient for our use case.
        // (We keep it minimal to avoid introducing a full connectivity subsystem.)
        do {
            try await withCheckedThrowingContinuation { continuation in
                self.client.checkHealth { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            // On success, only exit sticky offline mode when the user explicitly
            // requested a retry. This avoids oscillation between Online and Offline
            // when the server is intermittently reachable.
            if userInitiated {
                self.offlineModeEnabled = false
            }

            if !self.offlineModeEnabled {
                if self.connectionState != .online {
                    self.connectionState = .online
                }
                self.lastConnectionError = nil
            } else {
                // Keep presenting offline-first UI even if this probe succeeded.
                self.connectionState = .offline
            }
        } catch {
            self.connectionState = .offline
            self.lastConnectionError = error.localizedDescription
            self.offlineModeEnabled = true
        }
    }

    /// Validate the server by checking its health endpoint.  Updates the
    /// `serverURL` property if validation succeeds.  Emits error on failure.
    func validateServer(urlString: String) async throws {
        guard let url = normaliseServerURL(from: urlString) else {
            throw ValidationError.invalidURL
        }
        let tempClient = JellyfinClient(baseURL: url)
        try await withCheckedThrowingContinuation { continuation in
            tempClient.checkHealth { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        // If we reach here the health check succeeded
        serverURL = url
        // Update network client now that the server URL has changed
        client = JellyfinClient(baseURL: url)
        offlineModeEnabled = false
        connectionState = .online
        lastConnectionError = nil
    }

    /// Attempt to log in with the given credentials.  On success the user and
    /// token are saved.  On failure an error is thrown.
    func login(username: String, password: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            client.authenticate(username: username, password: password) { [weak self] result in
                switch result {
                case .success(let user):
                    self?.currentUser = user
                    // Ideally capture the token; currently accessToken set on client is not exposed
                    // For now just mark as logged in by storing non-nil token placeholder
                    // Save token for session state; the client stores it internally
                    // Copy the token from the client so our session knows whether a user is logged in.
                    self?.accessToken = self?.client.token
                    // Record the join date if this is the user's first login
                    if self?.joinDate == nil {
                        let now = Date()
                        self?.joinDate = now
                        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Keys.joinDate)
                    }
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Restore a session using a previously stored access token and user.
    /// This is used for "remembered accounts" flows.
    func restoreSession(serverURL: URL, user: JellyfinUser, accessToken: String, memberSince: Date?) {
        self.serverURL = serverURL
        self.client = JellyfinClient(baseURL: serverURL)
        self.client.setToken(accessToken)
        self.currentUser = user
        self.accessToken = accessToken
        if let ms = memberSince {
            self.joinDate = ms
        }
        // Reset cached per-session data.
        self.libraries.removeAll()
        self.isFetchingLibraries = false
        self.itemCache.removeAll()
    }

    /// Reset the server URL to nil and clear all session information.
    func resetServer() {
        // Clear persisted values
        UserDefaults.standard.removeObject(forKey: Keys.serverURL)
        UserDefaults.standard.removeObject(forKey: Keys.userData)
        accessToken = nil
        currentUser = nil
        serverURL = Self.defaultServerURL
        client = JellyfinClient(baseURL: serverURL)
        connectionState = .unknown
        lastConnectionError = nil
        // Reset libraries when server changes
        libraries.removeAll()
        isFetchingLibraries = false
        // Clear cached items as they correspond to a previous server
        itemCache.removeAll()
    }

    /// Log the user out and clear the token and user information.
    func logout() {
        accessToken = nil
        currentUser = nil
        libraries.removeAll()
        isFetchingLibraries = false
        itemCache.removeAll()
        // Keep the last-known connection state; logging out should not force offline UI.
    }

    // MARK: - Helpers

    /// Normalise a potentially incomplete server string.  Adds https:// if missing and
    /// trims trailing slashes.
    private func normaliseServerURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // If no scheme, prefix with https
        let hasScheme = trimmed.contains("://")
        let withScheme = hasScheme ? trimmed : "https://" + trimmed
        // Remove trailing slash
        let cleaned = withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
        return URL(string: cleaned)
    }

    enum ValidationError: LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Please enter a valid URL."
            }
        }
    }

    // MARK: - Library fetching

    /// Fetch the user's libraries (views) from the server.  This method updates
    /// the `libraries` property when complete.  It must be called after the
    /// user has logged in (and `currentUser` is non-nil).  If the fetch fails
    /// the error is thrown and the `libraries` array remains unchanged.
    func fetchLibraries() async throws {
        guard let userId = currentUser?.id else { return }
        isFetchingLibraries = true
        defer { isFetchingLibraries = false }
        try await withCheckedThrowingContinuation { continuation in
            client.fetchViews(for: userId) { [weak self] result in
                switch result {
                case .success(let views):
                    self?.libraries = views
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetch the items within a library.  This method uses pagination to
    /// retrieve all items if the server applies a default limit【885896507571970†L321-L323】.  Results
    /// are cached in memory for the duration of the session.  Recursive is
    /// enabled to include items in subfolders (e.g. movies inside subdirectories).
    func fetchItems(
        for library: JellyfinClient.LibraryView,
        includeItemTypes: [String]? = nil,
        sortBy: [String]? = ["SortName"],
        sortOrder: String? = "Ascending"
    ) async throws -> [JellyfinClient.LibraryItem] {
        guard let userId = currentUser?.id else { return [] }
        // Return from cache if available
        if let cached = itemCache[library.id] {
            return cached
        }
        // Fetch items with recursion enabled. Jellyfin servers impose default
        // limits, so we page until the server returns fewer than `pageSize`.
        // Track seen IDs to prevent duplicate appends.
        var allItems: [JellyfinClient.LibraryItem] = []
        var seenIds: Set<String> = []
        let pageSize = 400
        var startIndex = 0
        // Cap to avoid pathological libraries; still far more than enough for
        // typical home servers. (400 * 25 = 10,000 items)
        for _ in 0..<25 {
            let page = try await withCheckedThrowingContinuation { continuation in
                client.fetchItems(
                    for: library.id,
                    userId: userId,
                    startIndex: startIndex,
                    limit: pageSize,
                    recursive: true,
                    includeItemTypes: includeItemTypes,
                    sortBy: sortBy,
                    sortOrder: sortOrder
                ) { result in
                    switch result {
                    case .success(let items):
                        continuation.resume(returning: items)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            let newItems = page.filter { seenIds.insert($0.id).inserted }
            allItems.append(contentsOf: newItems)
            if page.count < pageSize || newItems.isEmpty {
                break
            }
            startIndex += pageSize
        }
        itemCache[library.id] = allItems
        return allItems
    }

    /// Fetch a single page of items for a given parent (library or item) without caching.
    /// This is intended for lightweight home-screen sections like "Recently Added".
    func fetchItemsPage(
        parentId: String,
        includeItemTypes: [String]? = nil,
        sortBy: [String]? = nil,
        sortOrder: String? = nil,
        limit: Int = 24,
        recursive: Bool = true
    ) async throws -> [JellyfinClient.LibraryItem] {
        guard let userId = currentUser?.id else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            client.fetchItems(
                for: parentId,
                userId: userId,
                startIndex: 0,
                limit: limit,
                recursive: recursive,
                includeItemTypes: includeItemTypes,
                sortBy: sortBy,
                sortOrder: sortOrder
            ) { result in
                switch result {
                case .success(let items):
                    continuation.resume(returning: items)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetch Jellyfin "Continue Watching" (resume) items for the current user.
    func fetchResumeItems(limit: Int = 24) async throws -> [JellyfinClient.LibraryItem] {
        guard let userId = currentUser?.id else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            client.fetchResumeItems(userId: userId, limit: limit) { result in
                switch result {
                case .success(let items):
                    continuation.resume(returning: items)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetch a simple watch history list (recently played items).
    func fetchWatchHistory(limit: Int = 50) async throws -> [JellyfinClient.LibraryItem] {
        guard let userId = currentUser?.id else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            client.fetchWatchHistory(userId: userId, limit: limit) { result in
                switch result {
                case .success(let items):
                    continuation.resume(returning: items)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetch the current user's favourite items.
    ///
    /// Jellyfin exposes favourites via `Filters=IsFavorite` on the standard
    /// `/Users/{userId}/Items` endpoint.  We page to ensure larger favourite
    /// libraries load reliably.
    func fetchFavouriteItems(limit: Int = 150) async throws -> [JellyfinClient.LibraryItem] {
        guard let userId = currentUser?.id else { return [] }

        let pageSize = min(max(limit, 1), 200)
        var startIndex = 0
        var all: [JellyfinClient.LibraryItem] = []
        var seen = Set<String>()

        while all.count < limit {
            let remaining = limit - all.count
            let requestSize = min(pageSize, remaining)
            let page: [JellyfinClient.LibraryItem] = try await withCheckedThrowingContinuation { continuation in
                client.fetchFavouriteItems(userId: userId, limit: requestSize, startIndex: startIndex) { result in
                    switch result {
                    case .success(let items):
                        continuation.resume(returning: items)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            let newItems = page.filter { seen.insert($0.id).inserted }
            all.append(contentsOf: newItems)

            if page.count < requestSize || newItems.isEmpty {
                break
            }
            startIndex += requestSize
        }

        return all
    }

    /// Fetch the child items of a given library item (e.g. seasons of a series,
    /// episodes of a season, or contents of a collection).  Uses the same
    /// underlying API as `fetchItems(for: LibraryView)`.  Does not cache by
    /// default because the same item ID may represent a season or series.
    func fetchItems(
        for item: JellyfinClient.LibraryItem,
        includeItemTypes: [String]? = nil,
        sortBy: [String]? = nil,
        sortOrder: String? = nil
    ) async throws -> [JellyfinClient.LibraryItem] {
        guard let userId = currentUser?.id else { return [] }
        // Use a single page; seasons, episodes and collection contents are typically small
        return try await withCheckedThrowingContinuation { continuation in
            client.fetchItems(
                for: item.id,
                userId: userId,
                startIndex: 0,
                limit: 500,
                recursive: false,
                includeItemTypes: includeItemTypes,
                sortBy: sortBy,
                sortOrder: sortOrder
            ) { result in
                switch result {
                case .success(let items):
                    continuation.resume(returning: items)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Playback

    /// Fetch playback information for a given item.  Returns the media source id and play session id
    /// along with the full response.  Throws if the request fails.  Must be called after login.
    func fetchPlaybackInfo(itemId: String) async throws -> JellyfinClient.PlaybackInfo {
        guard let userId = currentUser?.id else {
            throw JellyfinClient.NetworkError.invalidResponse
        }
        return try await withCheckedThrowingContinuation { continuation in
            client.fetchPlaybackInfo(for: itemId, userId: userId) { result in
                switch result {
                case .success(let info):
                    continuation.resume(returning: info)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Remote Subtitles

    func searchRemoteSubtitles(itemId: String) async throws -> [JellyfinClient.RemoteSubtitleInfo] {
        guard let userId = currentUser?.id else { throw JellyfinClient.NetworkError.invalidResponse }
        return try await withCheckedThrowingContinuation { continuation in
            client.searchRemoteSubtitles(itemId: itemId, userId: userId) { result in
                switch result {
                case .success(let subs): continuation.resume(returning: subs)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }
    }

    func downloadRemoteSubtitle(itemId: String, subtitleId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            client.downloadRemoteSubtitle(itemId: itemId, subtitleId: subtitleId) { result in
                switch result {
                case .success: continuation.resume(returning: ())
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }
    }

    /// Construct a stream URL for a given item.  This first fetches playback info to obtain
    /// the media source ID and play session ID, then uses the client to build the final URL.
    /// Throws if the server responds with an error or if a valid stream URL cannot be built.
    
    /// Construct a stream URL for a given item. This first fetches playback info to obtain
    /// the media source ID and play session ID, then uses the client to build the final URL.
    /// Returns a `PlaybackContext` so the caller can report playback (started/progress/stopped).
    func playbackContext(for itemId: String) async throws -> PlaybackContext {
        try await playbackContext(for: itemId, maxStreamingBitrate: nil)
    }

    /// Construct a stream URL for a given item with an optional maximum streaming bitrate.
    ///
    /// When `maxStreamingBitrate` is provided, Jellyfin may choose a lower bitrate encode
    /// (or transcode) depending on server capabilities and the source file.
    func playbackContext(for itemId: String, maxStreamingBitrate: Int?) async throws -> PlaybackContext {
        let playbackInfo = try await fetchPlaybackInfo(itemId: itemId)

        // If the item is very likely to be Apple-compatible (container + codecs),
        // prefer a single-file Direct Play stream whenever we are not explicitly
        // asking for a bitrate cap. This materially reduces server load compared
        // to forcing HLS/transcoding.
        //
        // We are conservative on constrained/expensive networks.
        if maxStreamingBitrate == nil,
           let direct = preferredDirectPlayURLIfSuitable(itemId: itemId, playbackInfo: playbackInfo) {
            return PlaybackContext(
                url: direct,
                mediaSourceId: playbackInfo.mediaSources.first?.id,
                playSessionId: playbackInfo.playSessionId
            )
        }

        // If a transcodingUrl is provided use it directly, appending the api_key.
        if let source = playbackInfo.mediaSources.first,
           let transcoding = source.transcodingUrl {
            var url = serverURL.appendingPathComponent(transcoding)
            if let token = accessToken {
                if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    var items = components.queryItems ?? []
                    items.append(URLQueryItem(name: "api_key", value: token))
                    components.queryItems = items
                    if let newURL = components.url {
                        url = newURL
                    }
                }
            }
            return PlaybackContext(
                url: url,
                mediaSourceId: source.id,
                playSessionId: playbackInfo.playSessionId
            )
        }

        // Otherwise construct a stream URL using the Videos endpoint.
        let mediaSourceId = playbackInfo.mediaSources.first?.id
        let playSessionId = playbackInfo.playSessionId

        // Prefer HLS playlist URL (server will remux/transcode as needed).
        if let hlsURL = client.makeHLSURL(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            userId: currentUser?.id,
            maxStreamingBitrate: maxStreamingBitrate
        ) {
            return PlaybackContext(url: hlsURL, mediaSourceId: mediaSourceId, playSessionId: playSessionId)
        }

        // Fallback to direct stream URL.
        if let streamURL = client.makeStreamURL(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            userId: currentUser?.id
        ) {
            return PlaybackContext(url: streamURL, mediaSourceId: mediaSourceId, playSessionId: playSessionId)
        }

        throw JellyfinClient.NetworkError.invalidResponse
    }

    /// Returns a Direct Play URL when the file is Apple-compatible and the
    /// current network path is not obviously constrained.
    private func preferredDirectPlayURLIfSuitable(itemId: String, playbackInfo: JellyfinClient.PlaybackInfo) -> URL? {
        guard let source = playbackInfo.mediaSources.first else { return nil }

        // Basic codec/container compatibility.
        guard isAppleCompatible(mediaSource: source) else { return nil }

        // Network gate: avoid forcing a large direct stream on constrained/expensive
        // paths unless the bitrate is low.
        let network = NetworkMonitor.shared
        if network.isConstrained {
            return nil
        }

        if network.isExpensive {
            // On cellular: only direct play when the source bitrate is modest.
            // If bitrate metadata is missing, allow direct play (best effort).
            if let b = source.bitrate, b > 8_000_000 { // ~8 Mbps
                return nil
            }
        }

        return client.makeStreamURL(
            itemId: itemId,
            mediaSourceId: source.id,
            playSessionId: playbackInfo.playSessionId,
            userId: currentUser?.id
        )
    }

    /// Conservative Apple compatibility check for Direct Play.
    private func isAppleCompatible(mediaSource: JellyfinClient.PlaybackMediaSource) -> Bool {
        let container = mediaSource.container?.lowercased()
        let streams = mediaSource.mediaStreams ?? []
        let videoCodec = streams.first(where: { $0.type?.lowercased() == "video" })?.codec?.lowercased()
        let audioCodec = streams.first(where: { $0.type?.lowercased() == "audio" })?.codec?.lowercased()

        let appleContainers: Set<String> = ["mp4", "m4v", "mov"]
        let appleVideo: Set<String> = ["h264", "avc", "hevc", "h265"]
        let appleAudio: Set<String> = ["aac", "alac", "mp3", "ac3", "eac3"]

        // If metadata is missing, be permissive (best effort direct play).
        if let c = container, !appleContainers.contains(c) { return false }
        if let v = videoCodec, !appleVideo.contains(v) { return false }
        if let a = audioCodec, !appleAudio.contains(a) { return false }
        return true
    }

    /// Convenience helper that returns only the playable URL.
    func streamURL(for itemId: String) async throws -> URL {
        try await playbackContext(for: itemId).url
    }

    /// Returns a direct, file-oriented URL suitable for offline downloading.
    ///
    /// This intentionally prefers the Videos stream endpoint (static=true) rather than
    /// HLS playlists so the client receives a single file payload.
    
/// Determines whether an item likely requires a compatibility download (MP4/H.264/AAC)
/// for offline playback on Apple platforms.
///
/// The result is conservative: it only returns `requiresTranscode = true` when the app
/// *knows* a container/codec is not typically supported. If codec metadata is missing,
/// the function will return `requiresTranscode = false` so the app can attempt a direct
/// download first (and optionally fall back to transcoding if playback fails).
func offlineCompatibilityReport(for itemId: String) async throws -> OfflineCompatibilityReport {
    let playbackInfo = try await fetchPlaybackInfo(itemId: itemId)
    let mediaSource = playbackInfo.mediaSources.first

    let container = mediaSource?.container?.lowercased()

    let streams = mediaSource?.mediaStreams ?? []
    let videoCodec = streams.first(where: { $0.type?.lowercased() == "video" })?.codec?.lowercased()
    let audioCodec = streams.first(where: { $0.type?.lowercased() == "audio" })?.codec?.lowercased()

    let appleContainers: Set<String> = ["mp4", "m4v", "mov"]
    let appleVideo: Set<String> = ["h264", "avc", "hevc", "h265"]
    let appleAudio: Set<String> = ["aac", "alac", "mp3", "ac3", "eac3"]

    var requires = false
    if let c = container, !appleContainers.contains(c) { requires = true }
    if let v = videoCodec, !appleVideo.contains(v) { requires = true }
    if let a = audioCodec, !appleAudio.contains(a) { requires = true }

    return OfflineCompatibilityReport(
        container: container,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        requiresTranscode: requires
    )
}

func downloadURL(for itemId: String, forceCompatibility: Bool = false) async throws -> URL {
        let playbackInfo = try await fetchPlaybackInfo(itemId: itemId)
        let mediaSourceId = playbackInfo.mediaSources.first?.id
        let playSessionId = playbackInfo.playSessionId

        guard var url = client.makeStreamURL(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            userId: currentUser?.id
        ) else {
            throw JellyfinClient.NetworkError.invalidResponse
        }

        // Offline downloads must be device-decodable.
        // Streaming playback can transcode on the fly, but downloaded files must be
        // playable locally by AVPlayer. Use PlaybackInfo to decide when to force a
        // compatible transcode/remux.
        let source = playbackInfo.mediaSources.first
        let container = source?.container?.lowercased()
        let streams = source?.mediaStreams ?? []
        let videoCodec = streams.first(where: { ($0.type ?? "").lowercased() == "video" })?.codec?.lowercased()
        let audioCodec = streams.first(where: { ($0.type ?? "").lowercased() == "audio" })?.codec?.lowercased()

        // Conservative Apple-compatible profile.
        // - Container: mp4
        // - Video: h264 (AVC)
        // - Audio: aac
        let appleContainers: Set<String> = ["mp4", "m4v", "mov"]
        let appleVideo: Set<String> = ["h264", "avc", "hevc", "h265"]
        let appleAudio: Set<String> = ["aac", "alac", "mp3", "ac3", "eac3"]

        // Decide whether we must force a compatible offline download.
        //
        // Important: some Jellyfin servers (and some item types) do not return full
        // MediaStreams codec info. In those cases, *do not* pessimistically force a
        // compatibility transcode, because it can cause needless server transcoding
        // for content that is already Apple-playable.
        //
        // Instead:
        //  - force compatibility only when we *know* the container/codec is incompatible
        //  - otherwise attempt a direct download and rely on post-download validation
        //    (AVFoundation) to detect incompatibility and let the user retry as compatible.
        let requiresCompatibilityTranscode: Bool = {
            if let c = container, !appleContainers.contains(c) { return true }
            if let v = videoCodec, !appleVideo.contains(v) { return true }
            if let a = audioCodec, !appleAudio.contains(a) { return true }
            return false
        }()

        let shouldForceCompatibility = forceCompatibility || requiresCompatibilityTranscode
        if shouldForceCompatibility {
            // Rebuild the base URL using the explicit container endpoint so the server is allowed
            // to remux/transcode. NOTE: `static=true` means "original file, no encoding" and must
            // not be used for compatibility downloads.
            if let compatBase = client.makeStreamURLByContainer(
                itemId: itemId,
                container: "mp4",
                mediaSourceId: mediaSourceId,
                playSessionId: playSessionId,
                userId: currentUser?.id,
                isStatic: false
            ) {
                url = compatBase
            }
            // Append stream parameters that strongly encourage Jellyfin to remux/transcode
            // into a universally playable offline file.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []

            // Force MP4 container and an Apple-friendly codec set.
            items.append(URLQueryItem(name: "Container", value: "mp4"))
            items.append(URLQueryItem(name: "TranscodingContainer", value: "mp4"))
            items.append(URLQueryItem(name: "VideoCodec", value: "h264"))
            items.append(URLQueryItem(name: "AudioCodec", value: "aac"))
            // Avoid "copy" decisions that can preserve unsupported codecs.
            // For offline files we prefer a guaranteed-decodable transcode.
            items.append(URLQueryItem(name: "AllowVideoStreamCopy", value: "false"))
            items.append(URLQueryItem(name: "AllowAudioStreamCopy", value: "false"))
            items.append(URLQueryItem(name: "MaxAudioChannels", value: "2"))
            // Help servers that are picky about timestamp/copy behaviour.
            items.append(URLQueryItem(name: "CopyTimestamps", value: "true"))

            components?.queryItems = items
            if let coerced = components?.url {
                url = coerced
            }
        }

        return url
    }


    // MARK: - Playback Reporting

    func reportPlaybackStarted(context: PlaybackContext, itemId: String, positionTicks: Int, isPaused: Bool) async {
        do {
            try await client.reportPlaybackStarted(
                itemId: itemId,
                mediaSourceId: context.mediaSourceId,
                playSessionId: context.playSessionId,
                positionTicks: positionTicks,
                isPaused: isPaused
            )
        } catch {
            // Non-fatal; do not disrupt playback.
        }
    }

    func reportPlaybackProgress(context: PlaybackContext, itemId: String, positionTicks: Int, isPaused: Bool) async {
        do {
            try await client.reportPlaybackProgress(
                itemId: itemId,
                mediaSourceId: context.mediaSourceId,
                playSessionId: context.playSessionId,
                positionTicks: positionTicks,
                isPaused: isPaused
            )
        } catch {
            // Non-fatal; do not disrupt playback.
        }
    }

    func reportPlaybackStopped(context: PlaybackContext, itemId: String, positionTicks: Int, playedToCompletion: Bool, failed: Bool = false) async {
        do {
            try await client.reportPlaybackStopped(
                itemId: itemId,
                mediaSourceId: context.mediaSourceId,
                playSessionId: context.playSessionId,
                positionTicks: positionTicks,
                playedToCompletion: playedToCompletion,
                failed: failed
            )
        } catch {
            // Non-fatal; do not disrupt playback.
        }
    }


    /// If you ever want to force a transcoded HLS URL explicitly, call this helper.
    /// Currently this is the same as the preferred URL in `streamURL(for:)`.
    func transcodedHLSURL(for itemId: String) async throws -> URL {
        let playbackInfo = try await fetchPlaybackInfo(itemId: itemId)
        let mediaSourceId = playbackInfo.mediaSources.first?.id
        let playSessionId = playbackInfo.playSessionId
        if let hlsURL = client.makeHLSURL(itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId, userId: currentUser?.id) {
            return hlsURL
        }
        throw JellyfinClient.NetworkError.invalidResponse
    }

    /// Construct the URL for the current user's profile image.  Returns nil if
    /// there is no logged in user.
    func userProfileImageURL(maxWidth: Int? = nil) -> URL? {
        guard let user = currentUser else { return nil }
        return client.userImageURL(for: user, maxWidth: maxWidth)
    }

    /// Construct the URL for a library's image.  Returns nil if the image tag is missing.
    func libraryImageURL(for view: JellyfinClient.LibraryView, maxWidth: Int? = nil) -> URL? {
        return client.libraryImageURL(for: view, maxWidth: maxWidth)
    }

    /// Construct the URL for a media item's image.  Returns nil if the item has no image.
    func itemImageURL(for item: JellyfinClient.LibraryItem, maxWidth: Int? = nil) -> URL? {
        return client.itemImageURL(for: item, maxWidth: maxWidth)
    }


    func itemImageURL(for item: JellyfinClient.LibraryItem, kind: String, maxWidth: Int? = nil) -> URL? {
        return client.itemImageURL(for: item, kind: kind, maxWidth: maxWidth)
    }



/// Construct the URL for a person's primary image.
func personImageURL(for person: JellyfinClient.Person, maxWidth: Int? = nil) -> URL? {
    return client.personImageURL(for: person, maxWidth: maxWidth)
}

    /// Construct the URL for a detailed media item's image.  Returns nil if there is no image.
    func itemImageURL(for detail: JellyfinClient.ItemDetail, maxWidth: Int? = nil) -> URL? {
        return client.itemImageURL(for: detail, maxWidth: maxWidth)
    }


    func itemImageURL(for detail: JellyfinClient.ItemDetail, kind: String, maxWidth: Int? = nil) -> URL? {
        return client.itemImageURL(for: detail, kind: kind, maxWidth: maxWidth)
    }

    /// Construct the URL for an item image when you only have the item's ID.
    /// Useful for fallbacks such as Series/Season artwork when an Episode lacks images.
    func itemImageURL(itemId: String, kind: String = "Primary", maxWidth: Int? = nil) -> URL? {
        return client.itemImageURL(itemId: itemId, kind: kind, tag: nil, maxWidth: maxWidth)
    }

    /// Fetch detailed information for a specific item.  Must be called after the user has
    /// logged in.  Returns an `ItemDetail` on success or throws on failure.
    func fetchItemDetails(itemId: String) async throws -> JellyfinClient.ItemDetail {
        guard let userId = currentUser?.id else {
            throw JellyfinClient.NetworkError.invalidResponse
        }
        return try await withCheckedThrowingContinuation { continuation in
            client.fetchItemDetails(for: itemId, userId: userId) { result in
                switch result {
                case .success(let detail):
                    continuation.resume(returning: detail)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }


    // MARK: - Favorites

    /// Toggle an item's favorite status on the Jellyfin server so the change is reflected
    /// across all clients (Jellyfin Web, mobile apps, etc.).
    func setFavorite(itemId: String, isFavorite: Bool) async throws {
        guard let userId = currentUser?.id else {
            throw JellyfinClient.NetworkError.invalidResponse
        }
        try await withCheckedThrowingContinuation { continuation in
            client.setFavorite(itemId: itemId, userId: userId, isFavorite: isFavorite) { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

// MARK: - TV helpers (Next Up / Resume)

/// Fetch Jellyfin "Next Up" episode for a given series.
func fetchNextUpEpisode(seriesId: String) async throws -> JellyfinClient.LibraryItem? {
    guard let userId = currentUser?.id else { return nil }
    return try await withCheckedThrowingContinuation { continuation in
        client.fetchNextUpEpisode(seriesId: seriesId, userId: userId) { result in
            switch result {
            case .success(let episode):
                continuation.resume(returning: episode)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Fetch Jellyfin media segments for an item (best-effort). Used for features like
/// Skip Intro. Returns an empty array if none are available.
func fetchMediaSegments(itemId: String) async throws -> [JellyfinClient.MediaSegment] {
    return try await withCheckedThrowingContinuation { continuation in
        client.fetchMediaSegments(itemId: itemId) { result in
            switch result {
            case .success(let segments):
                continuation.resume(returning: segments)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Fetch cast/crew for a given item (movies, series, episodes).
func fetchPeople(for itemId: String) async throws -> [JellyfinClient.Person] {
    guard let userId = currentUser?.id else { return [] }
    return try await withCheckedThrowingContinuation { continuation in
        client.fetchPeople(for: itemId, userId: userId) { result in
            switch result {
            case .success(let people):
                continuation.resume(returning: people)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Determine the best "primary play" target for a series. Tries NextUp first,
/// then falls back to S1E1.
func resolvePrimaryEpisodeForSeries(seriesId: String) async throws -> JellyfinClient.LibraryItem? {
    if let nextUp = try await fetchNextUpEpisode(seriesId: seriesId) {
        return nextUp
    }
    // Fallback: load first season, then first episode.
    let seasons = try await fetchItems(
        for: JellyfinClient.LibraryItem(
            id: seriesId,
            name: "",
            type: "Series",
            mediaType: nil,
            runtimeTicks: nil,
            primaryImageTag: nil,
            overview: nil,
            productionYear: nil,
            premiereDate: nil,
            indexNumber: nil,
            parentIndexNumber: nil,
            seriesId: nil,
            seasonId: nil,
            seriesName: nil,
            userData: nil
        ),
        includeItemTypes: ["Season"],
        sortBy: ["ParentIndexNumber", "IndexNumber", "SortName"],
        sortOrder: "Ascending"
    )
    if let firstSeason = seasons.first {
        let episodes = try await fetchItems(
            for: firstSeason,
            includeItemTypes: ["Episode"],
            sortBy: ["ParentIndexNumber", "IndexNumber", "SortName"],
            sortOrder: "Ascending"
        )
        return episodes.first
    }
    return nil
}



    /// Compute a human-readable membership duration string based on the join date.
    /// If the join date is nil, the user is assumed to be a new member.  The
    /// duration is expressed in years and months (e.g. "Member for 1y 2m").
    func membershipDurationString() -> String {
        guard let joinDate = joinDate else {
            return "Member since now"
        }
        let components = Calendar.current.dateComponents([.year, .month], from: joinDate, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        var parts: [String] = []
        if years > 0 {
            parts.append("\(years)y")
        }
        if months > 0 {
            parts.append("\(months)m")
        }
        if parts.isEmpty {
            return "Member for <1m"
        } else {
            return "Member for " + parts.joined(separator: " ")
        }
    }

    // MARK: - Server health

    /// Ping the currently configured Jellyfin server.  Returns true if the
    /// `/health` endpoint responds with HTTP 200 and false otherwise.  This
    /// method uses a temporary client so it does not depend on the login
    /// state.  You can call this from the login or server setup screens to
    /// display an online/offline indicator.
    func pingServer() async -> Bool {
        // Use the current serverURL to build a temp client
        let tempClient = JellyfinClient(baseURL: serverURL)
        return await withCheckedContinuation { continuation in
            tempClient.checkHealth { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
