import Foundation
import os
import UniformTypeIdentifiers

nonisolated enum ExternalImportL10n {
    private static let appGroupIdentifier = "group.com.isaachuo.leafy"
    private static let languagePreferenceKey = "leafy.appLanguagePreference"

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let rawValue = UserDefaults(suiteName: appGroupIdentifier)?
            .string(forKey: languagePreferenceKey)
        let localizationIdentifier: String
        switch rawValue {
        case "en-US":
            localizationIdentifier = "en-US"
        case "zh-Hans":
            localizationIdentifier = "zh-Hans"
        default:
            let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
            localizationIdentifier = preferredLanguage.hasPrefix("en") ? "en-US" : "zh-Hans"
        }

        let localizedFormat = String(
            localized: String.LocalizationValue(key),
            bundle: .main,
            locale: Locale(identifier: localizationIdentifier)
        )
        return String(
            format: localizedFormat,
            locale: Locale(identifier: localizationIdentifier),
            arguments: arguments
        )
    }
}

enum ExternalLearningMaterialImportError: LocalizedError, Equatable {
    case appGroupUnavailable
    case unsupportedFile(String)
    case emptyBatch
    case missingBatch(UUID)
    case missingStagedFile(String)
    case tooManyFiles
    case fileTooLarge(String)
    case batchTooLarge
    case insufficientDiskSpace
    case invalidManifest
    case cleanupFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return ExternalImportL10n.text("这批外部文件暂存记录已损坏，请重新导入。")
        case .cleanupFailed(let original, let cleanup):
            return original + "\n" + ExternalImportL10n.text("暂存文件清理失败：%@", cleanup)
        case .appGroupUnavailable:
            return ExternalImportL10n.text("无法访问 MyLeafy 共享暂存目录。")
        case .unsupportedFile(let filename):
            return ExternalImportL10n.text("暂不支持导入 %@。请使用 PDF、图片、Word 或 PPT 文件。", filename)
        case .emptyBatch:
            return ExternalImportL10n.text("没有找到可导入的文件。请使用 PDF、图片、Word 或 PPT 文件。")
        case .missingBatch:
            return ExternalImportL10n.text("这批外部文件暂存记录已失效，请重新从微信或 QQ 打开。")
        case .missingStagedFile(let filename):
            return ExternalImportL10n.text("无法找到暂存文件 %@，请重新导入。", filename)
        case .tooManyFiles:
            return ExternalImportL10n.text("每次最多导入 10 个文件。")
        case .fileTooLarge(let filename):
            return ExternalImportL10n.text("%@ 超过 25 MB，无法导入。", filename)
        case .batchTooLarge:
            return ExternalImportL10n.text("单次导入总大小不能超过 100 MB。")
        case .insufficientDiskSpace:
            return ExternalImportL10n.text("设备可用空间不足，无法暂存这些文件。")
        }
    }
}

nonisolated enum ExternalLearningMaterialImportSource: String, Codable, Equatable, Sendable {
    case openIn
    case shareExtension
}

nonisolated struct ExternalLearningMaterialImportItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalFilename: String
    let stagedFilename: String
    let contentTypeIdentifier: String
    let byteCount: Int64
}

nonisolated struct ExternalLearningMaterialImportManifest: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: ExternalLearningMaterialImportSource
    let createdAt: Date
    var items: [ExternalLearningMaterialImportItem]

    init(
        id: UUID = UUID(),
        source: ExternalLearningMaterialImportSource,
        createdAt: Date = Date(),
        items: [ExternalLearningMaterialImportItem]
    ) {
        self.id = id
        self.source = source
        self.createdAt = createdAt
        self.items = items
    }
}

enum ExternalLearningMaterialImport {
    static let appGroupIdentifier = "group.com.isaachuo.leafy"
    static let callbackScheme = "leafy"
    static let callbackHost = "learning-material-import"
    static let stagingDirectoryName = "ExternalLearningMaterialImports"
    static let manifestFilename = "manifest.json"
    static let maximumItemCount = 10
    static let maximumFileBytes: Int64 = 25 * 1024 * 1024
    static let maximumBatchBytes: Int64 = 100 * 1024 * 1024
    static let maximumDataFallbackBytes = 10 * 1024 * 1024
    static let stagingLifetime: TimeInterval = 24 * 60 * 60

    static let supportedContentTypes: [UTType] = [
        .pdf,
        .image,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "ppt") ?? .data,
        UTType(filenameExtension: "pptx") ?? .data
    ]

    static let supportedContentTypeIdentifiers: [String] = supportedContentTypes.map(\.identifier)

    static func allowsDataRepresentationFallback(after error: Error) -> Bool {
        let providerError = error as NSError
        // NSItemProviderItemUnavailableError / NSItemProviderUnavailableCoercionError.
        return providerError.domain == NSItemProvider.errorDomain && [-1000, -1200].contains(providerError.code)
    }

    static func callbackURL(for batchID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = callbackHost
        components.queryItems = [
            URLQueryItem(name: "batch", value: batchID.uuidString)
        ]
        return components.url ?? URL(string: "\(callbackScheme)://\(callbackHost)?batch=\(batchID.uuidString)")!
    }

    static func batchID(from url: URL) -> UUID? {
        guard url.scheme == callbackScheme, url.host == callbackHost else { return nil }
        let batchValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "batch" })?
            .value
        return batchValue.flatMap(UUID.init(uuidString:))
    }

    static func isSupported(filename: String, contentTypeIdentifier: String? = nil) -> Bool {
        let lowercasedFilename = filename.lowercased()
        if lowercasedFilename.hasSuffix(".doc") ||
            lowercasedFilename.hasSuffix(".docx") ||
            lowercasedFilename.hasSuffix(".ppt") ||
            lowercasedFilename.hasSuffix(".pptx") {
            return true
        }

        guard let contentType = contentType(filename: filename, contentTypeIdentifier: contentTypeIdentifier) else {
            return false
        }
        if contentType.conforms(to: .pdf) || contentType.conforms(to: .image) {
            return true
        }

        let identifier = contentType.identifier.lowercased()
        return identifier.contains("word") ||
            identifier.contains("powerpoint") ||
            identifier.contains("presentation")
    }

    static func contentType(filename: String, contentTypeIdentifier: String? = nil) -> UTType? {
        if let contentTypeIdentifier,
           let type = UTType(contentTypeIdentifier) {
            return type
        }
        let fileExtension = (filename as NSString).pathExtension
        guard !fileExtension.isEmpty else { return nil }
        return UTType(filenameExtension: fileExtension)
    }

    static func normalizedFilename(_ filename: String, fallback: String = ExternalImportL10n.text("学习资料")) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct ExternalLearningMaterialImportStore {
    private static let logger = Logger(subsystem: "com.isaachuo.leafy", category: "ExternalImport")
    let rootDirectory: URL
    let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func appGroupStore(fileManager: FileManager = .default) throws -> ExternalLearningMaterialImportStore {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ExternalLearningMaterialImport.appGroupIdentifier
        ) else {
            throw ExternalLearningMaterialImportError.appGroupUnavailable
        }
        return ExternalLearningMaterialImportStore(
            rootDirectory: container.appendingPathComponent(
                ExternalLearningMaterialImport.stagingDirectoryName,
                isDirectory: true
            ),
            fileManager: fileManager
        )
    }

    func makeBatch(
        from urls: [URL],
        source: ExternalLearningMaterialImportSource,
        id: UUID = UUID()
    ) throws -> ExternalLearningMaterialImportManifest {
        guard urls.count <= ExternalLearningMaterialImport.maximumItemCount else {
            throw ExternalLearningMaterialImportError.tooManyFiles
        }
        var items: [ExternalLearningMaterialImportItem] = []
        do {
            try prepareBatchDirectory(id)
            for url in urls {
                items.append(try stageFile(from: url, batchID: id))
                try validateBatch(items)
            }
            guard !items.isEmpty else { throw ExternalLearningMaterialImportError.emptyBatch }
            let manifest = ExternalLearningMaterialImportManifest(id: id, source: source, items: items)
            try writeManifest(manifest)
            return manifest
        } catch {
            throw failure(error, cleaningBatch: id)
        }
    }

    func failure(_ original: Error, cleaningBatch id: UUID) -> Error {
        do {
            try removeBatch(id)
            return original
        } catch {
            return ExternalLearningMaterialImportError.cleanupFailed(original.localizedDescription, error.localizedDescription)
        }
    }

    func prepareBatchDirectory(_ batchID: UUID) throws {
        try fileManager.createDirectory(
            at: batchDirectoryURL(for: batchID),
            withIntermediateDirectories: true
        )
    }

    func stageFile(
        from sourceURL: URL,
        batchID: UUID,
        sourceContentTypeIdentifier: String? = nil,
        originalFilename: String? = nil,
        itemID: UUID = UUID()
    ) throws -> ExternalLearningMaterialImportItem {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let filename = ExternalLearningMaterialImport.normalizedFilename(
            originalFilename ?? sourceURL.lastPathComponent
        )
        let contentTypeIdentifier = sourceContentTypeIdentifier ??
            ExternalLearningMaterialImport.contentType(filename: filename)?.identifier ??
            sourceURL.resourceContentType?.identifier ??
            UTType.data.identifier

        guard ExternalLearningMaterialImport.isSupported(
            filename: filename,
            contentTypeIdentifier: contentTypeIdentifier
        ) else {
            throw ExternalLearningMaterialImportError.unsupportedFile(filename)
        }

        let sourceBytes = try byteCount(for: sourceURL)
        guard sourceBytes <= ExternalLearningMaterialImport.maximumFileBytes else {
            throw ExternalLearningMaterialImportError.fileTooLarge(filename)
        }
        try requireAvailableCapacity(sourceBytes)

        try prepareBatchDirectory(batchID)
        let stagedFilename = stagedFilename(for: itemID, originalFilename: filename)
        let destinationURL = batchDirectoryURL(for: batchID).appendingPathComponent(stagedFilename)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        let copiedBytes = try byteCount(for: destinationURL)
        guard copiedBytes <= ExternalLearningMaterialImport.maximumFileBytes else {
            throw ExternalLearningMaterialImportError.fileTooLarge(filename)
        }

        return ExternalLearningMaterialImportItem(
            id: itemID,
            originalFilename: filename,
            stagedFilename: stagedFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: copiedBytes
        )
    }

    func stageData(
        _ data: Data,
        batchID: UUID,
        originalFilename: String,
        contentTypeIdentifier: String,
        itemID: UUID = UUID()
    ) throws -> ExternalLearningMaterialImportItem {
        let filename = ExternalLearningMaterialImport.normalizedFilename(originalFilename)
        guard ExternalLearningMaterialImport.isSupported(
            filename: filename,
            contentTypeIdentifier: contentTypeIdentifier
        ) else {
            throw ExternalLearningMaterialImportError.unsupportedFile(filename)
        }

        guard !data.isEmpty else { throw ExternalLearningMaterialImportError.emptyBatch }
        guard data.count <= ExternalLearningMaterialImport.maximumDataFallbackBytes,
              Int64(data.count) <= ExternalLearningMaterialImport.maximumFileBytes else {
            throw ExternalLearningMaterialImportError.fileTooLarge(filename)
        }
        try requireAvailableCapacity(Int64(data.count))

        try prepareBatchDirectory(batchID)
        let stagedFilename = stagedFilename(for: itemID, originalFilename: filename)
        let destinationURL = batchDirectoryURL(for: batchID).appendingPathComponent(stagedFilename)
        try data.write(to: destinationURL, options: [.atomic])

        return ExternalLearningMaterialImportItem(
            id: itemID,
            originalFilename: filename,
            stagedFilename: stagedFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: Int64(data.count)
        )
    }

    func writeManifest(_ manifest: ExternalLearningMaterialImportManifest) throws {
        try validateBatch(manifest.items)
        try prepareBatchDirectory(manifest.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = Self.preciseISO8601DateEncodingStrategy
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(for: manifest.id), options: [.atomic])
    }

    func loadManifest(id: UUID) throws -> ExternalLearningMaterialImportManifest {
        let url = manifestURL(for: id)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ExternalLearningMaterialImportError.missingBatch(id)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = Self.preciseISO8601DateDecodingStrategy
        let manifest = try decoder.decode(
            ExternalLearningMaterialImportManifest.self,
            from: Data(contentsOf: url)
        )
        guard manifest.id == id else { throw ExternalLearningMaterialImportError.invalidManifest }
        try validateBatch(manifest.items)
        return manifest
    }

    func pendingManifests() throws -> [ExternalLearningMaterialImportManifest] {
        removeExpiredBatches()
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
        let batchDirectories = try fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
        return try batchDirectories.compactMap { directory in
            guard let batchID = UUID(uuidString: directory.lastPathComponent),
                  fileManager.fileExists(atPath: manifestURL(for: batchID).path) else { return nil }
            return try loadManifest(id: batchID)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func stagedFileURL(for item: ExternalLearningMaterialImportItem, in manifest: ExternalLearningMaterialImportManifest) throws -> URL {
        try validateBatch(manifest.items)
        guard manifest.items.contains(item) else { throw ExternalLearningMaterialImportError.invalidManifest }
        let directory = batchDirectoryURL(for: manifest.id).resolvingSymlinksInPath().standardizedFileURL
        let url = directory.appendingPathComponent(item.stagedFilename).resolvingSymlinksInPath().standardizedFileURL
        guard url.deletingLastPathComponent() == directory else { throw ExternalLearningMaterialImportError.invalidManifest }
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ExternalLearningMaterialImportError.missingStagedFile(item.originalFilename)
        }
        let actualBytes = try byteCount(for: url)
        guard actualBytes == item.byteCount, actualBytes <= ExternalLearningMaterialImport.maximumFileBytes else {
            throw ExternalLearningMaterialImportError.invalidManifest
        }
        return url
    }

    func removeBatch(_ id: UUID) throws {
        let url = batchDirectoryURL(for: id)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.removeItem(at: url)
        }
    }

    func removeExpiredBatches(now: Date = Date()) {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            let manifestDate = UUID(uuidString: directory.lastPathComponent)
                .flatMap { try? loadManifest(id: $0).createdAt }
            let creationDate = try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate
            let referenceDate = manifestDate ?? creationDate ?? .distantPast
            if now.timeIntervalSince(referenceDate) > ExternalLearningMaterialImport.stagingLifetime {
                do { try fileManager.removeItem(at: directory) }
                catch { Self.logger.error("Expired import cleanup failed: \(error.localizedDescription, privacy: .private)") }
            }
        }
    }

    func batchDirectoryURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func manifestURL(for id: UUID) -> URL {
        batchDirectoryURL(for: id).appendingPathComponent(ExternalLearningMaterialImport.manifestFilename)
    }

    private func stagedFilename(for itemID: UUID, originalFilename: String) -> String {
        let fileExtension = (originalFilename as NSString).pathExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
        guard !fileExtension.isEmpty else { return itemID.uuidString }
        return "\(itemID.uuidString).\(fileExtension)"
    }

    private func byteCount(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Int64(size)
    }

    private func validateBatch(_ items: [ExternalLearningMaterialImportItem]) throws {
        guard items.count <= ExternalLearningMaterialImport.maximumItemCount else {
            throw ExternalLearningMaterialImportError.tooManyFiles
        }
        guard !items.isEmpty else { throw ExternalLearningMaterialImportError.emptyBatch }
        var ids = Set<UUID>()
        var filenames = Set<String>()
        for item in items {
            guard ids.insert(item.id).inserted, filenames.insert(item.stagedFilename).inserted,
                  item.byteCount > 0, item.byteCount <= ExternalLearningMaterialImport.maximumFileBytes,
                  !item.stagedFilename.isEmpty, item.stagedFilename != ".", item.stagedFilename != "..",
                  !item.stagedFilename.contains("/"), !item.stagedFilename.contains("\\"),
                  ExternalLearningMaterialImport.isSupported(filename: item.originalFilename, contentTypeIdentifier: item.contentTypeIdentifier) else {
                throw ExternalLearningMaterialImportError.invalidManifest
            }
        }
        let total = items.reduce(Int64(0)) { $0 + $1.byteCount }
        guard total <= ExternalLearningMaterialImport.maximumBatchBytes else {
            throw ExternalLearningMaterialImportError.batchTooLarge
        }
    }

    private func requireAvailableCapacity(_ additionalBytes: Int64) throws {
        var existingDirectory = rootDirectory
        while !fileManager.fileExists(atPath: existingDirectory.path), existingDirectory.path != "/" {
            existingDirectory.deleteLastPathComponent()
        }
        let values = try existingDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values.volumeAvailableCapacityForImportantUsage,
           capacity < additionalBytes + 20 * 1024 * 1024 {
            throw ExternalLearningMaterialImportError.insufficientDiskSpace
        }
    }

    private static var preciseISO8601DateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
    }

    private static var preciseISO8601DateDecodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }

            let value = try container.decode(String.self)

            let preciseFormatter = ISO8601DateFormatter()
            preciseFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = preciseFormatter.date(from: value) {
                return date
            }

            let legacyFormatter = ISO8601DateFormatter()
            if let date = legacyFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
    }
}

private extension URL {
    var resourceContentType: UTType? {
        (try? resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }
}
