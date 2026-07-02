import Foundation
import Supabase

nonisolated enum BackendFeature: String, CaseIterable, Sendable {
    case communityFeed = "community_feed"
    case communityHotPosts = "community_hot_posts"
    case communityPolls = "community_polls"
    case communityNotifications = "community_notifications"
    case postFavorites = "post_favorites"
    case catalogRatings = "catalog_ratings"
    case postgraduateSources = "postgraduate_sources"
    case timetableSharing = "timetable_sharing"
    case campusRuntime = "campus_runtime"
    case campusWeather = "campus_weather"
    case schoolCommunityAccess = "school_community_access"
    case campusAI = "campus_ai"
    case campusAIManagedEntitlements = "campus_ai_managed_entitlements"
    case adminConsole = "admin_console"
}

nonisolated struct BackendCapabilities: Decodable, Sendable {
    let version: Int
    let generatedAt: String?
    let features: [String: Bool]
    let rpcs: [String: Bool]
    let edgeFunctions: [String]

    func supports(_ feature: BackendFeature) -> Bool {
        features[feature.rawValue] == true
    }

    func supportsRPC(_ name: String) -> Bool {
        rpcs[name] == true
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case features
        case rpcs
        case edgeFunctions = "edge_functions"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        features = try container.decodeIfPresent([String: Bool].self, forKey: .features) ?? [:]
        rpcs = try container.decodeIfPresent([String: Bool].self, forKey: .rpcs) ?? [:]
        edgeFunctions = try container.decodeIfPresent([String].self, forKey: .edgeFunctions) ?? []
    }
}

nonisolated struct BackendErrorEnvelope: Decodable, LocalizedError, Sendable {
    let code: String
    let message: String
    let retryable: Bool
    let details: String?

    var errorDescription: String? {
        message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case retryable
        case details
    }

    init(code: String, message: String, retryable: Bool, details: String? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        retryable = try container.decodeIfPresent(Bool.self, forKey: .retryable) ?? false
        details = (try? container.decodeIfPresent(String.self, forKey: .details)) ?? nil
    }
}

nonisolated struct BackendErrorPayload: Decodable, Sendable {
    let error: String?
    let errorEnvelope: BackendErrorEnvelope?
}

nonisolated struct SupabaseBackendClient {
    static let shared = SupabaseBackendClient()
    private static let capabilitiesCache = BackendCapabilitiesCache()

    private init() {}

    func capabilities(forceRefresh: Bool = false) async throws -> BackendCapabilities {
        try await Self.capabilitiesCache.value(forceRefresh: forceRefresh) {
            let client = try LeafySupabase.shared.requireClient()
            return try await client
                .rpc("backend_capabilities_v1")
                .execute()
                .value
        }
    }

    func decodedErrorPayload(from data: Data) -> BackendErrorPayload? {
        try? JSONDecoder().decode(BackendErrorPayload.self, from: data)
    }

    func decodedErrorEnvelope(from data: Data) -> BackendErrorEnvelope? {
        decodedErrorPayload(from: data)?.errorEnvelope
    }

    func mapFunctionsError(_ error: FunctionsError, fallbackMessage: String) -> BackendErrorEnvelope {
        switch error {
        case .relayError:
            return BackendErrorEnvelope(
                code: "backend_unavailable",
                message: fallbackMessage,
                retryable: true
            )
        case .httpError(let statusCode, let data):
            if let envelope = decodedErrorEnvelope(from: data) {
                return envelope
            }

            if let payload = decodedErrorPayload(from: data),
               let message = payload.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return BackendErrorEnvelope(
                    code: Self.code(forHTTPStatus: statusCode),
                    message: message,
                    retryable: Self.isRetryableHTTPStatus(statusCode)
                )
            }

            return BackendErrorEnvelope(
                code: Self.code(forHTTPStatus: statusCode),
                message: "后端返回了 \(statusCode) 错误。",
                retryable: Self.isRetryableHTTPStatus(statusCode)
            )
        }
    }

    private static func code(forHTTPStatus statusCode: Int) -> String {
        switch statusCode {
        case 400:
            return "bad_request"
        case 401:
            return "unauthorized"
        case 403:
            return "forbidden"
        case 404:
            return "not_found"
        case 405:
            return "method_not_allowed"
        case 409:
            return "conflict"
        case 429:
            return "rate_limited"
        case 500...:
            return "backend_unavailable"
        default:
            return "internal_error"
        }
    }

    private static func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || statusCode >= 500
    }
}

private actor BackendCapabilitiesCache {
    private var cached: BackendCapabilities?

    func value(
        forceRefresh: Bool,
        fetch: @Sendable () async throws -> BackendCapabilities
    ) async throws -> BackendCapabilities {
        if !forceRefresh, let cached {
            return cached
        }

        let fresh = try await fetch()
        cached = fresh
        return fresh
    }
}
