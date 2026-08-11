import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
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
