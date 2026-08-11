import Foundation
import ImageIO
import UIKit

enum ImageDataDecoder {
    static func decodedImage(
        from data: Data,
        targetSize: CGSize? = nil,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        if let targetSize {
            let maxDimension = max(targetSize.width, targetSize.height) * scale
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(Int(maxDimension.rounded(.up)), 1)
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return platformImage(from: image, scale: scale)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension(for: source)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return platformImage(from: image, scale: scale)
    }

    private static func platformImage(from image: CGImage, scale: CGFloat) -> UIImage {
        UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    private static func maxPixelDimension(for source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return 4096
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height, 1)
    }
}
