import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated enum CommunityImageProcessingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片处理失败，请换一张图片。"
        }
    }
}

extension CommunityImageUpload {
    static let thumbnailImageMaxPixelDimension: CGFloat = 480
    static let thumbnailImageMaxBytes = 120 * 1024

    @MainActor
    static func compressedJPEG(
        from image: UIImage,
        maxPixelDimension: CGFloat,
        maxBytes: Int
    ) throws -> CommunityImageUpload {
        let renderedImage = image.leafyRenderedForUpload(maxPixelDimension: maxPixelDimension)
        guard let data = renderedImage.leafyJPEGData(maxBytes: maxBytes) else {
            throw CommunityImageProcessingError.invalidImage
        }

        return CommunityImageUpload(
            data: data,
            mimeType: "image/jpeg",
            fileExtension: "jpg",
            width: Int(renderedImage.size.width.rounded()),
            height: Int(renderedImage.size.height.rounded())
        )
    }

    @MainActor
    func thumbnailUpload() throws -> CommunityImageUpload {
        guard let image = ImageDataDecoder.decodedImage(from: data) else {
            throw CommunityImageProcessingError.invalidImage
        }

        return try Self.compressedJPEG(
            from: image,
            maxPixelDimension: Self.thumbnailImageMaxPixelDimension,
            maxBytes: Self.thumbnailImageMaxBytes
        )
    }
}

private extension UIImage {
    var leafyPixelSize: CGSize {
        if let cgImage {
            return CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        }

        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func leafyRenderedForUpload(maxPixelDimension: CGFloat) -> UIImage {
        let sourceSize = leafyPixelSize
        let longestSide = max(sourceSize.width, sourceSize.height)
        let resizeRatio = longestSide > 0 ? min(1, maxPixelDimension / longestSide) : 1
        let targetSize = CGSize(
            width: max(1, (sourceSize.width * resizeRatio).rounded()),
            height: max(1, (sourceSize.height * resizeRatio).rounded())
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func leafyJPEGData(maxBytes: Int) -> Data? {
        let qualities: [CGFloat] = [0.82, 0.76, 0.68, 0.60, 0.52, 0.44, 0.36]
        var candidateImage = self
        var candidateMaxDimension = max(size.width, size.height)
        var smallestData: Data?

        for _ in 0..<4 {
            for quality in qualities {
                guard let data = candidateImage.jpegData(compressionQuality: quality) else {
                    continue
                }

                if smallestData == nil || data.count < (smallestData?.count ?? Int.max) {
                    smallestData = data
                }

                if data.count <= maxBytes {
                    return data
                }
            }

            candidateMaxDimension *= 0.82
            candidateImage = candidateImage.leafyRenderedForUpload(maxPixelDimension: candidateMaxDimension)
        }

        return smallestData
    }
}
