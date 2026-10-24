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
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 5))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 5, width: 6, height: 5))
        }
        let data = try XCTUnwrap(jpegData(from: source, orientation: 6))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let original = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let loaded = await ScheduleMemoImageLoader.readImage(url)
        let decoded = try XCTUnwrap(loaded)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 6), format: format)
        func renderedPixels(_ image: UIImage) throws -> [UInt8] {
            let raster = try XCTUnwrap(renderer.image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: 10, height: 6))
            }.cgImage)
            var bytes = [UInt8](repeating: 0, count: 10 * 6 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 10, height: 6,
                                                      bitsPerComponent: 8, bytesPerRow: 40,
                                                      space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(raster, in: CGRect(x: 0, y: 0, width: 10, height: 6))
            }
            return bytes
        }
        XCTAssertEqual(decoded.size, original.size)
        let before = try renderedPixels(original)
        let after = try renderedPixels(decoded)
        XCTAssertEqual(before.count, after.count)
        // Display decoding may change channel rounding. Check the oriented content, not byte identity.
        func redBlueRegions(_ pixels: [UInt8]) -> [Bool] {
            [2, 7].map { x in
                let offset = (3 * 10 + x) * 4
                let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                XCTAssertGreaterThan(abs(red - blue), 80)
                XCTAssertGreaterThan(max(red, blue) - green, 60)
                return red > blue
            }
        }
        let expectedRegions = redBlueRegions(before)
        XCTAssertNotEqual(expectedRegions[0], expectedRegions[1])
        XCTAssertEqual(redBlueRegions(after), expectedRegions)
    }
}

extension PerformanceRefactorTests {
    @MainActor
    func testRepeatedCompressionReportsActualEncodedPixelDimensions() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 64), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
        }
        let source = try XCTUnwrap(image.pngData())
        let actorResult = try await CommunityImageProcessor.shared.compressedJPEG(
            from: source,
            maxPixelDimension: 96,
            maxBytes: 1
        )
        let uiResult = try CommunityImageUpload.compressedJPEG(from: image, maxPixelDimension: 96, maxBytes: 1)
        for upload in [actorResult.upload, uiResult] {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(upload.data as CFData, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(upload.width, properties[kCGImagePropertyPixelWidth] as? Int)
            XCTAssertEqual(upload.height, properties[kCGImagePropertyPixelHeight] as? Int)
            XCTAssertLessThan(try XCTUnwrap(upload.width), 96)
        }
    }
}
