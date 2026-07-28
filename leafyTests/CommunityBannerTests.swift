import XCTest
@testable import Leafy

final class CommunityBannerTests: XCTestCase {
    func testBannerDecodesDestinationAndSignedImage() throws {
        let data = Data(
            #"""
            {
              "id": "11111111-2222-3333-8444-555555555555",
              "campus_id": "bjfu",
              "revision": 3,
              "title": "校园春日计划",
              "subtitle": "查看本周社区精选",
              "image_path": "bjfu/banner.jpg",
              "signed_image_url": "https://example.com/banner.jpg",
              "destination_kind": "community_post",
              "destination_value": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
              "published_at": "2026-07-28T01:00:00Z",
              "expires_at": null
            }
            """#.utf8
        )

        let banner = try JSONDecoder().decode(CommunityBanner.self, from: data)

        XCTAssertEqual(banner.campusID, "bjfu")
        XCTAssertEqual(banner.revision, 3)
        XCTAssertEqual(banner.destinationKind, .communityPost)
        XCTAssertTrue(banner.hasDestination)
        XCTAssertEqual(banner.imageURL?.host, "example.com")
        XCTAssertTrue(banner.dismissalKey.contains(".r3"))
    }

    func testNewRevisionUsesDifferentDismissalKey() {
        let id = UUID()
        let first = makeBanner(id: id, revision: 1)
        let second = makeBanner(id: id, revision: 2)

        XCTAssertNotEqual(first.dismissalKey, second.dismissalKey)
    }

    private func makeBanner(id: UUID, revision: Int) -> CommunityBanner {
        CommunityBanner(
            id: id,
            campusID: "bjfu",
            revision: revision,
            title: "标题",
            subtitle: "副标题",
            imagePath: nil,
            imageURL: nil,
            destinationKind: .none,
            destinationValue: nil,
            publishedAt: nil,
            expiresAt: nil
        )
    }
}
