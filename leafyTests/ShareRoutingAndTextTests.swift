import Foundation
import XCTest
@testable import Leafy

final class ShareRoutingAndTextTests: XCTestCase {
    func testTimetableInviteDeepLinkParsesSupportedURLs() throws {
        let universalLink = URL(string: "https://myleafy.space/share/timetable/ab-cd-ef-gh-jk-23")!
        let customScheme = URL(string: "leafy://timetable-invite?code=ABCDEFGHJK23")!

        XCTAssertEqual(TimetableInviteDeepLink(url: universalLink)?.code, "ABCDEFGHJK23")
        XCTAssertEqual(TimetableInviteDeepLink(url: customScheme)?.code, "ABCDEFGHJK23")
        XCTAssertNil(TimetableInviteDeepLink(url: URL(string: "https://myleafy.space/share/timetable/short")!))
    }

    func testCommunityPostDeepLinkKeepsParsingUniversalLinksWithQuery() throws {
        let postID = UUID()
        let universalLink = URL(string: "https://myleafy.space/share/community/post/\(postID.uuidString)?open=1")!

        XCTAssertEqual(CommunityPostDeepLink(url: universalLink)?.postID, postID)
    }

    func testTimetableInviteShareTextUsesVisibleAddAction() throws {
        let invite = TimetableInvite(
            id: UUID(),
            ownerID: UUID(),
            semesterID: "2026-2027-1",
            code: "ABCDEFGHJK23",
            expiresAt: "2026-08-02T12:00:00Z",
            acceptedBy: nil,
            acceptedAt: nil,
            createdAt: "2026-07-26T12:00:00Z"
        )

        let text = invite.shareText(ownerName: "同学")

        XCTAssertTrue(text.contains("添加同学的课表"))
        XCTAssertTrue(text.contains("https://myleafy.space/share/timetable/ABCDEFGHJK23"))
        XCTAssertFalse(text.contains("-> +"))
    }

    func testLinkedTextBuilderMarksDetectedURL() throws {
        let text = "这个网站可以点：https://example.com/path?q=1"
        let attributedText = LeafyLinkedTextBuilder.attributedString(from: text)
        let plainText = String(attributedText.characters)
        let urlRange = try XCTUnwrap(plainText.range(of: "https://example.com/path?q=1"))
        let lowerBound = try XCTUnwrap(AttributedString.Index(urlRange.lowerBound, within: attributedText))
        let upperBound = try XCTUnwrap(AttributedString.Index(urlRange.upperBound, within: attributedText))
        let links = attributedText[lowerBound..<upperBound].runs.compactMap(\.link)

        XCTAssertTrue(links.contains(URL(string: "https://example.com/path?q=1")!))
    }
}
