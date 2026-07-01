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
