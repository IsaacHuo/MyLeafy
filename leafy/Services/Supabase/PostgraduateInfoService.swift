import Foundation
import Supabase

actor PostgraduateInfoService {
    static let shared = PostgraduateInfoService()

    private init() {}

    func fetchPublishedSources(limit: Int = 80) async throws -> [PostgraduateSource] {
        if MyLeafyBackendEnvironment.usesCloudflare {
            try await CloudflareCommunityRepository().ensureAnonymousSession()
            return try await MyLeafyBackendEnvironment.client().get("/v1/postgraduate-sources", query: [URLQueryItem(name: "limit", value: String(max(1, min(limit, 120))))])
        }
        try await CommunityService.shared.ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        let cappedLimit = max(1, min(limit, 120))

        return try await client
            .from("postgraduate_sources")
            .select()
            .eq("status", value: "published")
            .order("verified_at", ascending: false)
            .order("published_at", ascending: false)
            .limit(cappedLimit)
            .execute()
            .value
    }
}
