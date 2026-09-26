import Foundation

/// An explicit build configuration selects one authority. Request failures never
/// change this selection or retry against another backend.
nonisolated enum MyLeafyBackendEnvironment {
    static let clientResult: Result<MyLeafyBackendClient, Error> = Result {
        guard let origin = configuredString("MYLEAFY_API_ORIGIN"), let url = URL(string: origin) else {
            throw MyLeafyBackendError(status: 0, code: "invalid_backend_configuration", message: "后台配置无效，请联系开发者。", requestID: nil)
        }
        return try MyLeafyBackendClient(baseURL: url)
    }
    static func client() throws -> MyLeafyBackendClient { try clientResult.get() }
    static var publicationAuthority: String {
        return configuredString("MYLEAFY_API_ORIGIN") ?? "invalid-cloudflare-origin"
    }
    static var cachedUserID: UUID? {
        guard case .success(let client) = clientResult else { return nil }
        return try? MyLeafyBackendKeychainStore(origin: client.baseURL.absoluteString).load()?.userID
    }
    private static func configuredString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }
}

nonisolated enum CommunityBackendFactory {
    static var repository: any CommunityRepository {
        CloudflareCommunityRepository()
    }
    static var activity: any CommunityActivityRepository {
        CloudflareCommunityRepository()
    }
    static var identity: any CommunityIdentitySessionRepository {
        CloudflareCommunityRepository()
    }
    static var banner: any CommunityBannerRepository {
        CloudflareCommunityRepository()
    }
    static var changes: any CommunityFeedChangeStreaming {
        CloudflareCommunityRepository()
    }
    static var publish: any CommunityPublishBackend {
        CloudflareCommunityRepository()
    }
}
