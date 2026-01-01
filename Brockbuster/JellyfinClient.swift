import Foundation

/// A lightweight API client for interacting with a Jellyfin server.  This class encapsulates
/// the network details for authenticating a user and fetching data.  All requests are
/// performed with sensible timeouts and headers appropriate for a Jellyfin client.  The
/// authentication method conforms to the API specification described by the Jellyfin docs,
/// where the username is supplied as `Username` and the plaintext password is sent in
/// the `Pw` field【261741302448544†L73-L88】.
final class JellyfinClient {
    /// The base URL of the Jellyfin server.  Must include the scheme (e.g. https://).
    private let baseURL: URL
    /// Optional access token for authenticated requests.  After a successful login this
    /// property will be populated and automatically attached to subsequent requests via
    /// the `X-Emby-Authorization` header.  The token is kept private but can be read
    /// through the public `token` computed property.
    private var accessToken: String?
    /// A device identifier used to uniquely identify this installation.  Persist this
    /// between launches to avoid generating a new ID on every run.  For simplicity here
    /// we just use a random UUID and cache it via UserDefaults.
    private static let deviceIdKey = "JellyfinDeviceId"
    private let deviceId: String
    /// The version of the app.  You can bump this when releasing new versions.
    private let appVersion = "0.1.0"

    /// Create a new client for the given server URL.
    init(baseURL: URL) {
        self.baseURL = baseURL
        // Load or generate a unique device identifier
        if let existing = UserDefaults.standard.string(forKey: JellyfinClient.deviceIdKey) {
            deviceId = existing
        } else {
            let newId = UUID().uuidString
            deviceId = newId
            UserDefaults.standard.set(newId, forKey: JellyfinClient.deviceIdKey)
        }
    }

    // MARK: - Public properties

    /// Expose the currently stored access token for other components (e.g. SessionStore).
    /// The token is read-only to prevent external mutation.
    var token: String? {
        accessToken
    }

    /// Allow higher-level session management to restore a previously stored
    /// access token (e.g., from Keychain) without re-authenticating.
    func setToken(_ token: String?) {
        self.accessToken = token
    }

    // MARK: - API models

    /// Encodes the payload for the login request.  Note that the password field for
    /// Jellyfin is called `Pw` in the API and must be sent in plaintext【261741302448544†L73-L88】.
    private struct AuthenticateRequest: Encodable {
        let Username: String
        let Pw: String
    }

    /// Decodes the response from the login endpoint.  We only decode the fields we
    /// currently care about (access token and user ID).  Additional fields can be added
    /// as needed.
    private struct AuthenticateResponse: Decodable {
        let User: JellyfinUser
        let AccessToken: String
    }

    // MARK: - Public API

    /// Perform a login with the given username and password.  This method sends a POST
    /// request to `/Users/AuthenticateByName` with JSON body containing `Username` and
    /// `Pw` fields.  It also sets appropriate headers such as `X-Emby-Authorization` and
    /// `User-Agent` to mirror the behaviour of official Jellyfin clients【32†L50-L55】.
    /// - Parameters:
    ///   - username: Jellyfin account username
    ///   - password: Jellyfin account password
    ///   - completion: Completion handler invoked on the main queue with either the
    ///                 authenticated user or an error.
    func authenticate(username: String, password: String, completion: @escaping (Result<JellyfinUser, Error>) -> Void) {
        let endpoint = baseURL.appendingPathComponent("Users/AuthenticateByName")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        // Accept and send JSON
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Provide a descriptive user-agent that won't trip Cloudflare's bot detection.
        let userAgent = "Brockbuster/\(appVersion) (SwiftUI; Darwin)"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Compose the X-Emby-Authorization header according to Jellyfin API docs【32†L50-L55】.
        let authHeader = "MediaBrowser Client=\"Brockbuster\", Device=\"iOS\", DeviceId=\"\(deviceId)\", Version=\(appVersion)"
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        // Build the JSON body
        let payload = AuthenticateRequest(Username: username, Pw: password)
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        // Perform the network call
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            // Dispatch result to main queue for UI updates
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let serverError = NetworkError.httpStatus(code: http.statusCode)
                DispatchQueue.main.async { completion(.failure(serverError)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(AuthenticateResponse.self, from: data)
                // Save the access token so subsequent requests can include it
                self?.accessToken = decoded.AccessToken
                DispatchQueue.main.async { completion(.success(decoded.User)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    /// Check whether the server is available by calling the `/health` endpoint.  This
    /// endpoint returns a simple 200 OK status when the server is reachable【515309828831105†L67-L69】.
    func checkHealth(completion: @escaping (Result<Void, Error>) -> Void) {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard http.statusCode == 200 else {
                DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
                return
            }
            DispatchQueue.main.async { completion(.success(())) }
        }
        task.resume()
    }

    // MARK: - Network error types

    enum NetworkError: LocalizedError {
        case invalidResponse
        case httpStatus(code: Int)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid server response."
            case .httpStatus(let code):
                return "Server responded with status \(code)."
            case .emptyResponse:
                return "The server returned an empty response."
            }
        }
    }

    // MARK: - Helper types

    /// Represents a library view returned by the `/Users/{userId}/Views` endpoint.  Each view
    /// corresponds to a top-level library such as Movies, TV Shows or Music.  The
    /// `primaryImageTag` can be used to construct a URL for the view's image.
    struct LibraryView: Identifiable, Codable {
        let id: String
        let name: String
        let primaryImageTag: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case primaryImageTag = "PrimaryImageTag"
        }
    }

    // MARK: - Image URL helper for library views

    /// Construct a URL for a library view's primary image.  The image is requested from
    /// `/Items/{id}/Images/Primary` similar to item images.  Returns nil if there is no
    /// primary image tag.  You may specify a maximum width to request a scaled image.
    func libraryImageURL(for view: LibraryView, maxWidth: Int? = nil) -> URL? {
        let base = baseURL.appendingPathComponent("Items/\(view.id)/Images/Primary")
        guard let tag = view.primaryImageTag else { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [URLQueryItem(name: "tag", value: tag)]
        if let width = maxWidth {
            items.append(URLQueryItem(name: "maxWidth", value: String(width)))
        }
        components?.queryItems = items
        return components?.url ?? base
    }

    // MARK: - Image URL helpers

    /// Construct a URL for the user's profile image.  If the user has a primary image tag
    /// the tag is appended as a query parameter.  You can optionally specify a
    /// maximum width to request a resized image.
    func userImageURL(for user: JellyfinUser, maxWidth: Int? = nil) -> URL {
        var url = baseURL.appendingPathComponent("Users/\(user.id)/Images/Primary")
        if let tag = user.primaryImageTag, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items: [URLQueryItem] = [URLQueryItem(name: "tag", value: tag)]
            if let width = maxWidth {
                // Jellyfin supports maxWidth or width parameter; we use maxWidth for better quality
                items.append(URLQueryItem(name: "maxWidth", value: String(width)))
            }
            components.queryItems = items
            return components.url ?? url
        }
        // If there is no image tag just return the base URL
        return url
    }

    // MARK: - Data retrieval

    /// Fetch the library views (top-level libraries) for a user.  Requires that the
    /// client has a valid access token from a prior authentication.  The request
    /// attaches the token to the `X-Emby-Authorization` header.  See the Jellyfin
    /// API overview for details about the `/Users/{userId}/Views` endpoint【261741302448544†L96-L102】.
    func fetchViews(for userId: String, completion: @escaping (Result<[LibraryView], Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("Users/\(userId)/Views"))
        request.httpMethod = "GET"
        // Increase the timeout to account for slower servers or large libraries
        request.timeoutInterval = 30
        // Accept JSON
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Add authorization header with token
        request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
        // Set user-agent
        let userAgent = "Brockbuster/\(appVersion) (SwiftUI; Darwin)"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
                return
            }
            do {
                // Response JSON has structure { "Items": [ ... ] }
                let wrapper = try JSONDecoder().decode(ViewsResponse.self, from: data)
                DispatchQueue.main.async { completion(.success(wrapper.items)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    /// Fetch the items within a parent item or library. This method supports pagination,
    /// recursion and filtering by item type.
    ///
    /// Jellyfin's `/Users/{userId}/Items` endpoint defaults to a server-defined limit on
    /// the number of items returned. To retrieve all items, call this method repeatedly
    /// with increasing `startIndex` values until fewer than `limit` results are returned.
    func fetchItems(
        for parentId: String,
        userId: String,
        startIndex: Int = 0,
        limit: Int? = nil,
        recursive: Bool = false,
        includeItemTypes: [String]? = nil,
        sortBy: [String]? = nil,
        sortOrder: String? = nil,
        completion: @escaping (Result<[LibraryItem], Error>) -> Void
    ) {
        var components = URLComponents(url: baseURL.appendingPathComponent("Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "ParentId", value: parentId),
            URLQueryItem(name: "Recursive", value: recursive ? "true" : "false"),
            // Request richer metadata so we can build detailed pages without extra roundtrips.
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,CommunityRating,ProductionYear,RunTimeTicks,ParentId,ImageTags,BackdropImageTags,ParentIndexNumber,IndexNumber,SortName,PremiereDate,UserData,SeriesId,SeasonId,SeriesName"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
            URLQueryItem(name: "ImageTypeLimit", value: "1")
        ]
        if let includeItemTypes, !includeItemTypes.isEmpty {
            query.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes.joined(separator: ",")))
        }
        if let sortBy, !sortBy.isEmpty {
            query.append(URLQueryItem(name: "SortBy", value: sortBy.joined(separator: ",")))
        }
        if let sortOrder {
            query.append(URLQueryItem(name: "SortOrder", value: sortOrder))
        }
        if startIndex > 0 {
            query.append(URLQueryItem(name: "StartIndex", value: String(startIndex)))
        }
        if let limit = limit {
            query.append(URLQueryItem(name: "Limit", value: String(limit)))
        }
        components.queryItems = query
        guard let url = components.url else {
            DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("Brockbuster/\(appVersion) (SwiftUI; Darwin)", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
                return
            }
            do {
                let wrapper = try JSONDecoder().decode(ItemsResponse.self, from: data)
                DispatchQueue.main.async { completion(.success(wrapper.items)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    /// Fetch the current user's resume/continue-watching items.
    /// This uses Jellyfin's `/Users/{userId}/Items/Resume` endpoint.
    func fetchResumeItems(
        userId: String,
        limit: Int = 20,
        completion: @escaping (Result<[LibraryItem], Error>) -> Void
    ) {
        var components = URLComponents(url: baseURL.appendingPathComponent("Users/\(userId)/Items/Resume"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,CommunityRating,ProductionYear,RunTimeTicks,ParentId,ImageTags,BackdropImageTags,ParentIndexNumber,IndexNumber,SortName,PremiereDate,UserData,SeriesId,SeasonId,SeriesName"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
            URLQueryItem(name: "ImageTypeLimit", value: "1")
        ]
        guard let url = components.url else {
            DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("Brockbuster/\(appVersion) (SwiftUI; Darwin)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
                return
            }
            do {
                let wrapper = try JSONDecoder().decode(ItemsResponse.self, from: data)
                DispatchQueue.main.async { completion(.success(wrapper.items)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    /// Fetch recently played items (a simple "watch history" list).
    ///
    /// Jellyfin supports sorting by `DatePlayed` and filtering to only played
    /// items.  This powers the "Watch History" section in the app.
    func fetchWatchHistory(
        userId: String,
        limit: Int = 50,
        completion: @escaping (Result<[LibraryItem], Error>) -> Void
    ) {
        var components = URLComponents(url: baseURL.appendingPathComponent("Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "SortBy", value: "DatePlayed"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Filters", value: "IsPlayed"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,CommunityRating,ProductionYear,RunTimeTicks,ParentId,ImageTags,BackdropImageTags,ParentIndexNumber,IndexNumber,SortName,PremiereDate,UserData,SeriesId,SeasonId,SeriesName"),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
            URLQueryItem(name: "ImageTypeLimit", value: "1")
        ]
        guard let url = components.url else {
            DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("Brockbuster/\(appVersion) (SwiftUI; Darwin)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
                return
            }
            do {
                let wrapper = try JSONDecoder().decode(ItemsResponse.self, from: data)
                DispatchQueue.main.async { completion(.success(wrapper.items)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    // MARK: - Response structs

    private struct ViewsResponse: Decodable {
        let items: [LibraryView]

        enum CodingKeys: String, CodingKey {
            case items = "Items"
        }
    }


/// Represents per-user playback data attached to items when requested via the `Fields=UserData` parameter.
struct UserData: Decodable {
    let playbackPositionTicks: Int?
    let played: Bool?
    let lastPlayedDate: String?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case played = "Played"
        case lastPlayedDate = "LastPlayedDate"
    }
}

    /// Represents a media item inside a library.  Only includes a subset of fields that are
    /// useful for browsing.  You can extend this struct with additional properties as
    /// needed.
    struct LibraryItem: Identifiable, Decodable {
        let id: String
        let name: String
        /// Jellyfin "Type" (e.g. Movie, Series, Season, Episode, BoxSet).
        let type: String?
        /// Jellyfin "MediaType" (commonly Video / Audio). Some endpoints omit this.
        let mediaType: String?
        let runtimeTicks: Int?
        let primaryImageTag: String?

        // Optional rich fields (present depending on endpoint / item type)
        let overview: String?
        let productionYear: Int?
        let indexNumber: Int?
        let parentIndexNumber: Int?

        /// Additional linkage fields (present depending on the endpoint / fields requested)
        let seriesId: String?
        let seasonId: String?
        let seriesName: String?

        /// Per-user playback state (when requested via Fields=UserData)
        let userData: UserData?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case type = "Type"
            case mediaType = "MediaType"
            case runtimeTicks = "RunTimeTicks"
            case primaryImageTag = "PrimaryImageTag"
            case overview = "Overview"
            case productionYear = "ProductionYear"
            case indexNumber = "IndexNumber"
            case parentIndexNumber = "ParentIndexNumber"
            case seriesId = "SeriesId"
            case seasonId = "SeasonId"
            case seriesName = "SeriesName"
            case userData = "UserData"
        }
    }

    /// Represents detailed information about a media item.  This struct includes
    /// optional fields commonly used for display such as overview, taglines,
    /// production year and runtime.  Not all fields are guaranteed to be
    /// present for every item.  Extend this model as needed for additional
    /// metadata.
    struct ItemDetail: Identifiable, Decodable {
        let id: String
        let name: String
        let overview: String?
        let mediaType: String?
        let runTimeTicks: Int?
        let productionYear: Int?
        let communityRating: Double?
        let primaryImageTag: String?
        let genres: [String]?
        let taglines: [String]?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case overview = "Overview"
            case mediaType = "MediaType"
            case runTimeTicks = "RunTimeTicks"
            case productionYear = "ProductionYear"
            case communityRating = "CommunityRating"
            case primaryImageTag = "PrimaryImageTag"
            case genres = "Genres"
            case taglines = "Taglines"
        }
    }

    private struct ItemsResponse: Decodable {
        let items: [LibraryItem]
        enum CodingKeys: String, CodingKey {
            case items = "Items"
        }
    }

    // MARK: - Image URL helpers for items

    /// Construct a URL for an item's primary image.  If the item has a primary image tag
    /// the tag is appended as a query parameter.  Optionally specify a maximum width to
    /// request a resized image.  Returns nil if the item has no primary image.
    func itemImageURL(for item: LibraryItem, maxWidth: Int? = nil) -> URL? {
        // If there is no image tag, Jellyfin may still return an image but we'll avoid unnecessary requests
        // by checking for the tag.  Remove this guard if you want a default image for all items.
        let base = baseURL.appendingPathComponent("Items/\(item.id)/Images/Primary")
        if let tag = item.primaryImageTag {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            var items: [URLQueryItem] = [URLQueryItem(name: "tag", value: tag)]
            if let width = maxWidth {
                items.append(URLQueryItem(name: "maxWidth", value: String(width)))
            }
            components?.queryItems = items
            return components?.url ?? base
        } else {
            // If there is no tag but we still want the image, simply return the base URL
            return base
        }
    }

    /// Construct a URL for the primary image of a detailed item.  Accepts an
    /// `ItemDetail` rather than a `LibraryItem` and uses the item's
    /// `primaryImageTag` if available to build a tagged URL.  Returns nil if
    /// there is no image for the item.
    func itemImageURL(for detail: ItemDetail, maxWidth: Int? = nil) -> URL? {
        let base = baseURL.appendingPathComponent("Items/\(detail.id)/Images/Primary")
        if let tag = detail.primaryImageTag {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            var items: [URLQueryItem] = [URLQueryItem(name: "tag", value: tag)]
            if let width = maxWidth {
                items.append(URLQueryItem(name: "maxWidth", value: String(width)))
            }
            components?.queryItems = items
            return components?.url ?? base
        } else {
            return base
        }
    }


/// Construct a URL for a person's primary image.
func personImageURL(for person: Person, maxWidth: Int? = nil) -> URL? {
    let base = baseURL.appendingPathComponent("Items/\(person.id)/Images/Primary")
    if let tag = person.primaryImageTag {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [URLQueryItem(name: "tag", value: tag)]
        if let width = maxWidth {
            items.append(URLQueryItem(name: "maxWidth", value: String(width)))
        }
        components?.queryItems = items
        return components?.url ?? base
    }
    return base
}


    // MARK: - Item detail retrieval

    /// Fetch detailed information for a specific media item.  The item ID is
    /// required.  Pass the user ID to include user-specific data in the
    /// response (e.g. play state).  The request attaches the access token and
    /// user-agent similar to other API calls.  Only a subset of fields is
    /// requested to improve performance.  Adjust the `fields` parameter to
    /// include additional metadata as needed.
    func fetchItemDetails(for itemId: String, userId: String?, completion: @escaping (Result<ItemDetail, Error>) -> Void) {
        // Build the URL with optional user ID and requested fields
        var components = URLComponents(url: baseURL.appendingPathComponent("Items/\(itemId)"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let uid = userId {
            queryItems.append(URLQueryItem(name: "UserId", value: uid))
        }
        // Request only relevant fields.  See Jellyfin ItemFields enum for more.
        queryItems.append(URLQueryItem(name: "Fields", value: "Overview,Genres,Taglines,ProductionYear,RunTimeTicks,CommunityRating,PrimaryImageTag,MediaType"))
        components.queryItems = queryItems
        guard let url = components.url else {
            DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("Brockbuster/\(appVersion) (SwiftUI; Darwin)", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
                return
            }
            do {
                let detail = try JSONDecoder().decode(ItemDetail.self, from: data)
                DispatchQueue.main.async { completion(.success(detail)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }


// MARK: - People (cast/crew)

/// Represents a person (actor/crew) returned by Jellyfin's `/Items/{id}/People` endpoint.
struct Person: Identifiable, Decodable {
    let id: String
    let name: String
    let role: String?
    let type: String?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

/// Fetch cast/crew for an item via `/Items/{itemId}/People`.
func fetchPeople(for itemId: String, userId: String?, completion: @escaping (Result<[Person], Error>) -> Void) {
    var components = URLComponents(url: baseURL.appendingPathComponent("Items/\(itemId)/People"), resolvingAgainstBaseURL: false)!
    if let userId {
        components.queryItems = [URLQueryItem(name: "UserId", value: userId)]
    }
    guard let url = components.url else {
        DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
    request.setValue("Brockbuster/\(appVersion) (SwiftUI; Darwin)", forHTTPHeaderField: "User-Agent")

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        guard let http = response as? HTTPURLResponse else {
            DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
            return
        }
        guard (200...299).contains(http.statusCode) else {
            DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
            return
        }
        guard let data else {
            DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
            return
        }
        do {
            let people = try JSONDecoder().decode([Person].self, from: data)
            DispatchQueue.main.async { completion(.success(people)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
    task.resume()
}

// MARK: - Next Up (TV)

/// Fetch the next-up episode for a series via `/Shows/NextUp`.
/// This endpoint returns episodes the user should watch next (or resume).
func fetchNextUpEpisode(seriesId: String, userId: String, completion: @escaping (Result<LibraryItem?, Error>) -> Void) {
    var components = URLComponents(url: baseURL.appendingPathComponent("Shows/NextUp"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "UserId", value: userId),
        URLQueryItem(name: "SeriesId", value: seriesId),
        URLQueryItem(name: "Limit", value: "1"),
        URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,CommunityRating,ProductionYear,RunTimeTicks,ParentId,ImageTags,BackdropImageTags,ParentIndexNumber,IndexNumber,SortName,PremiereDate,UserData,SeriesId,SeasonId,SeriesName"),
        URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Thumb"),
        URLQueryItem(name: "ImageTypeLimit", value: "1")
    ]
    guard let url = components.url else {
        DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
    request.setValue("Brockbuster/\(appVersion) (SwiftUI; Darwin)", forHTTPHeaderField: "User-Agent")

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        guard let http = response as? HTTPURLResponse else {
            DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
            return
        }
        guard (200...299).contains(http.statusCode) else {
            DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
            return
        }
        guard let data else {
            DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
            return
        }
        do {
            let wrapper = try JSONDecoder().decode(ItemsResponse.self, from: data)
            DispatchQueue.main.async { completion(.success(wrapper.items.first)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
    task.resume()
}


    // MARK: - Authorization header helper

    /// Build the value for the `X-Emby-Authorization` header.  If a token is provided
    /// it will be included, otherwise the token component is omitted.  The values
    /// correspond to the Jellyfin API spec【32†L50-L55】.
    private func buildAuthorizationHeader(withToken token: String?) -> String {
        var segments = [String]()
        segments.append("Client=\"Brockbuster\"")
        segments.append("Device=\"iOS\"")
        segments.append("DeviceId=\"\(deviceId)\"")
        segments.append("Version=\(appVersion)")
        if let token = token {
            segments.append("Token=\"\(token)\"")
        }
        return "MediaBrowser " + segments.joined(separator: ", ")
    }

    // MARK: - Playback Info retrieval

    /// Represents the playback info response from Jellyfin, containing media sources
    /// and a play session id.  Only the fields relevant for building a stream
    /// URL are included here.
    struct PlaybackInfo: Decodable {
        let mediaSources: [PlaybackMediaSource]
        let playSessionId: String?

        enum CodingKeys: String, CodingKey {
            case mediaSources = "MediaSources"
            case playSessionId = "PlaySessionId"
        }
    }

    /// Represents a media source within a playback info response.  Only the fields
    /// needed for constructing a stream URL are decoded here.
    struct PlaybackMediaSource: Decodable {
        let id: String?
        let transcodingUrl: String?
        let path: String?
        let container: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case transcodingUrl = "TranscodingUrl"
            case path = "Path"
            case container = "Container"
        }
    }

    /// Fetch playback info for an item.  This calls `/Items/{itemId}/PlaybackInfo`
    /// with an optional userId.  The result includes media sources and a play session id.
    ///
    /// - Parameters:
    ///   - itemId: The identifier of the media item to play.
    ///   - userId: Optional user identifier.  If supplied the server may include
    ///             user-specific playback settings.
    ///   - completion: Completion handler called on the main queue with the
    ///                 playback info or an error.
    func fetchPlaybackInfo(for itemId: String, userId: String?, completion: @escaping (Result<PlaybackInfo, Error>) -> Void) {
        // Build URL with userId as query parameter if provided.
        var url = baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo")
        if let userId = userId, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "UserId", value: userId)]
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(buildAuthorizationHeader(withToken: accessToken), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("Brockbuster/\(appVersion) (SwiftUI; Darwin)", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(NetworkError.invalidResponse)) }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { completion(.failure(NetworkError.httpStatus(code: http.statusCode))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NetworkError.emptyResponse)) }
                return
            }
            do {
                let info = try JSONDecoder().decode(PlaybackInfo.self, from: data)
                DispatchQueue.main.async { completion(.success(info)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    /// Build a stream URL using the item ID, media source ID and play session ID.
    /// The resulting URL points at `/Videos/{itemId}/stream` and includes query parameters
    /// such as static=true, mediaSourceId, playSessionId, userId, deviceId and api_key.
    /// - Parameters:
    ///   - itemId: The item identifier
    ///   - mediaSourceId: The media source identifier (optional)
    ///   - playSessionId: The playback session id (optional)
    ///   - userId: The user identifier (optional)
    /// - Returns: The constructed URL for streaming
    func makeStreamURL(itemId: String, mediaSourceId: String?, playSessionId: String?, userId: String?) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemId)/stream"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        // Static streaming to avoid segmented m3u8 if possible
        query.append(URLQueryItem(name: "static", value: "true"))
        if let mediaSourceId = mediaSourceId {
            query.append(URLQueryItem(name: "mediaSourceId", value: mediaSourceId))
        }
        if let playSessionId = playSessionId {
            query.append(URLQueryItem(name: "playSessionId", value: playSessionId))
        }
        if let userId = userId {
            query.append(URLQueryItem(name: "UserId", value: userId))
        }
        // DeviceId is used by Jellyfin to stop background transcoding when the device disconnects
        query.append(URLQueryItem(name: "DeviceId", value: deviceId))
        // Attach the access token as api_key for authentication on direct file requests
        if let token = accessToken {
            query.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = query
        return components.url
    }

    /// Build an HLS playlist URL for streaming via m3u8.  Jellyfin will serve
    /// segmented media at `/Videos/{itemId}/main.m3u8` or `/Videos/{itemId}/master.m3u8`.  We default
    /// to `main.m3u8` because this is used by the web client and returns a single
    /// bit-rate playlist.  The query parameters include the mediaSourceId,
    /// playSessionId, userId, deviceId and api_key.  This may improve
    /// compatibility if the direct stream URL fails to play.
    /// - Parameters:
    ///   - itemId: The item identifier
    ///   - mediaSourceId: The media source identifier (optional)
    ///   - playSessionId: The playback session id (optional)
    ///   - userId: The user identifier (optional)
    /// - Returns: A URL pointing to the m3u8 playlist
    func makeHLSURL(itemId: String, mediaSourceId: String?, playSessionId: String?, userId: String?) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemId)/main.m3u8"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []

        // Prefer a universally compatible Apple playback profile.
        // This encourages the server to remux/transcode into HLS
        // with H.264 video + AAC audio in a TS container when needed.
        query.append(URLQueryItem(name: "Container", value: "ts"))
        query.append(URLQueryItem(name: "VideoCodec", value: "h264"))
        query.append(URLQueryItem(name: "AudioCodec", value: "aac"))
        if let mediaSourceId = mediaSourceId {
            query.append(URLQueryItem(name: "mediaSourceId", value: mediaSourceId))
        }
        if let playSessionId = playSessionId {
            query.append(URLQueryItem(name: "playSessionId", value: playSessionId))
        }
        if let userId = userId {
            query.append(URLQueryItem(name: "UserId", value: userId))
        }
        query.append(URLQueryItem(name: "DeviceId", value: deviceId))
        if let token = accessToken {
            query.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = query
        return components.url
    }
}
