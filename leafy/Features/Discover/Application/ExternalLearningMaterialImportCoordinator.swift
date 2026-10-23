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
        self
            .store = store ?? (try? ExternalLearningMaterialImportStore.appGroupStore()) ??
            ExternalLearningMaterialImportStore(
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

    func presentPendingIfPossible(isAuthenticated: Bool, modelContext: ModelContext? = nil) {
        guard isAuthenticated, activeBatch == nil else { return }

        do {
            let importedIDs = try modelContext
                .map { Set(try $0.fetch(FetchDescriptor<LearningMaterialDocument>()).map(\.id)) } ?? []
            let isImported: (ExternalLearningMaterialImportManifest) -> Bool = { manifest in
                !manifest.items.isEmpty && manifest.items.allSatisfy { importedIDs.contains($0.id) }
            }
            while let batchID = queuedBatchIDs.first {
                let manifest = try store.loadManifest(id: batchID)
                queuedBatchIDs.removeFirst()
                if isImported(manifest) { try store.removeBatch(batchID); continue }
                activeBatch = manifest
                return
            }
            for manifest in try store.pendingManifests() {
                if isImported(manifest) { try store.removeBatch(manifest.id); continue }
                activeBatch = manifest
                return
            }
        } catch { alertMessage = error.localizedDescription }
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
        appNavigation: AppNavigationCoordinator,
        save: (ModelContext) throws -> Void = { try $0.save() },
        cleanup: LocalFileCleanup? = nil
    ) throws -> Int {
        guard !batch.items.isEmpty else { throw ExternalLearningMaterialImportError.emptyBatch }
        let sources = try batch.items.map { item in
            LearningMaterialBatchImport.Source(
                id: item.id, url: try store.stagedFileURL(for: item, in: batch),
                originalFilename: item.originalFilename, contentTypeIdentifier: item.contentTypeIdentifier
            )
        }
        let result = try LearningMaterialBatchImport.importFiles(
            sources,
            to: destination,
            in: modelContext,
            cleanup: cleanup,
            save: save
        )
        alertMessage = result.cleanupWarning
        // From this point the database is authoritative; cleanup errors must not trigger a second import.
        do { try store.removeBatch(batch.id) }
        catch { alertMessage = L10n.text("资料已保存，但暂存文件清理未完成：%@", error.localizedDescription) }
        queuedBatchIDs.removeAll { $0 == batch.id }
        if activeBatch?.id == batch.id { activeBatch = nil }
        appNavigation.openAcademicDetailRoute(.learningWorkspace(destination, initialTab: .materials))
        return result.documents.count
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
