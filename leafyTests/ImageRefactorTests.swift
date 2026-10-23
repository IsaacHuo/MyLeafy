import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import SwiftData
@testable import Leafy

extension PerformanceRefactorTests {
    func testImageProcessorDownsamplesUpload() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        let data = try XCTUnwrap(image.pngData())

        let result = try await CommunityImageProcessor.shared.compressedJPEG(
            from: data,
            maxPixelDimension: 32,
            maxBytes: 80 * 1024
        )

        XCTAssertLessThanOrEqual(result.upload.data.count, 80 * 1024)
        XCTAssertLessThanOrEqual(result.upload.width ?? 0, 32)
        XCTAssertLessThanOrEqual(result.upload.height ?? 0, 32)
        XCTAssertNotNil(UIImage(data: result.previewData))
    }

    func testImageDataDecoderHandlesValidAndInvalidData() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try XCTUnwrap(image.pngData())

        XCTAssertNotNil(ImageDataDecoder.decodedImage(from: data, targetSize: CGSize(width: 4, height: 4)))
        XCTAssertNil(ImageDataDecoder.decodedImage(from: Data("not-an-image".utf8)))
    }

    func testImageDataDecoderAppliesOrientationTransform() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sourceImage = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 10), format: format).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 10))
        }
        let orientedData = try XCTUnwrap(jpegData(from: sourceImage, orientation: 6))

        let decoded = try XCTUnwrap(ImageDataDecoder.decodedImage(from: orientedData, scale: 1))

        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertEqual(Int(decoded.size.width), 10)
        XCTAssertEqual(Int(decoded.size.height), 6)
    }
}

extension PerformanceRefactorTests {
    @MainActor
    func testMemoImageBackgroundReadPreservesRenderedOrientationAndDimensions() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 10), format: format).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 10))
        }
        let data = try XCTUnwrap(jpegData(from: source, orientation: 6))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let original = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let loaded = await ScheduleMemoImageLoader.readImage(url)
        let decoded = try XCTUnwrap(loaded)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 6), format: format)
        func rendered(_ image: UIImage) -> Data? {
            renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 10, height: 6)) }.pngData()
        }
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(rendered(decoded), rendered(original))
    }
}
