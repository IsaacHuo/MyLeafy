import Foundation

protocol CommunityBannerRepository: Sendable {
    func fetchActiveBanner(campusID: String) async throws -> CommunityBanner?
}
