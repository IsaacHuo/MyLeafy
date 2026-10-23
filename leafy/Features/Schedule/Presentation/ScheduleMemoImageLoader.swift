import Foundation
import Observation
import os
import UIKit

nonisolated struct ScheduleMemoImageRequest: Equatable, Sendable {
    nonisolated struct Source: Equatable, Sendable {
        let id: UUID
        let url: URL
        let importedAt: Date
    }

    let sources: [Source]
    let revision: Date

    @MainActor
    init(images: [ScheduleMemoImage], revision: Date, directory: URL? = nil) {
        let directory = directory ?? ScheduleMemoImageStore.directoryURL()
        sources = images.map {
            Source(id: $0.id, url: directory.appendingPathComponent($0.localFilename), importedAt: $0.importedAt)
        }
        self.revision = revision
    }
}

@MainActor
@Observable
final class ScheduleMemoImageLoader {
    private var loadedRequest: ScheduleMemoImageRequest?
    private var loadedImages: [UUID: UIImage] = [:]
    private var runID = UUID()

    func images(for request: ScheduleMemoImageRequest) -> [UUID: UIImage] {
        loadedRequest == request ? loadedImages : [:]
    }

    func isLoading(_ request: ScheduleMemoImageRequest) -> Bool {
        loadedRequest != request
    }

    func reset() {
        runID = UUID()
        loadedRequest = nil
        loadedImages = [:]
    }

    func load(
        _ request: ScheduleMemoImageRequest,
        read: @escaping @Sendable (URL) async -> UIImage? = ScheduleMemoImageLoader.readImage
    ) async {
        guard loadedRequest != request else { return }
        let currentRun = UUID()
        runID = currentRun
        loadedRequest = nil
        loadedImages = [:]
        let scope = CampusOperationScope()
        let task = Task.detached(priority: .userInitiated) {
            var images: [UUID: UIImage] = [:]
            for source in request.sources {
                try Task.checkCancellation()
                if let image = await read(source.url) { images[source.id] = image }
            }
            return images
        }
        do {
            let images = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try scope.check()
            guard runID == currentRun else { return }
            loadedImages = images
            loadedRequest = request
        } catch {
            // Cancelled or superseded loads must never replace the current identity's images.
        }
    }

    nonisolated static func readImage(_ url: URL) async -> UIImage? {
        let state = LeafyPerformanceSignposter.imageProcessing.beginInterval("schedule-memo-image-load")
        defer { LeafyPerformanceSignposter.imageProcessing.endInterval("schedule-memo-image-load", state) }
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        return image.preparingForDisplay() ?? image
    }
}
