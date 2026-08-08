import Foundation
import UIKit

enum ScheduleMemoImageStoreError: LocalizedError {
    case invalidImage
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取这张图片，请换一张图片。"
        case .compressionFailed:
            return "图片压缩失败，请换一张图片。"
        }
    }
}

enum ScheduleMemoImageStore {
    static let maximumImageCount = 3
    static let maximumPixelDimension: CGFloat = 1_600
    static let targetMaximumBytes = 1_024 * 1_024

    @MainActor
    static func importImage(data: Data) throws -> String {
        guard let image = ImageDataDecoder.decodedImage(from: data) else {
            throw ScheduleMemoImageStoreError.invalidImage
        }
        let rendered = render(image, maximumPixelDimension: maximumPixelDimension)
        guard let compressed = jpegData(for: rendered, maximumBytes: targetMaximumBytes) else {
            throw ScheduleMemoImageStoreError.compressionFailed
        }

        let directory = directoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).jpg"
        try compressed.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    static func image(named filename: String) -> UIImage? {
        UIImage(contentsOfFile: fileURL(named: filename).path(percentEncoded: false))
    }

    static func data(named filename: String) -> Data? {
        try? Data(contentsOf: fileURL(named: filename), options: .mappedIfSafe)
    }

    static func deleteFile(named filename: String, in directory: URL? = nil) throws {
        let url = (directory ?? directoryURL()).appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func deleteFiles(named filenames: [String], in directory: URL? = nil) throws {
        for filename in filenames {
            try deleteFile(named: filename, in: directory)
        }
    }

    static func deleteAllFiles(in directory: URL? = nil) throws {
        let url = directory ?? directoryURL()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func directoryURL(identity: CampusIdentity? = CampusIdentityStore.currentIdentity()) -> URL {
        if let identity,
           let scopedStore = CampusStoreScope.scopedStoreURL(for: identity) {
            return scopedStore.deletingLastPathComponent()
                .appendingPathComponent("ScheduleMemoImages", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScheduleMemoImages", isDirectory: true)
    }

    private static func fileURL(named filename: String) -> URL {
        directoryURL().appendingPathComponent(filename)
    }

    @MainActor
    private static func render(_ image: UIImage, maximumPixelDimension: CGFloat) -> UIImage {
        let pixelSize: CGSize
        if let cgImage = image.cgImage {
            pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        }
        let longestSide = max(pixelSize.width, pixelSize.height)
        let ratio = longestSide > 0 ? min(1, maximumPixelDimension / longestSide) : 1
        let targetSize = CGSize(
            width: max(1, (pixelSize.width * ratio).rounded()),
            height: max(1, (pixelSize.height * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    @MainActor
    private static func jpegData(for image: UIImage, maximumBytes: Int) -> Data? {
        var candidate = image
        var smallest: Data?
        for _ in 0..<4 {
            for quality in stride(from: CGFloat(0.84), through: 0.32, by: -0.08) {
                guard let data = candidate.jpegData(compressionQuality: quality) else { continue }
                if smallest == nil || data.count < (smallest?.count ?? .max) {
                    smallest = data
                }
                if data.count <= maximumBytes { return data }
            }
            candidate = render(candidate, maximumPixelDimension: max(candidate.size.width, candidate.size.height) * 0.8)
        }
        return smallest
    }
}
