import CoreImage
import LinkPresentation
import UIKit
import XCTest
@testable import Leafy

@MainActor
final class AndroidDownloadShareTests: XCTestCase {
    func testQRCodeOpensOfficialDownloadSection() throws {
        let image = try AndroidDownloadShareContent.qrCode()
        XCTAssertEqual(try qrMessages(in: image), [LeafyExternalLinks.androidDownload.absoluteString])
    }

    func testPortraitPNGKeepsOfficialDownloadQRCodeReadableInBothLanguages() throws {
        for language in [AppLanguagePreference.zhHans, .enUS] {
            let card = try AndroidDownloadShareContent.card(language: language)
            XCTAssertGreaterThanOrEqual(card.iconImage.cgImage?.width ?? 0, 300)
            let url = try AndroidDownloadShareCardRenderer.render(card)
            defer { AndroidDownloadShareCardRenderer.deleteRenderedFile(url) }
            let data = try Data(contentsOf: url)
            XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertEqual(image.cgImage?.width, 1080)
            XCTAssertEqual(image.cgImage?.height, 1584)
            XCTAssertEqual(try qrMessages(in: image), [LeafyExternalLinks.androidDownload.absoluteString])
            let attachment = XCTAttachment(image: image)
            attachment.name = "Android share card - \(language.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testRegenerationUsesIndependentFilesAndCleanupPreservesOtherCards() throws {
        let card = try AndroidDownloadShareContent.card(language: .zhHans)
        let first = try AndroidDownloadShareCardRenderer.render(card)
        let second = try AndroidDownloadShareCardRenderer.render(card)
        defer {
            AndroidDownloadShareCardRenderer.deleteRenderedFile(first)
            AndroidDownloadShareCardRenderer.deleteRenderedFile(second)
        }
        XCTAssertNotEqual(first, second)
        AndroidDownloadShareCardRenderer.deleteRenderedFile(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        XCTAssertNotNil(UIImage(contentsOfFile: second.path))
        AndroidDownloadShareCardRenderer.deleteRenderedFile(first)
        AndroidDownloadShareCardRenderer.deleteRenderedFile(second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.deletingLastPathComponent().path))
    }

    func testLinkShareProvidesClickableURLAndCardMetadata() throws {
        let card = try AndroidDownloadShareContent.card(language: .zhHans)
        let url = try AndroidDownloadShareCardRenderer.render(card)
        defer { AndroidDownloadShareCardRenderer.deleteRenderedFile(url) }
        let source = AndroidDownloadLinkItemSource(title: "MyLeafy 安卓版", cardURL: url, appIcon: card.iconImage)
        let activity = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        assertDownloadURL(source, activity: activity)
        let metadata = try XCTUnwrap(source.activityViewControllerLinkMetadata(activity))
        XCTAssertNotNil(metadata.imageProvider)
        XCTAssertNotNil(metadata.iconProvider)
    }

    func testLinkShareWorksWithoutGeneratedCardOrIcon() throws {
        let source = AndroidDownloadLinkItemSource(title: "MyLeafy 安卓版")
        let activity = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        assertDownloadURL(source, activity: activity)
        let metadata = try XCTUnwrap(source.activityViewControllerLinkMetadata(activity))
        XCTAssertNil(metadata.imageProvider)
        XCTAssertNil(metadata.iconProvider)
    }

    private func assertDownloadURL(_ source: AndroidDownloadLinkItemSource, activity: UIActivityViewController) {
        XCTAssertEqual(
            source.activityViewControllerPlaceholderItem(activity) as? URL,
            LeafyExternalLinks.androidDownload
        )
        XCTAssertEqual(
            source.activityViewController(activity, itemForActivityType: nil) as? URL,
            LeafyExternalLinks.androidDownload
        )
        let metadata = source.activityViewControllerLinkMetadata(activity)
        XCTAssertEqual(metadata?.originalURL, LeafyExternalLinks.androidDownload)
        XCTAssertEqual(metadata?.url?.fragment, "download")
        XCTAssertEqual(metadata?.title, source.title)
    }

    private func qrMessages(in image: UIImage) throws -> [String] {
        let detector = try XCTUnwrap(CIDetector(
            ofType: CIDetectorTypeQRCode, context: CIContext(),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let ciImage = try XCTUnwrap(CIImage(image: image))
        return detector.features(in: ciImage).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
