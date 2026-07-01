import Foundation
import XCTest
@testable import Leafy

final class AppStoreUpdateLookupTests: XCTestCase {
    func testLookupSelectsResultForRequestedPlatform() throws {
        let data = Data(
            """
            {
              "results": [
                {"kind":"software","trackViewUrl":"https://apps.apple.com/app/id-ios"},
                {"kind":"mac-software","trackViewUrl":"https://apps.apple.com/app/id-mac"}
              ]
            }
            """.utf8
        )

        XCTAssertEqual(
            try AppStoreUpdateLookup.preferredURL(from: data, platform: .iOS)?.absoluteString,
            "https://apps.apple.com/app/id-ios"
        )
        XCTAssertEqual(
            try AppStoreUpdateLookup.preferredURL(from: data, platform: .macOS)?.absoluteString,
            "https://apps.apple.com/app/id-mac"
        )
    }

    func testLookupDoesNotFallBackToWrongPlatform() throws {
        let data = Data(
            """
            {"results":[{"kind":"software","trackViewUrl":"https://apps.apple.com/app/id-ios"}]}
            """.utf8
        )

        XCTAssertNil(try AppStoreUpdateLookup.preferredURL(from: data, platform: .macOS))
    }
}
