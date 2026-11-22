import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum CommunityImageSaveError: LocalizedError {
    case invalidDownload
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidDownload: return L10n.text("图片下载失败，请稍后重试。")
        case .invalidImage: return L10n.text("图片文件无法读取，请重试。")
        }
    }
}

enum CommunityImageSaver {
    static func save(
        url: URL,
        download: (URL) async throws -> (URL, URLResponse) = { try await URLSession.shared.download(from: $0) },
        saveFiles: ([URL]) async throws -> Void = { try await LeafyPhotoLibrarySaver.saveImageFiles($0) }
    ) async throws {
        let (temporaryURL, response) = try await download(url)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else {
            throw CommunityImageSaveError.invalidDownload
        }
        guard let source = CGImageSourceCreateWithURL(temporaryURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0, let type = CGImageSourceGetType(source) else {
            throw CommunityImageSaveError.invalidImage
        }
        let fileExtension = UTType(type as String)?.preferredFilenameExtension ?? "image"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommunityImage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("image").appendingPathExtension(fileExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: imageURL)
        try Task.checkCancellation()
        try await saveFiles([imageURL])
    }
}
