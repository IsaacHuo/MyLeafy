import Foundation
import Photos
import UIKit

enum LeafyPhotoLibrarySaveError: LocalizedError {
    case cancelled
    case permissionDenied
    case unreadableImage
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return L10n.text("已取消保存。")
        case .permissionDenied:
            return L10n.text("没有相册保存权限，请在系统设置中允许 %@ 添加照片。", AppBrand.displayName)
        case .unreadableImage:
            return L10n.text("图片文件无法读取，请重新生成。")
        case .saveFailed:
            return L10n.text("保存失败，请稍后重试。")
        }
    }
}

enum LeafyPhotoLibrarySaver {
    static func save(_ image: UIImage) async throws {
        try await requireAddOnlyAuthorization()
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                finishSave(success: success, error: error, continuation: continuation)
            }
        }
    }

    static func saveImageFiles(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { throw LeafyPhotoLibrarySaveError.unreadableImage }
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            throw LeafyPhotoLibrarySaveError.unreadableImage
        }
        try await requireAddOnlyAuthorization()
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            } completionHandler: { success, error in
                finishSave(success: success, error: error, continuation: continuation)
            }
        }
    }

    private static func requireAddOnlyAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requestedStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw LeafyPhotoLibrarySaveError.permissionDenied
            }
        default:
            throw LeafyPhotoLibrarySaveError.permissionDenied
        }
    }

    private static func finishSave(
        success: Bool,
        error: Error?,
        continuation: CheckedContinuation<Void, Error>
    ) {
        if let error {
            continuation.resume(throwing: error)
        } else if success {
            continuation.resume(returning: ())
        } else {
            continuation.resume(throwing: LeafyPhotoLibrarySaveError.saveFailed)
        }
    }
}
