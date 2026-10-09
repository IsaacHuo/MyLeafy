import CoreImage
import LinkPresentation
import UIKit
import XCTest
@testable import Leafy

@MainActor
final class AndroidDownloadShareTests: XCTestCase {
    func testQRCodeOpensOfficialDownloadSection() throws {
        let image = try AndroidDownloadShareContent.qrCode()
        let ciImage = try XCTUnwrap(CIImage(image: image))
        let detector = try XCTUnwrap(CIDetector(
            ofType: CIDetectorTypeQRCode, context: CIContext(),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let code = try XCTUnwrap(detector.features(in: ciImage).first as? CIQRCodeFeature)
        XCTAssertEqual(code.messageString, "https://myleafy.space/#download")
    }

    func testRenderedCommunityStyleCardKeepsDownloadQRCodeReadable() throws {
        let snapshot = try AndroidDownloadShareContent.snapshot(language: .zhHans)
        XCTAssertEqual(snapshot.authorName, "MyLeafy")
        XCTAssertEqual(snapshot.avatarStyle, .appIcon)
        XCTAssertNotNil(snapshot.avatarData.flatMap { UIImage(data: $0) })
        XCTAssertFalse(snapshot.body.contains("\n"))
        XCTAssertEqual(snapshot.title, "MyLeafy 安卓版")
        XCTAssertTrue(snapshot.attachmentNames.isEmpty)
        let url = try CommunityPostCardGenerator.render(snapshot)
        defer { CommunityPostCardGenerator.deleteRenderedFile(url) }
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("MyLeafy-android-share-preview.jpg")
        try Data(contentsOf: url).write(to: previewURL)
        print("ANDROID_SHARE_PREVIEW=\(previewURL.path)")
        XCTAssertEqual(image.cgImage?.width, 1080)
        let detector = try XCTUnwrap(CIDetector(
            ofType: CIDetectorTypeQRCode, context: CIContext(),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let ciImage = try XCTUnwrap(CIImage(image: image))
        let messages = detector.features(in: ciImage).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(messages, [LeafyExternalLinks.androidDownload.absoluteString])
    }

    func testLinkShareProvidesClickableURLAndCardMetadata() throws {
        let url = try CommunityPostCardGenerator.render(AndroidDownloadShareContent.snapshot(language: .zhHans))
        defer { CommunityPostCardGenerator.deleteRenderedFile(url) }
        let source = AndroidDownloadLinkItemSource(title: "MyLeafy 安卓版", cardURL: url, appIcon: try LeafyAppIconManager.primaryIconImage())
        let activity = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        XCTAssertEqual(source.activityViewControllerPlaceholderItem(activity) as? URL, LeafyExternalLinks.androidDownload)
        XCTAssertEqual(source.activityViewController(activity, itemForActivityType: nil) as? URL, LeafyExternalLinks.androidDownload)
        let metadata = try XCTUnwrap(source.activityViewControllerLinkMetadata(activity))
        XCTAssertEqual(metadata.originalURL, LeafyExternalLinks.androidDownload)
        XCTAssertEqual(metadata.url?.fragment, "download")
        XCTAssertEqual(metadata.title, source.title)
        XCTAssertNotNil(metadata.imageProvider)
        XCTAssertNotNil(metadata.iconProvider)
    }
}
