import Foundation

protocol CommunityBannerRepository: Sendable {
    func fetchActiveBanner(campusID: String) async throws -> CommunityBanner?
}

struct LiveCommunityBannerRepository: CommunityBannerRepository {
    private let service: CommunityService

    nonisolated init(service: CommunityService = .shared) {
        self.service = service
    }

    func fetchActiveBanner(campusID: String) async throws -> CommunityBanner? {
        try await service.ensureAnonymousSession()
        return try await service.fetchActiveBanner(campusID: campusID)
    }
}
