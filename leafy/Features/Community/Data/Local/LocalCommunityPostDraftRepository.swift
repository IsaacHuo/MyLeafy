import Foundation
import OSLog

@MainActor
final class LocalCommunityPostDraftRepository: CommunityPostDraftRepository {
    static let shared = LocalCommunityPostDraftRepository()

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let appliesFileProtection: Bool
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyLeafy", category: "CommunityDrafts")

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        appliesFileProtection: Bool = true
    ) {
        self.fileManager = fileManager
        self.appliesFileProtection = appliesFileProtection
        let base = rootDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.rootDirectory = base
            .appendingPathComponent("CommunityPostDrafts", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    func listDrafts(ownerProfileID: UUID) throws -> [CommunityPostDraft] {
        let ownerDirectory = ownerDirectory(ownerProfileID)
        guard fileManager.fileExists(atPath: ownerDirectory.path) else { return [] }

        do {
            return try fileManager
                .contentsOfDirectory(
                    at: ownerDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { try decodeManifest(at: $0.appendingPathComponent("manifest.json")) }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch let error as CommunityPostDraftError {
            throw error
        } catch {
            logger.error(
                "List community drafts failed owner=\(ownerProfileID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw CommunityPostDraftError.storageFailure(error.localizedDescription)
        }
    }

    func loadDraft(id: UUID, ownerProfileID: UUID) throws -> CommunityPostDraftEditorPayload {
        let directory = draftDirectory(id: id, ownerProfileID: ownerProfileID)
        let draft = try decodeManifest(at: directory.appendingPathComponent("manifest.json"))
        guard draft.ownerProfileID == ownerProfileID else {
            throw CommunityPostDraftError.ownerMismatch
        }

        let images = try draft.images
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { record -> CommunityImageUpload in
                let url = directory.appendingPathComponent(record.fileName)
                guard fileManager.fileExists(atPath: url.path) else {
                    throw CommunityPostDraftError.missingImage(record.fileName)
                }
                let data = try Data(contentsOf: url)
                guard ImageDataDecoder.decodedImage(from: data) != nil else {
                    throw CommunityPostDraftError.invalidImage(record.fileName)
                }
                return CommunityImageUpload(
                    id: record.id,
                    data: data,
                    mimeType: record.mimeType,
                    fileExtension: record.fileExtension,
                    width: record.width,
                    height: record.height
                )
            }

        let attachments = try draft.attachments
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { record -> CommunityAttachmentUpload in
                let url = directory.appendingPathComponent(record.fileName)
                guard fileManager.fileExists(atPath: url.path) else {
                    throw CommunityPostDraftError.missingAttachment(record.displayName)
                }
                return CommunityAttachmentUpload(
                    id: record.id,
                    localURL: url,
                    displayName: record.displayName,
                    contentType: record.contentType,
                    fileExtension: record.fileExtension,
                    byteSize: record.byteSize
                )
            }

        return CommunityPostDraftEditorPayload(
            draft: draft,
            images: images,
            attachments: attachments
        )
    }

    @discardableResult
    func saveDraft(
        id: UUID,
        ownerProfileID: UUID,
        input: CreatePostInput,
        images: [CommunityImageUpload],
        attachments: [CommunityAttachmentUpload]
    ) throws -> CommunityPostDraftEditorPayload {
        let directory = draftDirectory(id: id, ownerProfileID: ownerProfileID)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try applyFileProtection(to: directory)

            let existingDraft = try? decodeManifest(at: directory.appendingPathComponent("manifest.json"))
            if let existingDraft, existingDraft.ownerProfileID != ownerProfileID {
                throw CommunityPostDraftError.ownerMismatch
            }

            let imageRecords = try images.enumerated().map { index, upload in
                let fileName = "\(upload.id.uuidString.lowercased()).\(upload.fileExtension)"
                let thumbnailFileName = "\(upload.id.uuidString.lowercased())-thumb.jpg"
                let fileURL = directory.appendingPathComponent(fileName)
                let thumbnailURL = directory.appendingPathComponent(thumbnailFileName)

                try upload.data.write(to: fileURL, options: .atomic)
                let thumbnail = try upload.thumbnailUpload()
                try thumbnail.data.write(to: thumbnailURL, options: .atomic)
                try applyFileProtection(to: fileURL)
                try applyFileProtection(to: thumbnailURL)

                return CommunityPostDraftImageRecord(
                    id: upload.id,
                    fileName: fileName,
                    thumbnailFileName: thumbnailFileName,
                    mimeType: upload.mimeType,
                    fileExtension: upload.fileExtension,
                    width: upload.width,
                    height: upload.height,
                    sortOrder: index
                )
            }

            let attachmentRecords = try attachments.enumerated().map { index, upload in
                let fileName = "\(upload.id.uuidString.lowercased()).\(upload.fileExtension)"
                let destination = directory.appendingPathComponent(fileName)
                if upload.localURL.standardizedFileURL != destination.standardizedFileURL {
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.copyItem(at: upload.localURL, to: destination)
                } else if !fileManager.fileExists(atPath: destination.path) {
                    throw CommunityPostDraftError.missingAttachment(upload.displayName)
                }
                try applyFileProtection(to: destination)

                return CommunityPostDraftAttachmentRecord(
                    id: upload.id,
                    fileName: fileName,
                    displayName: upload.displayName,
                    contentType: upload.contentType,
                    fileExtension: upload.fileExtension,
                    byteSize: upload.byteSize,
                    sortOrder: index
                )
            }

            let now = Date()
            let draft = CommunityPostDraft(
                id: id,
                ownerProfileID: ownerProfileID,
                createdAt: existingDraft?.createdAt ?? now,
                updatedAt: now,
                input: input,
                images: imageRecords,
                attachments: attachmentRecords
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(draft)
            let manifestURL = directory.appendingPathComponent("manifest.json")
            try data.write(to: manifestURL, options: .atomic)
            try applyFileProtection(to: manifestURL)
            try removeOrphanedMedia(in: directory, draft: draft)

            logger.info(
                "Saved community draft id=\(id.uuidString, privacy: .public) images=\(images.count, privacy: .public) attachments=\(attachments.count, privacy: .public)"
            )
            let payload = try loadDraft(id: id, ownerProfileID: ownerProfileID)
            NotificationCenter.default.post(
                name: .communityPostDraftsDidChange,
                object: ownerProfileID
            )
            return payload
        } catch let error as CommunityPostDraftError {
            throw error
        } catch {
            logger.error(
                "Save community draft failed id=\(id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw CommunityPostDraftError.storageFailure(error.localizedDescription)
        }
    }

    func deleteDraft(id: UUID, ownerProfileID: UUID) throws {
        let directory = draftDirectory(id: id, ownerProfileID: ownerProfileID)
        guard fileManager.fileExists(atPath: directory.path) else { return }

        do {
            let draft = try decodeManifest(at: directory.appendingPathComponent("manifest.json"))
            guard draft.ownerProfileID == ownerProfileID else {
                throw CommunityPostDraftError.ownerMismatch
            }
            try fileManager.removeItem(at: directory)
            logger.info("Deleted community draft id=\(id.uuidString, privacy: .public)")
            NotificationCenter.default.post(
                name: .communityPostDraftsDidChange,
                object: ownerProfileID
            )
        } catch let error as CommunityPostDraftError {
            throw error
        } catch {
            throw CommunityPostDraftError.storageFailure(error.localizedDescription)
        }
    }

    func thumbnailData(
        draftID: UUID,
        ownerProfileID: UUID,
        imageID: UUID
    ) throws -> Data {
        let directory = draftDirectory(id: draftID, ownerProfileID: ownerProfileID)
        let draft = try decodeManifest(at: directory.appendingPathComponent("manifest.json"))
        guard draft.ownerProfileID == ownerProfileID else {
            throw CommunityPostDraftError.ownerMismatch
        }
        guard let record = draft.images.first(where: { $0.id == imageID }) else {
            throw CommunityPostDraftError.missingImage(imageID.uuidString)
        }
        let url = directory.appendingPathComponent(record.thumbnailFileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CommunityPostDraftError.missingImage(record.thumbnailFileName)
        }
        return try Data(contentsOf: url)
    }

    private func decodeManifest(at url: URL) throws -> CommunityPostDraft {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CommunityPostDraftError.draftNotFound
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(CommunityPostDraft.self, from: Data(contentsOf: url))
        } catch {
            logger.error("Decode community draft manifest failed url=\(url.lastPathComponent, privacy: .public)")
            throw CommunityPostDraftError.corruptManifest
        }
    }

    private func removeOrphanedMedia(in directory: URL, draft: CommunityPostDraft) throws {
        let retainedNames = Set(
            ["manifest.json"]
                + draft.images.flatMap { [$0.fileName, $0.thumbnailFileName] }
                + draft.attachments.map(\.fileName)
        )
        for url in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) where !retainedNames.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
        }
    }

    private func ownerDirectory(_ ownerProfileID: UUID) -> URL {
        rootDirectory.appendingPathComponent(ownerProfileID.uuidString.lowercased(), isDirectory: true)
    }

    private func draftDirectory(id: UUID, ownerProfileID: UUID) -> URL {
        ownerDirectory(ownerProfileID)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func applyFileProtection(to url: URL) throws {
        guard appliesFileProtection else { return }
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }
}

extension Notification.Name {
    static let communityPostDraftsDidChange = Notification.Name("CommunityPostDraftsDidChange")
}
