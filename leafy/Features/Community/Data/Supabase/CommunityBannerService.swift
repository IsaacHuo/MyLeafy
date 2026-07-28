import Foundation
import Supabase

extension CommunityService {
    nonisolated func fetchActiveBanner(
        campusID: String = ActiveCampusContext.descriptor.id.rawValue
    ) async throws -> CommunityBanner? {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityBannerRecord] = try await client
            .from("community_banners")
            .select()
            .eq("campus_id", value: campusID)
            .eq("status", value: "published")
            .order("published_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let record = records.first else { return nil }
        let imageURL: URL?
        if let imagePath = record.imagePath {
            let results = try await client.storage
                .from("community-banner-assets")
                .createSignedURLs(paths: [imagePath], expiresIn: 60 * 60)
            imageURL = results.first?.signedURL
        } else {
            imageURL = nil
        }

        return CommunityBanner(
            id: record.id,
            campusID: record.campusID,
            revision: record.revision,
            title: record.title,
            subtitle: record.subtitle,
            imagePath: record.imagePath,
            imageURL: imageURL,
            destinationKind: record.destinationKind,
            destinationValue: record.destinationValue,
            publishedAt: record.publishedAt,
            expiresAt: record.expiresAt
        )
    }
}

private nonisolated struct CommunityBannerRecord: Decodable, Sendable {
    let id: UUID
    let campusID: String
    let revision: Int
    let title: String
    let subtitle: String
    let imagePath: String?
    let destinationKind: CommunityBannerDestinationKind
    let destinationValue: String?
    let publishedAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case campusID = "campus_id"
        case revision
        case title
        case subtitle
        case imagePath = "image_path"
        case destinationKind = "destination_kind"
        case destinationValue = "destination_value"
        case publishedAt = "published_at"
        case expiresAt = "expires_at"
    }
}
