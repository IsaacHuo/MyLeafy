import Foundation
import XCTest
@testable import Leafy

final class AppStoreUpdateLookupTests: XCTestCase {
    func testLookupSelectsIOSResult() throws {
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
            try AppStoreUpdateLookup.preferredURL(from: data)?.absoluteString,
            "https://apps.apple.com/app/id-ios"
        )
    }

    func testLookupIgnoresNonIOSResult() throws {
        let data = Data(
            """
            {"results":[{"kind":"mac-software","trackViewUrl":"https://apps.apple.com/app/id-mac"}]}
            """.utf8
        )

        XCTAssertNil(try AppStoreUpdateLookup.preferredURL(from: data))
    }
}
