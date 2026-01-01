import Foundation
import SwiftUI

/// Shared application state managing the connection to the Jellyfin server,
/// authentication token and current user.  Views can observe this object to
/// automatically react to changes (e.g. showing login when the user logs out).
@MainActor
final class SessionStore: ObservableObject {
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

    /// Construct a stream URL for a given item.  This first fetches playback info to obtain
    /// the media source ID and play session ID, then uses the client to build the final URL.
    /// Throws if the server responds with an error or if a valid stream URL cannot be built.
    func streamURL(for itemId: String) async throws -> URL {
        let playbackInfo = try await fetchPlaybackInfo(itemId: itemId)
        // If a transcodingUrl is provided use it directly, appending the api_key
        if let source = playbackInfo.mediaSources.first,
           let transcoding = source.transcodingUrl {
            // Build absolute URL from the relative transcodingUrl
            var url = serverURL.appendingPathComponent(transcoding)
            // Append api_key if token is available and not already present
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
            return url
        }
        // Otherwise construct a stream URL using the Videos endpoint.
        // We preferentially use HLS (m3u8) with an Apple-compatible profile.
        // This allows Jellyfin to remux/transcode when a device cannot direct-play
        // a given container/codec (e.g., MKV, DTS, etc.).
        let mediaSourceId = playbackInfo.mediaSources.first?.id
        let playSessionId = playbackInfo.playSessionId

        // First attempt HLS playlist URL (server will remux/transcode as needed).
        if let hlsURL = client.makeHLSURL(itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId, userId: currentUser?.id) {
            return hlsURL
        }

        // Fallback to direct stream URL.
        if let streamURL = client.makeStreamURL(itemId: itemId, mediaSourceId: mediaSourceId, playSessionId: playSessionId, userId: currentUser?.id) {
            return streamURL
        }
        throw JellyfinClient.NetworkError.invalidResponse
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
