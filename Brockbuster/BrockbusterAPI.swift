//
//  BrockbusterAPI.swift
//  Brockbuster
//
//  Created by Brock Sexton on 2025-12-31.
//

import Foundation

/// Client for the optional companion "service layer" API that powers the
/// community features (Server Health, Friends, People).
/// Auth: Jellyfin token + userId, validated server-side via Jellyfin.
///
/// The expected endpoints and response shapes are documented in
/// docs/SERVICE_API.md so you can implement your own backend.
final class BrockbusterAPI {
    static let shared = BrockbusterAPI()

    /// Service base URL (NOT Jellyfin). This is the host serving the /api/*
    /// endpoints, configured via AppConfig.serviceBaseURL. When nil the
    /// service layer is disabled and every call throws `.serviceDisabled`.
    private var baseURL: URL? { AppConfig.serviceBaseURL }

    private init() {}

    // MARK: - Models (Generic Envelope)

    /// Some endpoints may respond as:
    /// { "ok": true, "data": { ... } }
    /// while others respond as:
    /// { "ok": true, ...top-level... }
    private struct Envelope<T: Decodable>: Decodable {
        let ok: Bool
        let data: T?
        let error: String?
    }

    // MARK: - Models (Health v2)

    struct HealthV2Response: Decodable {
        let ok: Bool
        let version: Int?
        let generatedAt: String?
        let status: StatusBlock?
        let hardware: HardwareBlock?
        let network: NetworkBlock?
        let storage: StorageBlock?
        let checks: ChecksBlock?
        let caller: CallerBlock?

        enum CodingKeys: String, CodingKey {
            case ok
            case version
            case generatedAt = "generated_at"
            case status
            case hardware
            case network
            case storage
            case checks
            case caller
        }

        struct StatusBlock: Decodable {
            let serverOnline: Bool?
            let severity: String?
            let badges: [Badge]?
            let banner: String?

            enum CodingKeys: String, CodingKey {
                case serverOnline = "server_online"
                case severity
                case badges
                case banner
            }

            struct Badge: Decodable, Identifiable {
                var id: String { (type ?? "") + ":" + (label ?? UUID().uuidString) }
                let type: String?
                let label: String?
            }
        }

        struct HardwareBlock: Decodable {
            let cpu: CPU?
            let gpu: GPU?
            let memory: Memory?

            struct CPU: Decodable {
                let name: String?
                let utilPercent: Double?
                enum CodingKeys: String, CodingKey { case name; case utilPercent = "util_percent" }
            }

            struct GPU: Decodable {
                let name: String?
                let utilPercent: Double?
                let vramUsedMB: Double?
                let vramTotalMB: Double?
                enum CodingKeys: String, CodingKey {
                    case name
                    case utilPercent = "util_percent"
                    case vramUsedMB = "vram_used_mb"
                    case vramTotalMB = "vram_total_mb"
                }
            }

            struct Memory: Decodable {
                let usedGB: Double?
                let totalGB: Double?
                enum CodingKeys: String, CodingKey { case usedGB = "used_gb"; case totalGB = "total_gb" }
            }
        }

        struct NetworkBlock: Decodable {
            let uptimeSeconds: Int?
            enum CodingKeys: String, CodingKey { case uptimeSeconds = "uptime_seconds" }
        }

        struct StorageBlock: Decodable {
            let thresholds: Thresholds?
            let drives: [Drive]?

            struct Thresholds: Decodable {
                let warningFreePercent: Double?
                let criticalFreePercent: Double?
                enum CodingKeys: String, CodingKey {
                    case warningFreePercent = "warning_free_percent"
                    case criticalFreePercent = "critical_free_percent"
                }
            }

            struct Drive: Decodable, Identifiable {
                var id: String { mount ?? UUID().uuidString }

                let mount: String?
                let label: String?
                let role: String?
                let usedBytes: Int?
                let freeBytes: Int?
                let totalBytes: Int?
                let freePercent: Double?
                let severity: String?

                enum CodingKeys: String, CodingKey {
                    case mount
                    case label
                    case role
                    case severity
                    case usedBytes = "used_bytes"
                    case freeBytes = "free_bytes"
                    case totalBytes = "total_bytes"
                    case freePercent = "free_percent"
                }

                var usedFraction: Double? {
                    guard let usedBytes, let totalBytes, totalBytes > 0 else { return nil }
                    return Double(usedBytes) / Double(totalBytes)
                }
            }
        }

        struct ChecksBlock: Decodable {
            let jellyfinPublicInfoOk: Bool?
            enum CodingKeys: String, CodingKey { case jellyfinPublicInfoOk = "jellyfin_public_info_ok" }
        }

        struct CallerBlock: Decodable {
            let userId: String?
            let name: String?
        }
    }

    // MARK: - Models (Friends)

    struct FriendsPayload: Decodable {
        let version: Int?
        let me: Me?
        let friends: [FriendItem]?
        let pending: [FriendItem]?

        struct Me: Decodable {
            let id: Int?
            let displayName: String?
            let isPublic: Bool?

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case isPublic = "is_public"
            }
        }

        struct FriendItem: Decodable, Identifiable {
            var id: Int { friendshipId ?? Int.random(in: 1...Int.max) }

            let friendshipId: Int?
            let status: String?
            let createdAt: String?
            let user: UserSummary?

            enum CodingKeys: String, CodingKey {
                case friendshipId = "friendship_id"
                case status
                case createdAt = "created_at"
                case user
            }
        }

        struct UserSummary: Decodable {
            let id: Int?
            let displayName: String?
            let avatarURL: String?
            let isPublic: Bool?
            let jellyfinUserId: String?

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case avatarURL = "avatar_url"
                case isPublic = "is_public"
                case jellyfinUserId = "jellyfin_user_id"
            }
        }
    }

    /// If your API returns flat keys, decode into this.
    private struct FriendsFlatResponse: Decodable {
        let ok: Bool
        let version: Int?
        let me: FriendsPayload.Me?
        let friends: [FriendsPayload.FriendItem]?
        let pending: [FriendsPayload.FriendItem]?
    }

    // MARK: - Models (People)

    struct PeoplePayload: Decodable {
        let version: Int?
        let query: String?
        let limit: Int?
        let offset: Int?
        let results: [Person]?

        struct Person: Decodable, Identifiable {
            let id: Int
            let displayName: String
            let avatarURL: String?
            let isPublic: Bool?
            let relationship: String? // "friends" / "pending" / "none"

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case avatarURL = "avatar_url"
                case isPublic = "is_public"
                case relationship
            }

            // MARK: - Backwards-compatible aliases (so older UI code compiles)

            /// Older UI code uses snake_case
            var display_name: String { displayName }
            var avatar_url: String? { avatarURL }
            var is_public: Bool { isPublic ?? false }

            /// Some of your earlier UI code used these
            var avatarUrl: String? { avatarURL }
            var displayNameSafe: String { displayName }
        }
    }

    private struct PeopleFlatResponse: Decodable {
        let ok: Bool
        let version: Int?
        let query: String?
        let limit: Int?
        let offset: Int?
        let results: [PeoplePayload.Person]?
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case serviceDisabled
        case notAuthenticated
        case invalidResponse
        case httpStatus(Int, String?)
        case decodeFailed(bodySnippet: String?)

        var errorDescription: String? {
            switch self {
            case .serviceDisabled:
                return "This build has no companion service configured."
            case .notAuthenticated:
                return "You must be logged in to use this feature."
            case .invalidResponse:
                return "Invalid server response."
            case let .httpStatus(code, message):
                if let message, !message.isEmpty { return "Server returned \(code): \(message)" }
                return "Server returned HTTP \(code)."
            case let .decodeFailed(bodySnippet):
                if let bodySnippet, !bodySnippet.isEmpty {
                    return "Failed to decode server data. Response: \(bodySnippet)"
                }
                return "Failed to decode server data."
            }
        }
    }

    // MARK: - Internal request helper

    private func makeRequest(path: String,
                             queryItems: [URLQueryItem] = [],
                             jellyfinToken: String,
                             jellyfinUserId: String) throws -> URLRequest {
        guard let baseURL else { throw APIError.serviceDisabled }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { comps?.queryItems = queryItems }
        guard let url = comps?.url else { throw APIError.invalidResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(jellyfinToken)", forHTTPHeaderField: "Authorization")
        req.setValue(jellyfinUserId, forHTTPHeaderField: "X-JF-UserId")
        req.setValue("BrockbusterApple/1.0", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func bodySnippet(_ data: Data) -> String {
        // Keep it short, helps debug HTML/PHP notices quickly.
        let s = String(data: data, encoding: .utf8) ?? ""
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 220 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 220)
        return String(trimmed[..<idx]) + "…"
    }

    private func decodeFlatOrEnvelope<Flat: Decodable, Payload: Decodable>(
        flat: Flat.Type,
        payload: Payload.Type,
        data: Data
    ) throws -> Payload {
        let decoder = JSONDecoder()

        // 1) Try “flat” JSON first
        if let flatObj = try? decoder.decode(flat, from: data) {
            // Map Flat -> Payload by re-encoding is annoying; so we decode Payload directly below if needed.
            // Instead of reflection, we just attempt decoding Payload itself after flat succeeds.
            // Most APIs do not need this path; it’s mostly to detect "ok" quickly.
            _ = flatObj
        }

        // Prefer: decode payload directly if the server returns it as the response body (no ok wrapper)
        if let directPayload = try? decoder.decode(Payload.self, from: data) {
            return directPayload
        }

        // 2) Try envelope: { ok, data:{...} }
        if let env = try? decoder.decode(Envelope<Payload>.self, from: data),
           env.ok, let payloadObj = env.data {
            return payloadObj
        }

        // 3) Try “flat response” where payload fields are top-level with ok
        // (We handle this via dedicated flat structs in the public methods.)
        throw APIError.decodeFailed(bodySnippet: bodySnippet(data))
    }

    private func validateHTTP(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            // Try to parse { ok:false, error:"..." } if present, otherwise include snippet.
            let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let errText = (message?["error"] as? String) ?? bodySnippet(data)
            throw APIError.httpStatus(http.statusCode, errText)
        }
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodeFailed(bodySnippet: bodySnippet(data))
        }
    }

    // MARK: - Public API

    func fetchHealthV2(jellyfinToken: String, jellyfinUserId: String) async throws -> HealthV2Response {
        let req = try makeRequest(
            path: "/api/health",
            queryItems: [URLQueryItem(name: "v", value: "2")],
            jellyfinToken: jellyfinToken,
            jellyfinUserId: jellyfinUserId
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(data: data, response: response)
        return try decodeJSON(HealthV2Response.self, data: data)
    }

    /// Returns payload for Friends page (accepted + pending).
    func fetchFriends(jellyfinToken: String, jellyfinUserId: String) async throws -> FriendsPayload {
        let req = try makeRequest(
            path: "/api/friends",
            jellyfinToken: jellyfinToken,
            jellyfinUserId: jellyfinUserId
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(data: data, response: response)

        // Try flat: { ok, version, me, friends, pending }
        if let flat = try? JSONDecoder().decode(FriendsFlatResponse.self, from: data), flat.ok {
            return FriendsPayload(
                version: flat.version,
                me: flat.me,
                friends: flat.friends,
                pending: flat.pending
            )
        }

        // Try envelope: { ok, data:{ version, me, friends, pending } }
        return try decodeFlatOrEnvelope(flat: FriendsFlatResponse.self, payload: FriendsPayload.self, data: data)
    }

    /// Returns payload for People/Public Accounts page.
    func fetchPeople(jellyfinToken: String,
                     jellyfinUserId: String,
                     query: String? = nil,
                     limit: Int = 24,
                     offset: Int = 0) async throws -> PeoplePayload {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(max(1, min(100, limit)))),
            URLQueryItem(name: "offset", value: String(max(0, offset)))
        ]
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            items.append(URLQueryItem(name: "query", value: q))
        }

        let req = try makeRequest(
            path: "/api/people",
            queryItems: items,
            jellyfinToken: jellyfinToken,
            jellyfinUserId: jellyfinUserId
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(data: data, response: response)

        // Flat: { ok, version, query, limit, offset, results }
        if let flat = try? JSONDecoder().decode(PeopleFlatResponse.self, from: data), flat.ok {
            return PeoplePayload(
                version: flat.version,
                query: flat.query,
                limit: flat.limit,
                offset: flat.offset,
                results: flat.results
            )
        }

        // Envelope fallback
        return try decodeFlatOrEnvelope(flat: PeopleFlatResponse.self, payload: PeoplePayload.self, data: data)
    }
}
