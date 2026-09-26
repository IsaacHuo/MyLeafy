import Foundation

actor PostgraduateInfoService {
    static let shared = PostgraduateInfoService()
    func fetchPublishedSources(limit: Int = 80) async throws -> [PostgraduateSource] {
        try await CloudflareCommunityRepository().ensureAnonymousSession()
        return try await MyLeafyBackendEnvironment.client().get("/v1/postgraduate-sources", query: [URLQueryItem(name: "limit", value: String(max(1, min(limit, 120))))])
    }
}
