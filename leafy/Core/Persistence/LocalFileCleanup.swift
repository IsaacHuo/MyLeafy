import Foundation
import SwiftData

@MainActor
protocol LocalFileRecord: PersistentModel {
    var id: UUID { get }
    var localFilename: String { get }
}

extension ScheduleMemoImage: LocalFileRecord {}
extension ScheduleMemoAttachment: LocalFileRecord {}
extension ScheduleMemoAudio: LocalFileRecord {}
extension LearningMaterialDocument: LocalFileRecord {}
extension HonorRecord: LocalFileRecord {}
extension ComprehensiveQualityEvidenceDocument: LocalFileRecord {}
extension MedicalLedgerPhoto: LocalFileRecord {}
extension CareerResumeDocument: LocalFileRecord {}

@MainActor
struct LocalFileCleanup {
    nonisolated struct File: Codable, Hashable, Sendable {
        let path: String
        let ownerID: UUID
        let ownerType: String

        @MainActor
        init<T: LocalFileRecord>(_ owner: T, url: URL) {
            let base = Self.applicationSupport.path + "/"
            let path = url.standardizedFileURL.path
            self.path = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
            ownerID = owner.id
            ownerType = String(describing: T.self)
        }

        var url: URL { URL(fileURLWithPath: path, relativeTo: Self.applicationSupport) }

        private static var applicationSupport: URL {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
    }

    private let queueURL: URL
    private let removeFile: (URL) throws -> Void

    init(
        queueURL: URL? = nil,
        removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        let root = CampusIdentityStore.currentIdentity().flatMap(CampusStoreScope.scopedStoreURL)?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.queueURL = queueURL ?? root.appendingPathComponent("PendingLocalFileCleanup.json")
        self.removeFile = removeFile
    }

    func delete(
        _ models: [any PersistentModel], files: [File], in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try enqueue(files)
        for model in models { context.delete(model) }
        try LocalModelSave.save(context, undo: {
            for model in models { context.insert(model) }
        }, using: save)
        // A crash between the database commit and cleanup is recovered from this queue.
        do { try retry(in: context) }
        catch { throw CleanupPendingError(detail: error.localizedDescription) }
    }

    func enqueue(_ files: [File]) throws {
        guard !files.isEmpty else { return }
        let pending = try load()
        try write(Array(Set(pending + files)))
    }

    func retry(in context: ModelContext) throws {
        let pending = try load()
        guard !pending.isEmpty else { return }
        var liveFiles: [String: Set<String>] = [:]
        for name in Set(pending.map(\.ownerType)) {
            guard context.container.schema.entitiesByName[name] != nil else { throw CocoaError(.fileReadCorruptFile) }
            switch name {
            case "ScheduleMemoImage": liveFiles[name] = try references(ScheduleMemoImage.self, in: context)
            case "ScheduleMemoAttachment": liveFiles[name] = try references(ScheduleMemoAttachment.self, in: context)
            case "ScheduleMemoAudio": liveFiles[name] = try references(ScheduleMemoAudio.self, in: context)
            case "LearningMaterialDocument": liveFiles[name] = try references(LearningMaterialDocument.self, in: context)
            case "HonorRecord": liveFiles[name] = try references(HonorRecord.self, in: context)
            case "ComprehensiveQualityEvidenceDocument": liveFiles[name] = try references(ComprehensiveQualityEvidenceDocument.self, in: context)
            case "MedicalLedgerPhoto": liveFiles[name] = try references(MedicalLedgerPhoto.self, in: context)
            case "CareerResumeDocument": liveFiles[name] = try references(CareerResumeDocument.self, in: context)
            default: throw CocoaError(.fileReadCorruptFile)
            }
        }
        var remaining: [File] = []
        var failure: Error?
        for file in pending {
            // Prepared operations whose database commit failed must never delete live files.
            guard liveFiles[file.ownerType]?.contains(file.url.lastPathComponent) != true else { continue }
            guard FileManager.default.fileExists(atPath: file.url.path) else { continue }
            do { try removeFile(file.url) }
            catch { remaining.append(file); failure = error }
        }
        try write(remaining)
        if let failure { throw failure }
    }

    private func references<T: LocalFileRecord>(_ type: T.Type, in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<T>()).map(\.localFilename))
    }

    private func load() throws -> [File] {
        guard FileManager.default.fileExists(atPath: queueURL.path) else { return [] }
        return try JSONDecoder().decode([File].self, from: Data(contentsOf: queueURL))
    }

    private func write(_ files: [File]) throws {
        try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(files).write(to: queueURL, options: .atomic)
    }

    private struct CleanupPendingError: LocalizedError {
        let detail: String
        var errorDescription: String? {
            L10n.text("记录已删除，但部分本地文件未能清理。下次打开 App 会重试。%@", detail)
        }
    }
}
