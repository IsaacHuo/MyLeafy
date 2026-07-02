import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
final class ExternalLearningMaterialImportCoordinator: ObservableObject {
    @Published var activeBatch: ExternalLearningMaterialImportManifest?
    @Published var alertMessage: String?

    private let store: ExternalLearningMaterialImportStore
    private var queuedBatchIDs: [UUID] = []

    init(store: ExternalLearningMaterialImportStore? = nil) {
        self.store = store ?? (try? ExternalLearningMaterialImportStore.appGroupStore()) ?? ExternalLearningMaterialImportStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(ExternalLearningMaterialImport.stagingDirectoryName, isDirectory: true)
        )
    }

    func handle(url: URL, isAuthenticated: Bool) -> Bool {
        if url.isFileURL {
            do {
                let manifest = try store.makeBatch(from: [url], source: .openIn)
                enqueue(manifest, isAuthenticated: isAuthenticated)
            } catch {
                alertMessage = error.localizedDescription
            }
            return true
        }

        guard let batchID = ExternalLearningMaterialImport.batchID(from: url) else {
            return false
        }

        do {
            let manifest = try store.loadManifest(id: batchID)
            enqueue(manifest, isAuthenticated: isAuthenticated)
        } catch {
            alertMessage = error.localizedDescription
        }
        return true
    }

    func presentPendingIfPossible(isAuthenticated: Bool) {
        guard isAuthenticated, activeBatch == nil else { return }

        while let batchID = queuedBatchIDs.first {
            queuedBatchIDs.removeFirst()
            if let manifest = try? store.loadManifest(id: batchID) {
                activeBatch = manifest
                return
            }
        }

        if let manifest = store.pendingManifests().first {
            activeBatch = manifest
        }
    }

    func cancel(_ batch: ExternalLearningMaterialImportManifest) {
        queuedBatchIDs.removeAll { $0 == batch.id }
        if activeBatch?.id == batch.id {
            activeBatch = nil
        }
        try? store.removeBatch(batch.id)
    }

    func importBatch(
        _ batch: ExternalLearningMaterialImportManifest,
        to destination: LearningWorkspaceDestination,
        modelContext: ModelContext,
        appNavigation: AppNavigationCoordinator
    ) throws -> Int {
        guard !batch.items.isEmpty else {
            throw ExternalLearningMaterialImportError.emptyBatch
        }

        for item in batch.items {
            let sourceURL = try store.stagedFileURL(for: item, in: batch)
            let stored = try LearningMaterialFileStore.importFile(
                from: sourceURL,
                contentTypeIdentifier: item.contentTypeIdentifier
            )
            let title = item.originalFilename.deletingPathExtensionTitle
            modelContext.insert(LearningMaterialDocument(
                projectID: destination.projectID,
                title: title.isEmpty ? "学习资料" : title,
                categoryRawValue: destination.fixedCategory?.rawValue ?? LearningMaterialCategory.other.rawValue,
                originalFilename: item.originalFilename,
                localFilename: stored.localFilename,
                contentTypeIdentifier: stored.contentTypeIdentifier
            ))
        }

        try modelContext.save()
        try? store.removeBatch(batch.id)
        queuedBatchIDs.removeAll { $0 == batch.id }
        if activeBatch?.id == batch.id {
            activeBatch = nil
        }
        appNavigation.openAcademicDetailRoute(.learningWorkspace(destination, initialTab: .materials))
        return batch.items.count
    }

    private func enqueue(_ manifest: ExternalLearningMaterialImportManifest, isAuthenticated: Bool) {
        guard activeBatch?.id != manifest.id, !queuedBatchIDs.contains(manifest.id) else { return }

        if isAuthenticated, activeBatch == nil {
            activeBatch = manifest
        } else {
            queuedBatchIDs.append(manifest.id)
        }
    }
}

private extension String {
    var deletingPathExtensionTitle: String {
        (self as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
