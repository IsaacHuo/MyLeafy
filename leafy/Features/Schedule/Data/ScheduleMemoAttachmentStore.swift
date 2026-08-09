import Foundation
import UniformTypeIdentifiers

enum ScheduleMemoAttachmentStoreError: LocalizedError {
    case unsupportedType
    case unreadableFile
    case tooManyAttachments(maximum: Int)
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "仅支持 PDF、Word、PowerPoint、Excel、Markdown 和纯文本文件。"
        case .unreadableFile:
            return "无法读取这个文件。"
        case .tooManyAttachments(let maximum):
            return "一条随记最多添加 \(maximum) 个附件。"
        case .copyFailed:
            return "附件保存失败，请重试。"
        }
    }
}

enum ScheduleMemoAttachmentStore {
    struct StoredFile: Equatable, Sendable {
        let id: UUID
        let originalFilename: String
        let localFilename: String
        let contentTypeIdentifier: String
    }

    static let maximumAttachmentCount = 3

    static let allowedContentTypes: [UTType] = [
        .pdf,
        .plainText,
        .rtf
    ] + ["md", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "csv"]
        .compactMap { UTType(filenameExtension: $0) }

    private static let allowedExtensions: Set<String> = [
        "pdf", "txt", "text", "md", "markdown", "rtf",
        "doc", "docx", "ppt", "pptx", "xls", "xlsx", "csv"
    ]

    static func importFile(
        from sourceURL: URL,
        contentTypeIdentifier: String? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) throws -> StoredFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let contentType = try validatedContentType(
            for: sourceURL,
            contentTypeIdentifier: contentTypeIdentifier
        )
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: sourceURL.path(percentEncoded: false)) else {
            throw ScheduleMemoAttachmentStoreError.unreadableFile
        }

        let directory = directoryURL(identity: identity)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )

            let id = UUID()
            let extensionText = sourceURL.pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let localFilename = extensionText.isEmpty
                ? id.uuidString
                : "\(id.uuidString).\(extensionText.lowercased())"
            let destinationURL = directory.appendingPathComponent(localFilename, isDirectory: false)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destinationURL.path(percentEncoded: false)
            )

            return StoredFile(
                id: id,
                originalFilename: sanitizedFilename(sourceURL.lastPathComponent),
                localFilename: localFilename,
                contentTypeIdentifier: contentType.identifier
            )
        } catch let error as ScheduleMemoAttachmentStoreError {
            throw error
        } catch {
            throw ScheduleMemoAttachmentStoreError.copyFailed
        }
    }

    static func importData(
        _ data: Data,
        originalFilename: String,
        contentTypeIdentifier: String? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) throws -> StoredFile {
        guard !data.isEmpty else {
            throw ScheduleMemoAttachmentStoreError.unreadableFile
        }

        let safeOriginalFilename = sanitizedFilename(originalFilename)
        let extensionText = URL(fileURLWithPath: safeOriginalFilename).pathExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let contentType = try validatedContentType(
            fileExtension: extensionText,
            contentTypeIdentifier: contentTypeIdentifier
        )
        let fileManager = FileManager.default
        let directory = directoryURL(identity: identity)

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )

            let id = UUID()
            let localFilename = extensionText.isEmpty
                ? id.uuidString
                : "\(id.uuidString).\(extensionText)"
            let destinationURL = directory.appendingPathComponent(localFilename, isDirectory: false)
            try data.write(to: destinationURL, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destinationURL.path(percentEncoded: false)
            )

            return StoredFile(
                id: id,
                originalFilename: safeOriginalFilename,
                localFilename: localFilename,
                contentTypeIdentifier: contentType.identifier
            )
        } catch {
            throw ScheduleMemoAttachmentStoreError.copyFailed
        }
    }

    static func importFiles(
        from sourceURLs: [URL],
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity(),
        maximumCount: Int = maximumAttachmentCount
    ) throws -> [StoredFile] {
        guard sourceURLs.count <= maximumCount else {
            throw ScheduleMemoAttachmentStoreError.tooManyAttachments(maximum: maximumCount)
        }
        guard !sourceURLs.isEmpty else { return [] }

        var stored: [StoredFile] = []
        do {
            for sourceURL in sourceURLs {
                stored.append(try importFile(from: sourceURL, identity: identity))
            }
            return stored
        } catch {
            try? deleteFiles(named: stored.map(\.localFilename), identity: identity)
            throw error
        }
    }

    static func fileURL(
        named localFilename: String,
        in directory: URL? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) -> URL? {
        let url = (directory ?? directoryURL(identity: identity)).appendingPathComponent(localFilename, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    static func fileURL(
        for attachment: ScheduleMemoAttachment,
        in directory: URL? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) -> URL? {
        fileURL(named: attachment.localFilename, in: directory, identity: identity)
    }

    static func dataURL(
        for attachment: ScheduleMemoAttachment,
        in directory: URL? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) -> URL? {
        fileURL(for: attachment, in: directory, identity: identity)
    }

    static func deleteFile(
        named localFilename: String,
        in directory: URL? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) throws {
        guard let url = fileURL(named: localFilename, in: directory, identity: identity) else { return }
        try deleteFile(at: url)
    }

    static func deleteFiles(
        named localFilenames: [String],
        in directory: URL? = nil,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity()
    ) throws {
        for localFilename in localFilenames {
            try deleteFile(named: localFilename, in: directory, identity: identity)
        }
    }

    static func deleteFile(at url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: url)
    }

    static func deleteAllFiles(
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity(),
        directory: URL? = nil
    ) throws {
        let url = directory ?? directoryURL(identity: identity)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try deleteFile(at: url)
    }

    static func directoryURL(identity: CampusIdentity? = CampusIdentityStore.currentIdentity()) -> URL {
        if let identity,
           let scopedStore = CampusStoreScope.scopedStoreURL(for: identity) {
            return scopedStore.deletingLastPathComponent()
                .appendingPathComponent("ScheduleMemoAttachments", isDirectory: true)
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScheduleMemoAttachments", isDirectory: true)
    }

    private static func validatedContentType(
        for sourceURL: URL,
        contentTypeIdentifier: String?
    ) throws -> UTType {
        let extensionText = sourceURL.pathExtension.lowercased()
        let contentType = try validatedContentType(
            fileExtension: extensionText,
            contentTypeIdentifier: contentTypeIdentifier,
            fallback: try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        )
        return contentType
    }

    private static func validatedContentType(
        fileExtension: String,
        contentTypeIdentifier: String?,
        fallback: UTType? = nil
    ) throws -> UTType {
        let candidates = [
            contentTypeIdentifier.flatMap { UTType($0) },
            UTType(filenameExtension: fileExtension),
            fallback
        ].compactMap { $0 }
        guard let contentType = candidates.first(where: { candidate in
            allowedContentTypes.contains(where: { candidate.conforms(to: $0) })
        }) else {
            throw ScheduleMemoAttachmentStoreError.unsupportedType
        }

        guard fileExtension.isEmpty || allowedExtensions.contains(fileExtension)
        else {
            throw ScheduleMemoAttachmentStoreError.unsupportedType
        }
        return contentType
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0.value != 0x2F && $0.value != 0x5C
        }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "附件" : cleaned).prefix(120))
    }
}
