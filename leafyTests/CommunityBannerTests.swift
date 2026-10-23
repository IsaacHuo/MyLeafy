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

    @MainActor
    func testSupersededBannerRequestCannotReplaceLatestBanner() async {
        let firstStarted = expectation(description: "First banner pending")
        let secondStarted = expectation(description: "Second banner pending")
        let repository = SuspendedBannerRepository(started: ["first": firstStarted, "second": secondStarted])
        let model = CommunityBannerViewModel(repository: repository)
        let first = Task { await model.load(campusID: "first") }
        await fulfillment(of: [firstStarted], timeout: 3)
        let second = Task { await model.load(campusID: "second") }
        await fulfillment(of: [secondStarted], timeout: 3)
        let latest = makeBanner(id: UUID(), revision: 2)
        repository.resume("second", banner: latest)
        await second.value
        repository.resume("first", banner: makeBanner(id: UUID(), revision: 1))
        await first.value
        XCTAssertEqual(model.banner, latest)
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

@MainActor
private final class SuspendedBannerRepository: CommunityBannerRepository {
    let started: [String: XCTestExpectation]
    private var pending: [String: CheckedContinuation<CommunityBanner?, Error>] = [:]
    init(started: [String: XCTestExpectation]) { self.started = started }
    func fetchActiveBanner(campusID: String) async throws -> CommunityBanner? {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                pending[campusID] = $0
                started[campusID]?.fulfill()
            }
        } onCancel: { [self] in
            Task { @MainActor in self.cancel(campusID) }
        }
    }
    func resume(_ campusID: String, banner: CommunityBanner) {
        pending.removeValue(forKey: campusID)?.resume(returning: banner)
    }
    private func cancel(_ campusID: String) {
        pending.removeValue(forKey: campusID)?.resume(throwing: CancellationError())
    }
}
