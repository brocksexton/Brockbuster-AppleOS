//
//  BrockbusterAPI 2.swift
//  Brockbuster
//
//  Created by Brock Sexton on 2025-12-31.
//


//
//  BrockbusterAPI.swift
//  Brockbuster
//
//  Created by Brock Sexton on 2025-12-31.
//

import Foundation

/// Client for Brockbuster website API (brockbuster.lol).
/// Uses Jellyfin token + userId for authentication, as required by the PHP API layer.
final class BrockbusterAPI {
    static let shared = BrockbusterAPI()

    /// Website base URL (NOT Jellyfin). This is the domain hosting /api/health.
    private let baseURL = URL(string: "https://brockbuster.lol")!

    private init() {}

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

        /// Not filled yet in A3 by default, but included for forward compatibility
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

        /// Not filled yet in A3 by default, but included for forward compatibility
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

    // MARK: - Errors

    enum APIError: LocalizedError {
        case notAuthenticated
        case invalidResponse
        case httpStatus(Int, String?)
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be logged in to view server health."
            case .invalidResponse:
                return "Invalid server response."
            case let .httpStatus(code, message):
                if let message, !message.isEmpty {
                    return "Server returned \(code): \(message)"
                }
                return "Server returned HTTP \(code)."
            case .decodeFailed:
                return "Failed to decode server data."
            }
        }
    }

    // MARK: - Public

    /// Fetches Health v2 payload from the website API.
    /// This expects /api/health to support v=2 query param as implemented in your A3 variant.
    func fetchHealthV2(jellyfinToken: String, jellyfinUserId: String) async throws -> HealthV2Response {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/health"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "v", value: "2")
        ]
        guard let url = components?.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Auth headers expected by your PHP api/_lib/jellyfin_auth.php
        request.setValue("Bearer \(jellyfinToken)", forHTTPHeaderField: "Authorization")
        request.setValue(jellyfinUserId, forHTTPHeaderField: "X-JF-UserId")

        // Helpful for Cloudflare/bot heuristics and logging
        request.setValue("BrockbusterApple/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            // Try to parse { ok:false, error:"..." } if present
            let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let errText = message?["error"] as? String
            throw APIError.httpStatus(http.statusCode, errText)
        }

        do {
            return try JSONDecoder().decode(HealthV2Response.self, from: data)
        } catch {
            throw APIError.decodeFailed
        }
    }
}
