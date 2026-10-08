import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum LearningMaterialBatchImport {
    struct Source {
        let id: UUID
        let url: URL
        let originalFilename: String
        let contentTypeIdentifier: String?

        init(id: UUID = UUID(), url: URL, originalFilename: String? = nil, contentTypeIdentifier: String? = nil) {
            self.id = id
            self.url = url
            self.originalFilename = originalFilename ?? url.lastPathComponent
            self.contentTypeIdentifier = contentTypeIdentifier
        }
    }

    struct Result {
        let documents: [LearningMaterialDocument]
        let cleanupWarning: String?
    }

    static func importFiles(
        _ sources: [Source], to destination: LearningWorkspaceDestination, in context: ModelContext,
        cleanup: LocalFileCleanup? = nil,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Result {
        guard Set(sources.map(\.id)).count == sources.count else { throw CocoaError(.fileReadCorruptFile) }
        let cleanup = cleanup ?? LocalFileCleanup()
        let existing = Dictionary(grouping: try context.fetch(FetchDescriptor<LearningMaterialDocument>()), by: \.id)
        var documents: [LearningMaterialDocument] = []
        var newDocuments: [LearningMaterialDocument] = []
        var files: [LocalFileCleanup.File] = []
        do {
            for source in sources {
                if let matches = existing[source.id] {
                    guard matches.count == 1 else { throw CocoaError(.fileReadCorruptFile) }
                    documents.append(matches[0])
                    continue
                }
                let filename = LearningMaterialLocalFile.localFilename(originalExtension: source.url.pathExtension)
                let title = (source.originalFilename as NSString).deletingPathExtension
                let document = LearningMaterialDocument(
                    id: source.id, projectID: destination.projectID,
                    title: title.isEmpty ? L10n.text("学习资料") : title,
                    categoryRawValue: destination.fixedCategory?.rawValue ?? LearningMaterialCategory.other.rawValue,
                    originalFilename: source.originalFilename, localFilename: filename,
                    contentTypeIdentifier: source.contentTypeIdentifier ?? UTType.data.identifier
                )
                let file = LocalFileCleanup.File(document, url: LearningMaterialFileStore.fileURL(named: filename))
                // Record ownership before copying, so a crash or disk-full save leaves a recoverable intent.
                try cleanup.enqueue([file])
                files.append(file)
                let stored = try LearningMaterialFileStore.importFile(
                    from: source.url, contentTypeIdentifier: source.contentTypeIdentifier, filename: filename
                )
                document.contentTypeIdentifier = stored.contentTypeIdentifier
                newDocuments.append(document)
                documents.append(document)
            }
            for document in newDocuments { context.insert(document) }
            try LocalModelSave.save(context, undo: {
                for document in newDocuments { context.delete(document) }
            }, using: save)
        } catch {
            let originalError = error
            do { try cleanup.retry(in: context) }
            catch {
                throw ImportCleanupError(original: originalError.localizedDescription, cleanup: error.localizedDescription)
            }
            throw originalError
        }
        var warning: String?
        do { try cleanup.retry(in: context) }
        catch { warning = L10n.text("资料已保存，但本地清理尚未完成：%@", error.localizedDescription) }
        return Result(documents: documents, cleanupWarning: warning)
    }

    private struct ImportCleanupError: LocalizedError {
        let original: String
        let cleanup: String
        var errorDescription: String? {
            L10n.text("资料未保存：%@。新增文件清理未完成，已保留待清理记录：%@", original, cleanup)
        }
    }
}
