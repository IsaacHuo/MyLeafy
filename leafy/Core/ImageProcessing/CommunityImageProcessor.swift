import Foundation
import ImageIO
import os
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CommunityImageProcessingResult {
    let upload: CommunityImageUpload
    let previewData: Data
}

protocol CommunityImageProcessing: Sendable {
    func compressedJPEG(
        from data: Data,
        maxPixelDimension: CGFloat,
        maxBytes: Int
    ) async throws -> CommunityImageProcessingResult
}

actor CommunityImageProcessor: CommunityImageProcessing {
    static let shared = CommunityImageProcessor()

    func compressedJPEG(
        from data: Data,
        maxPixelDimension: CGFloat,
        maxBytes: Int
    ) async throws -> CommunityImageProcessingResult {
        let state = LeafyPerformanceSignposter.imageProcessing.beginInterval("compress-jpeg")
        defer { LeafyPerformanceSignposter.imageProcessing.endInterval("compress-jpeg", state) }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CommunityImageProcessingError.invalidImage
        }

        let thumbnail = try Self.makeThumbnail(
            from: imageSource,
            maxPixelDimension: maxPixelDimension
        )
        let encoded = try Self.encodeJPEG(
            image: thumbnail,
            maxBytes: maxBytes
        )

        let upload = CommunityImageUpload(
            data: encoded.data,
            mimeType: "image/jpeg",
            fileExtension: "jpg",
            width: thumbnail.width,
            height: thumbnail.height
        )
        return CommunityImageProcessingResult(upload: upload, previewData: encoded.data)
    }

    nonisolated private static func makeThumbnail(
        from source: CGImageSource,
        maxPixelDimension: CGFloat
    ) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelDimension.rounded(.down))),
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CommunityImageProcessingError.invalidImage
        }

        return image
    }

    nonisolated private static func encodeJPEG(
        image: CGImage,
        maxBytes: Int
    ) throws -> (data: Data, quality: CGFloat) {
        let qualities: [CGFloat] = [0.82, 0.76, 0.68, 0.60, 0.52, 0.44, 0.36]
        var candidateImage = image
        var smallestData: Data?
        var smallestQuality = qualities.last ?? 0.36
        var currentMaxDimension = CGFloat(max(image.width, image.height))

        for _ in 0..<4 {
            for quality in qualities {
                guard let data = jpegData(from: candidateImage, quality: quality) else {
                    continue
                }

                if smallestData == nil || data.count < (smallestData?.count ?? Int.max) {
                    smallestData = data
                    smallestQuality = quality
                }

                if data.count <= maxBytes {
                    return (data, quality)
                }
            }

            currentMaxDimension *= 0.82
            guard let resized = resizedImage(candidateImage, maxPixelDimension: currentMaxDimension) else {
                break
            }
            candidateImage = resized
        }

        guard let smallestData else {
            throw CommunityImageProcessingError.invalidImage
        }
        return (smallestData, smallestQuality)
    }

    nonisolated private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    nonisolated private static func resizedImage(_ image: CGImage, maxPixelDimension: CGFloat) -> CGImage? {
        let longestSide = CGFloat(max(image.width, image.height))
        guard longestSide > maxPixelDimension else { return image }

        let ratio = maxPixelDimension / longestSide
        let width = max(1, Int((CGFloat(image.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(image.height) * ratio).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
