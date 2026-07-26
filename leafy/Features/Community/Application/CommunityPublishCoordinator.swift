import Combine
import Foundation
import Network
import OSLog
import Supabase
import UIKit

nonisolated enum CommunityPublishTaskState: String, Codable, Hashable, Sendable {
    case queued
    case creatingPost
    case uploading
    case validating
    case publishing
    case published
    case failed
    case cancelling
    case cancelled

    var title: String {
        switch self {
        case .queued: return "排队中"
        case .creatingPost: return "正在创建帖子"
        case .uploading: return "正在上传"
        case .validating: return "正在校验"
        case .publishing: return "正在发布"
        case .published: return "发布成功"
        case .failed: return "发布失败"
        case .cancelling: return "正在取消"
        case .cancelled: return "已取消"
        }
    }

    var isTerminal: Bool {
        self == .published || self == .cancelled
    }
}

nonisolated enum CommunityPublishMediaKind: String, Codable, Hashable, Sendable {
    case image
    case attachment
}

nonisolated enum CommunityPublishCapabilityRequirements {
    static func requiredRPCs(for mediaKinds: Set<CommunityPublishMediaKind>) -> [String] {
        var names = ["create_community_post_v4"]
        if mediaKinds.contains(.image) {
            names.append("attach_community_post_image_v1")
        }
        if mediaKinds.contains(.attachment) {
            names.append("attach_community_post_attachment_v1")
        }
        return names
    }

    static func requiredEdgeFunctions(for mediaKinds: Set<CommunityPublishMediaKind>) -> [String] {
        var names: [String] = []
        if mediaKinds.contains(.image) {
            names.append("community-validate-upload")
        }
        if mediaKinds.contains(.attachment) {
            names.append("community-validate-attachment")
        }
        return names
    }

    static func missingRPCs(
        in capabilities: BackendCapabilities,
        mediaKinds: Set<CommunityPublishMediaKind>
    ) -> [String] {
        requiredRPCs(for: mediaKinds).filter { !capabilities.supportsRPC($0) }
    }

    static func missingEdgeFunctions(
        in capabilities: BackendCapabilities,
        mediaKinds: Set<CommunityPublishMediaKind>
    ) -> [String] {
        requiredEdgeFunctions(for: mediaKinds).filter { !capabilities.edgeFunctions.contains($0) }
    }

    static func isSatisfied(
        by capabilities: BackendCapabilities,
        mediaKinds: Set<CommunityPublishMediaKind>
    ) -> Bool {
        missingRPCs(in: capabilities, mediaKinds: mediaKinds).isEmpty
            && missingEdgeFunctions(in: capabilities, mediaKinds: mediaKinds).isEmpty
    }

    static func refreshingIfNeeded(
        _ capabilities: BackendCapabilities,
        mediaKinds: Set<CommunityPublishMediaKind>,
        refresh: () async throws -> BackendCapabilities
    ) async rethrows -> BackendCapabilities {
        guard !isSatisfied(by: capabilities, mediaKinds: mediaKinds) else { return capabilities }
        return try await refresh()
    }
}

nonisolated struct CommunityPublishMediaItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: CommunityPublishMediaKind
    let displayName: String
    let contentType: String
    let fileExtension: String
    let byteSize: Int
    let sortOrder: Int
    let localRelativePath: String
    let thumbnailRelativePath: String?
    var remotePath: String?
    var thumbnailRemotePath: String?
    var fullUploaded: Bool
    var thumbnailUploaded: Bool
    var validated: Bool
    var progress: Double
    var tusUploadURL: URL?
    var tusOffset: Int64
    var errorMessage: String?
}

nonisolated struct CommunityPublishTask: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let input: CreatePostInput
    let createdAt: Date
    var updatedAt: Date
    var state: CommunityPublishTaskState
    var media: [CommunityPublishMediaItem]
    var authorID: UUID?
    var errorMessage: String?
    var completedAt: Date?
    var automaticallyRetryable: Bool? = nil

    var progress: Double {
        switch state {
        case .queued:
            return 0
        case .creatingPost:
            return 0.05
        case .uploading:
            guard !media.isEmpty else { return 0.7 }
            return 0.1 + media.map(\.progress).reduce(0, +) / Double(media.count) * 0.65
        case .validating:
            guard !media.isEmpty else { return 0.85 }
            let completed = Double(media.filter(\.validated).count) / Double(media.count)
            return 0.75 + completed * 0.15
        case .publishing:
            return 0.95
        case .published:
            return 1
        case .failed, .cancelling, .cancelled:
            return media.isEmpty ? 0 : media.map(\.progress).reduce(0, +) / Double(media.count)
        }
    }

    var progressDetail: String {
        guard !media.isEmpty else { return state.title }
        let finished = media.filter(\.validated).count
        switch state {
        case .uploading:
            return "上传 \(min(finished + 1, media.count))/\(media.count)"
        case .validating:
            return "校验 \(finished)/\(media.count)"
        default:
            return state.title
        }
    }
}

nonisolated struct CommunityBackgroundTransferDescriptor: Codable, Hashable, Sendable {
    enum Component: String, Codable, Sendable {
        case imageFull
        case imageThumbnail
        case attachmentChunk
    }

    let publishTaskID: UUID
    let mediaID: UUID
    let component: Component
    let offset: Int64
    let byteCount: Int64

    var key: String {
        [
            publishTaskID.uuidString,
            mediaID.uuidString,
            component.rawValue,
            String(offset)
        ].joined(separator: ":")
    }

    var encodedDescription: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return data.base64EncodedString()
    }

    static func decode(_ value: String?) -> Self? {
        guard let value,
              let data = Data(base64Encoded: value) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

nonisolated struct CommunityBackgroundTransferResult: Sendable {
    let statusCode: Int
}

nonisolated struct CommunityBackgroundTransferError: LocalizedError, Sendable {
    let message: String
    let statusCode: Int?

    var errorDescription: String? { message }
}

nonisolated final class CommunityBackgroundSessionStore: @unchecked Sendable {
    static let shared = CommunityBackgroundSessionStore()

    private let lock = NSLock()
    private var storedSession: URLSession?

    private init() {}

    func session(delegate: URLSessionDelegate) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let storedSession {
            return storedSession
        }

        let configuration = URLSessionConfiguration.background(
            withIdentifier: CommunityBackgroundTransferManager.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        storedSession = session
        return session
    }
}

nonisolated final class CommunityBackgroundTransferManager: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = CommunityBackgroundTransferManager()
    static let sessionIdentifier = "com.isaachuo.leafy.community-publish"

    private let lock = NSLock()
    private var continuations: [String: CheckedContinuation<CommunityBackgroundTransferResult, Error>] = [:]
    private var cachedResults: [String: Result<CommunityBackgroundTransferResult, Error>] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    var progressHandler: (@Sendable (CommunityBackgroundTransferDescriptor, Double) -> Void)?

    private var session: URLSession {
        CommunityBackgroundSessionStore.shared.session(delegate: self)
    }

    private override init() {
        super.init()
        _ = session
    }

    func reconnect() {
        session.getAllTasks { _ in }
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        backgroundCompletionHandler = handler
        lock.unlock()
        reconnect()
    }

    func upload(
        request: URLRequest,
        fileURL: URL,
        descriptor: CommunityBackgroundTransferDescriptor
    ) async throws -> CommunityBackgroundTransferResult {
        if let cached = takeCachedResult(for: descriptor.key) {
            return try cached.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.getAllTasks { [weak self] tasks in
                guard let self else {
                    continuation.resume(
                        throwing: CommunityBackgroundTransferError(
                            message: "后台上传服务不可用。",
                            statusCode: nil
                        )
                    )
                    return
                }

                self.lock.lock()
                if let cached = self.cachedResults.removeValue(forKey: descriptor.key) {
                    self.lock.unlock()
                    continuation.resume(with: cached)
                    return
                }
                self.continuations[descriptor.key] = continuation
                self.lock.unlock()

                if tasks.contains(where: {
                    CommunityBackgroundTransferDescriptor.decode($0.taskDescription)?.key == descriptor.key
                }) {
                    return
                }

                let task = self.session.uploadTask(with: request, fromFile: fileURL)
                task.taskDescription = descriptor.encodedDescription
                task.countOfBytesClientExpectsToSend = descriptor.byteCount
                task.resume()
            }
        }
    }

    func cancel(publishTaskID: UUID) {
        session.getAllTasks { tasks in
            for task in tasks {
                guard let descriptor = CommunityBackgroundTransferDescriptor.decode(task.taskDescription),
                      descriptor.publishTaskID == publishTaskID else { continue }
                task.cancel()
            }
        }
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didSendBodyData _: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let descriptor = CommunityBackgroundTransferDescriptor.decode(task.taskDescription),
              totalBytesExpectedToSend > 0 else { return }
        progressHandler?(
            descriptor,
            min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        )
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let descriptor = CommunityBackgroundTransferDescriptor.decode(task.taskDescription) else { return }
        let result: Result<CommunityBackgroundTransferResult, Error>
        if let error {
            result = .failure(error)
        } else if let response = task.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) {
            result = .success(CommunityBackgroundTransferResult(statusCode: response.statusCode))
        } else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
            result = .failure(
                CommunityBackgroundTransferError(
                    message: "后台上传失败（HTTP \(status)）。",
                    statusCode: status
                )
            )
        }

        lock.lock()
        let continuation = continuations.removeValue(forKey: descriptor.key)
        if continuation == nil {
            cachedResults[descriptor.key] = result
        }
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        lock.lock()
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        lock.unlock()
        DispatchQueue.main.async {
            handler?()
        }
    }

    private func takeCachedResult(
        for key: String
    ) -> Result<CommunityBackgroundTransferResult, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return cachedResults.removeValue(forKey: key)
    }
}

@MainActor
final class CommunityPublishCoordinator: ObservableObject {
    static let shared = CommunityPublishCoordinator()

    @Published private(set) var tasks: [CommunityPublishTask] = []

    private let logger = Logger(subsystem: "com.isaachuo.leafy", category: "CommunityPublish")
    private let fileManager = FileManager.default
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.isaachuo.leafy.community-publish-network")
    private let notificationReadKey = "community.publish.notification.read.ids"
    private let notificationDismissedKey = "community.publish.notification.dismissed.ids"
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var hasConfigured = false

    private init() {
        tasks = loadPersistedTasks()
        CommunityBackgroundTransferManager.shared.progressHandler = { descriptor, progress in
            Task { @MainActor in
                CommunityPublishCoordinator.shared.applyProgress(
                    descriptor: descriptor,
                    progress: progress
                )
            }
        }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                self?.resumeAutomaticallyRetryableTasks()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    var activeTasks: [CommunityPublishTask] {
        tasks.filter { !$0.state.isTerminal && $0.state != .cancelled }
    }

    var visibleTasks: [CommunityPublishTask] {
        tasks.filter {
            if $0.state == .published, let completedAt = $0.completedAt {
                return Date().timeIntervalSince(completedAt) < 8
            }
            return $0.state != .cancelled
        }
    }

    var notificationItems: [NotificationFeedItem] {
        let readIDs = storedNotificationIDs(forKey: notificationReadKey)
        let dismissedIDs = storedNotificationIDs(forKey: notificationDismissedKey)
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return tasks
            .filter {
                ($0.state == .published || $0.state == .failed)
                    && $0.updatedAt >= cutoff
                    && !dismissedIDs.contains($0.id)
            }
            .map {
                .publication(
                    CommunityPublishNotification(
                        task: $0,
                        isRead: readIDs.contains($0.id)
                    )
                )
            }
    }

    func markNotificationRead(taskID: UUID) {
        updateStoredNotificationIDs(forKey: notificationReadKey) { $0.insert(taskID) }
    }

    func dismissNotification(taskID: UUID) {
        updateStoredNotificationIDs(forKey: notificationDismissedKey) { $0.insert(taskID) }
    }

    func configureAndResume() {
        purgeExpiredTasks()
        if !hasConfigured {
            hasConfigured = true
            CommunityBackgroundTransferManager.shared.reconnect()
        }
        resumeAutomaticallyRetryableTasks()
        startQueuedWork()
    }

    @discardableResult
    func enqueue(
        input: CreatePostInput,
        images: [CommunityImageUpload],
        attachments: [CommunityAttachmentUpload]
    ) throws -> UUID {
        guard images.count <= CommunityImageUpload.postImageLimit else {
            throw CommunityServiceError.imageLimitExceeded
        }
        guard attachments.count <= CommunityPostAttachment.postAttachmentLimit else {
            throw CommunityServiceError.edgeFunctionRejected("单条帖子最多上传 2 个附件。")
        }

        let taskID = UUID()
        let directory = try taskDirectory(taskID: taskID, create: true)
        var media: [CommunityPublishMediaItem] = []

        for (index, image) in images.enumerated() {
            let fullName = "\(image.id.uuidString.lowercased()).\(image.fileExtension)"
            let thumbnail = try image.thumbnailUpload()
            let thumbnailName = "\(image.id.uuidString.lowercased())-thumb.\(thumbnail.fileExtension)"
            let fullURL = directory.appendingPathComponent(fullName)
            let thumbnailURL = directory.appendingPathComponent(thumbnailName)
            try image.data.write(to: fullURL, options: .atomic)
            try thumbnail.data.write(to: thumbnailURL, options: .atomic)
            try applyBackgroundFileProtection(to: fullURL)
            try applyBackgroundFileProtection(to: thumbnailURL)
            media.append(
                CommunityPublishMediaItem(
                    id: image.id,
                    kind: .image,
                    displayName: "图片 \(index + 1)",
                    contentType: image.mimeType,
                    fileExtension: image.fileExtension,
                    byteSize: image.data.count,
                    sortOrder: index,
                    localRelativePath: fullName,
                    thumbnailRelativePath: thumbnailName,
                    remotePath: nil,
                    thumbnailRemotePath: nil,
                    fullUploaded: false,
                    thumbnailUploaded: false,
                    validated: false,
                    progress: 0,
                    tusUploadURL: nil,
                    tusOffset: 0,
                    errorMessage: nil
                )
            )
        }

        for (index, attachment) in attachments.enumerated() {
            guard CommunityPostAttachment.supportedExtensions.contains(attachment.fileExtension),
                  attachment.byteSize > 0,
                  attachment.byteSize <= CommunityPostAttachment.maxBytes else {
                throw CommunityServiceError.edgeFunctionRejected("附件格式或大小无效。")
            }
            let localName = "\(attachment.id.uuidString.lowercased()).\(attachment.fileExtension)"
            let destination = directory.appendingPathComponent(localName)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: attachment.localURL, to: destination)
            try applyBackgroundFileProtection(to: destination)
            media.append(
                CommunityPublishMediaItem(
                    id: attachment.id,
                    kind: .attachment,
                    displayName: attachment.displayName,
                    contentType: attachment.contentType,
                    fileExtension: attachment.fileExtension,
                    byteSize: attachment.byteSize,
                    sortOrder: index,
                    localRelativePath: localName,
                    thumbnailRelativePath: nil,
                    remotePath: nil,
                    thumbnailRemotePath: nil,
                    fullUploaded: false,
                    thumbnailUploaded: true,
                    validated: false,
                    progress: 0,
                    tusUploadURL: nil,
                    tusOffset: 0,
                    errorMessage: nil
                )
            )
        }

        let now = Date()
        tasks.insert(
            CommunityPublishTask(
                id: taskID,
                input: input,
                createdAt: now,
                updatedAt: now,
                state: .queued,
                media: media,
                authorID: nil,
                errorMessage: nil,
                completedAt: nil
            ),
            at: 0
        )
        persistTasks()
        startWorker(taskID: taskID)
        return taskID
    }

    func retry(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[index].state == .failed else { return }
        tasks[index].state = .queued
        tasks[index].errorMessage = nil
        tasks[index].automaticallyRetryable = nil
        tasks[index].updatedAt = Date()
        for mediaIndex in tasks[index].media.indices {
            tasks[index].media[mediaIndex].errorMessage = nil
        }
        persistTasks()
        startWorker(taskID: taskID)
    }

    func cancel(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              !tasks[index].state.isTerminal else { return }
        tasks[index].state = .cancelling
        tasks[index].updatedAt = Date()
        persistTasks()
        workers[taskID]?.cancel()
        workers[taskID] = nil
        CommunityBackgroundTransferManager.shared.cancel(publishTaskID: taskID)
        Task {
            if (try? await CommunityService.shared.pendingPostContext(postID: taskID)) != nil {
                try? await CommunityService.shared.abortPendingPost(postID: taskID)
            }
            await MainActor.run {
                self.finishCancellation(taskID: taskID)
            }
        }
    }

    func handleIdentityChange() {
        for task in activeTasks {
            cancel(taskID: task.id)
        }
        updateStoredNotificationIDs(forKey: notificationDismissedKey) { ids in
            ids.formUnion(
                tasks
                    .filter { $0.state == .published || $0.state == .failed }
                    .map(\.id)
            )
        }
    }

    private func storedNotificationIDs(forKey key: String) -> Set<UUID> {
        Set(
            UserDefaults.standard.stringArray(forKey: key)?
                .compactMap(UUID.init(uuidString:)) ?? []
        )
    }

    private func updateStoredNotificationIDs(
        forKey key: String,
        update: (inout Set<UUID>) -> Void
    ) {
        var ids = storedNotificationIDs(forKey: key)
        update(&ids)
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
        objectWillChange.send()
    }

    private func startQueuedWork() {
        for task in tasks where !task.state.isTerminal
            && task.state != .cancelling
            && task.state != .failed {
            startWorker(taskID: task.id)
        }
    }

    private func resumeAutomaticallyRetryableTasks() {
        var resumedTaskIDs: [UUID] = []
        for index in tasks.indices
        where tasks[index].state == .failed && tasks[index].automaticallyRetryable == true {
            tasks[index].state = .queued
            tasks[index].errorMessage = nil
            tasks[index].automaticallyRetryable = nil
            tasks[index].updatedAt = Date()
            resumedTaskIDs.append(tasks[index].id)
        }
        guard !resumedTaskIDs.isEmpty else { return }
        persistTasks()
        for taskID in resumedTaskIDs {
            startWorker(taskID: taskID)
        }
    }

    private func purgeExpiredTasks() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let expired = tasks.filter {
            ($0.state == .failed || $0.state == .published || $0.state == .cancelled)
                && $0.updatedAt < cutoff
        }
        guard !expired.isEmpty else { return }
        for task in expired {
            try? fileManager.removeItem(at: taskDirectoryURL(taskID: task.id))
        }
        let expiredIDs = Set(expired.map(\.id))
        tasks.removeAll { expiredIDs.contains($0.id) }
        persistTasks()
    }

    private func startWorker(taskID: UUID) {
        guard workers[taskID] == nil else { return }
        workers[taskID] = Task { [weak self] in
            await self?.process(taskID: taskID)
            await MainActor.run {
                self?.workers[taskID] = nil
            }
        }
    }

    private func process(taskID: UUID) async {
        do {
            guard !Task.isCancelled else { return }
            var task = try requiredTask(taskID)
            try await requireBackendCapabilities(for: task)

            if task.authorID == nil {
                setState(taskID, .creatingPost)
                if let existing = try await CommunityService.shared.pendingPostContext(postID: taskID) {
                    updateTask(taskID) {
                        $0.authorID = existing.authorID
                    }
                    if existing.status == "published" {
                        complete(taskID: taskID)
                        return
                    }
                } else {
                    _ = try await CommunityService.shared.createPendingPost(
                        id: taskID,
                        input: task.input,
                        imageCount: task.media.filter { $0.kind == .image }.count,
                        attachmentCount: task.media.filter { $0.kind == .attachment }.count
                    )
                    guard let context = try await CommunityService.shared.pendingPostContext(postID: taskID) else {
                        throw CommunityServiceError.edgeFunctionRejected("帖子创建后未能读取发布状态。")
                    }
                    updateTask(taskID) {
                        $0.authorID = context.authorID
                    }
                    if context.status == "published" {
                        complete(taskID: taskID)
                        return
                    }
                }
            }

            task = try requiredTask(taskID)
            guard let authorID = task.authorID else {
                throw CommunityServiceError.missingAuthenticatedUser
            }
            assignRemotePaths(taskID: taskID, authorID: authorID)
            setState(taskID, .uploading)

            for mediaID in try requiredTask(taskID).media.map(\.id) {
                guard !Task.isCancelled else { return }
                try await processMedia(taskID: taskID, mediaID: mediaID)
            }

            setState(taskID, .publishing)
            guard let post = try await CommunityService.shared.fetchPost(postID: taskID),
                  post.status == "published" else {
                throw CommunityServiceError.edgeFunctionRejected("媒体已上传，但帖子尚未完成发布。")
            }
            complete(taskID: taskID)
        } catch is CancellationError {
            return
        } catch {
            fail(taskID: taskID, error: error)
        }
    }

    private func processMedia(taskID: UUID, mediaID: UUID) async throws {
        var media = try requiredMedia(taskID: taskID, mediaID: mediaID)
        guard !media.validated else { return }
        let directory = try taskDirectory(taskID: taskID, create: false)

        switch media.kind {
        case .image:
            guard let remotePath = media.remotePath,
                  let thumbnailRemotePath = media.thumbnailRemotePath,
                  let thumbnailRelativePath = media.thumbnailRelativePath else {
                throw CommunityServiceError.edgeFunctionRejected("图片上传路径无效。")
            }
            if !media.fullUploaded {
                try await uploadStandardObject(
                    bucket: "community-images",
                    objectPath: remotePath,
                    contentType: media.contentType,
                    fileURL: directory.appendingPathComponent(media.localRelativePath),
                    descriptor: CommunityBackgroundTransferDescriptor(
                        publishTaskID: taskID,
                        mediaID: mediaID,
                        component: .imageFull,
                        offset: 0,
                        byteCount: Int64(media.byteSize)
                    )
                )
                updateMedia(taskID: taskID, mediaID: mediaID) {
                    $0.fullUploaded = true
                    $0.progress = $0.thumbnailUploaded ? 0.9 : 0.5
                }
            }
            media = try requiredMedia(taskID: taskID, mediaID: mediaID)
            if !media.thumbnailUploaded {
                let thumbnailURL = directory.appendingPathComponent(thumbnailRelativePath)
                let thumbnailSize = (try? thumbnailURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                try await uploadStandardObject(
                    bucket: "community-images",
                    objectPath: thumbnailRemotePath,
                    contentType: "image/jpeg",
                    fileURL: thumbnailURL,
                    descriptor: CommunityBackgroundTransferDescriptor(
                        publishTaskID: taskID,
                        mediaID: mediaID,
                        component: .imageThumbnail,
                        offset: 0,
                        byteCount: Int64(thumbnailSize)
                    )
                )
                updateMedia(taskID: taskID, mediaID: mediaID) {
                    $0.thumbnailUploaded = true
                    $0.progress = 0.9
                }
            }

            setState(taskID, .validating)
            try await CommunityService.shared.validateAndAttachPostImage(
                postID: taskID,
                imageID: mediaID,
                fullPath: remotePath,
                thumbnailPath: thumbnailRemotePath,
                sortOrder: media.sortOrder
            )

        case .attachment:
            guard let remotePath = media.remotePath else {
                throw CommunityServiceError.edgeFunctionRejected("附件上传路径无效。")
            }
            if !media.fullUploaded {
                try await uploadAttachmentTUS(
                    taskID: taskID,
                    mediaID: mediaID,
                    sourceURL: directory.appendingPathComponent(media.localRelativePath),
                    objectPath: remotePath
                )
                updateMedia(taskID: taskID, mediaID: mediaID) {
                    $0.fullUploaded = true
                    $0.progress = 0.9
                }
            }
            media = try requiredMedia(taskID: taskID, mediaID: mediaID)
            setState(taskID, .validating)
            try await CommunityService.shared.validateAndAttachPostAttachment(
                postID: taskID,
                attachmentID: mediaID,
                objectPath: remotePath,
                displayName: media.displayName,
                sortOrder: media.sortOrder
            )
        }

        updateMedia(taskID: taskID, mediaID: mediaID) {
            $0.validated = true
            $0.progress = 1
            $0.errorMessage = nil
        }
        setState(taskID, .uploading)
    }

    private func uploadStandardObject(
        bucket: String,
        objectPath: String,
        contentType: String,
        fileURL: URL,
        descriptor: CommunityBackgroundTransferDescriptor
    ) async throws {
        let credentials = try await uploadCredentials()
        var request = URLRequest(
            url: credentials.config.url
                .appendingPathComponent("storage/v1/object")
                .appendingPathComponent(bucket)
                .appendingPathComponent(objectPath)
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.setValue("31536000", forHTTPHeaderField: "cache-control")
        _ = try await CommunityBackgroundTransferManager.shared.upload(
            request: request,
            fileURL: fileURL,
            descriptor: descriptor
        )
    }

    private func uploadAttachmentTUS(
        taskID: UUID,
        mediaID: UUID,
        sourceURL: URL,
        objectPath: String
    ) async throws {
        let chunkSize = 6 * 1024 * 1024
        var media = try requiredMedia(taskID: taskID, mediaID: mediaID)
        var uploadURL = media.tusUploadURL
        var offset = media.tusOffset

        if let currentURL = uploadURL {
            do {
                offset = try await tusOffset(uploadURL: currentURL)
            } catch {
                uploadURL = nil
                offset = 0
            }
        }
        if uploadURL == nil {
            uploadURL = try await createTUSUpload(
                objectPath: objectPath,
                contentType: media.contentType,
                byteSize: media.byteSize
            )
            offset = 0
            updateMedia(taskID: taskID, mediaID: mediaID) {
                $0.tusUploadURL = uploadURL
                $0.tusOffset = 0
            }
        }
        guard let uploadURL else {
            throw CommunityServiceError.edgeFunctionRejected("无法创建附件续传会话。")
        }

        while offset < Int64(media.byteSize) {
            guard !Task.isCancelled else { throw CancellationError() }
            let length = min(Int64(chunkSize), Int64(media.byteSize) - offset)
            let chunkURL = try makeChunkFile(
                sourceURL: sourceURL,
                taskID: taskID,
                mediaID: mediaID,
                offset: offset,
                length: Int(length)
            )
            defer { try? fileManager.removeItem(at: chunkURL) }
            let credentials = try await uploadCredentials()
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(credentials.config.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
            request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
            _ = try await CommunityBackgroundTransferManager.shared.upload(
                request: request,
                fileURL: chunkURL,
                descriptor: CommunityBackgroundTransferDescriptor(
                    publishTaskID: taskID,
                    mediaID: mediaID,
                    component: .attachmentChunk,
                    offset: offset,
                    byteCount: length
                )
            )
            offset += length
            media = try requiredMedia(taskID: taskID, mediaID: mediaID)
            updateMedia(taskID: taskID, mediaID: mediaID) {
                $0.tusOffset = offset
                $0.progress = min(0.9, Double(offset) / Double(max(1, media.byteSize)) * 0.9)
            }
        }
    }

    private func createTUSUpload(
        objectPath: String,
        contentType: String,
        byteSize: Int
    ) async throws -> URL {
        let credentials = try await uploadCredentials()
        let endpoint = directStorageBaseURL(config: credentials.config)
            .appendingPathComponent("storage/v1/upload/resumable")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(byteSize), forHTTPHeaderField: "Upload-Length")
        request.setValue(
            [
                tusMetadata("bucketName", "community-attachments"),
                tusMetadata("objectName", objectPath),
                tusMetadata("contentType", contentType),
                tusMetadata("cacheControl", "3600")
            ].joined(separator: ","),
            forHTTPHeaderField: "Upload-Metadata"
        )
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: endpoint)?.absoluteURL else {
            throw CommunityBackgroundTransferError(
                message: "附件续传会话创建失败。",
                statusCode: (response as? HTTPURLResponse)?.statusCode
            )
        }
        return url
    }

    private func tusOffset(uploadURL: URL) async throws -> Int64 {
        let credentials = try await uploadCredentials()
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rawOffset = http.value(forHTTPHeaderField: "Upload-Offset"),
              let offset = Int64(rawOffset) else {
            throw CommunityBackgroundTransferError(
                message: "附件续传状态已失效。",
                statusCode: (response as? HTTPURLResponse)?.statusCode
            )
        }
        return offset
    }

    private func requireBackendCapabilities(for task: CommunityPublishTask) async throws {
        let mediaKinds = Set(task.media.map(\.kind))
        let cachedCapabilities = try await SupabaseBackendClient.shared.capabilities()
        let capabilities = try await CommunityPublishCapabilityRequirements.refreshingIfNeeded(
            cachedCapabilities,
            mediaKinds: mediaKinds
        ) {
            try await SupabaseBackendClient.shared.capabilities(forceRefresh: true)
        }

        let missingRPCs = CommunityPublishCapabilityRequirements.missingRPCs(
            in: capabilities,
            mediaKinds: mediaKinds
        )
        let missingEdgeFunctions = CommunityPublishCapabilityRequirements.missingEdgeFunctions(
            in: capabilities,
            mediaKinds: mediaKinds
        )
        guard missingRPCs.isEmpty, missingEdgeFunctions.isEmpty else {
            CommunityDiagnostics.log.error(
                """
                Community publish capabilities unavailable after refresh. \
                version=\(capabilities.version, privacy: .public) \
                media_kinds=\(mediaKinds.map(\.rawValue).sorted().joined(separator: ","), privacy: .public) \
                missing_rpcs=\(missingRPCs.joined(separator: ","), privacy: .public) \
                missing_edge_functions=\(missingEdgeFunctions.joined(separator: ","), privacy: .public)
                """
            )
            throw CommunityServiceError.edgeFunctionRejected("社区服务需要更新后才能发布，请稍后重试。")
        }
    }

    private func uploadCredentials() async throws -> (config: SupabaseConfig, accessToken: String) {
        let client = try LeafySupabase.shared.requireClient()
        let session = try await client.auth.session
        return (try LeafySupabase.shared.requireConfig(), session.accessToken)
    }

    private func directStorageBaseURL(config: SupabaseConfig) -> URL {
        guard let host = config.url.host,
              host.hasSuffix(".supabase.co"),
              !host.hasSuffix(".storage.supabase.co"),
              var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            return config.url
        }
        components.host = host.replacingOccurrences(of: ".supabase.co", with: ".storage.supabase.co")
        components.path = ""
        return components.url ?? config.url
    }

    private func tusMetadata(_ key: String, _ value: String) -> String {
        let encoded = Data(value.utf8).base64EncodedString()
        return "\(key) \(encoded)"
    }

    private func makeChunkFile(
        sourceURL: URL,
        taskID: UUID,
        mediaID: UUID,
        offset: Int64,
        length: Int
    ) throws -> URL {
        let source = try FileHandle(forReadingFrom: sourceURL)
        defer { try? source.close() }
        try source.seek(toOffset: UInt64(offset))
        guard let data = try source.read(upToCount: length), data.count == length else {
            throw CommunityServiceError.edgeFunctionRejected("读取附件分块失败。")
        }
        let url = try taskDirectory(taskID: taskID, create: true)
            .appendingPathComponent("\(mediaID.uuidString.lowercased())-\(offset).chunk")
        try data.write(to: url, options: .atomic)
        try applyBackgroundFileProtection(to: url)
        return url
    }

    private func assignRemotePaths(taskID: UUID, authorID: UUID) {
        updateTask(taskID) { task in
            for index in task.media.indices {
                let media = task.media[index]
                let base = "posts/\(authorID.uuidString.lowercased())/\(taskID.uuidString.lowercased())"
                switch media.kind {
                case .image:
                    task.media[index].remotePath =
                        "\(base)/full/\(media.id.uuidString.lowercased()).\(media.fileExtension)"
                    task.media[index].thumbnailRemotePath =
                        "\(base)/thumb/\(media.id.uuidString.lowercased()).jpg"
                case .attachment:
                    task.media[index].remotePath =
                        "\(base)/\(media.id.uuidString.lowercased()).\(media.fileExtension)"
                }
            }
        }
    }

    private func applyProgress(
        descriptor: CommunityBackgroundTransferDescriptor,
        progress: Double
    ) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == descriptor.publishTaskID }),
              let mediaIndex = tasks[taskIndex].media.firstIndex(where: { $0.id == descriptor.mediaID }) else {
            return
        }
        let media = tasks[taskIndex].media[mediaIndex]
        let resolved: Double
        switch descriptor.component {
        case .imageFull:
            resolved = (media.thumbnailUploaded ? 0.5 : 0) + progress * 0.5
        case .imageThumbnail:
            resolved = (media.fullUploaded ? 0.5 : 0) + progress * 0.5
        case .attachmentChunk:
            let uploaded = Double(descriptor.offset) + progress * Double(descriptor.byteCount)
            resolved = min(0.9, uploaded / Double(max(1, media.byteSize)) * 0.9)
        }
        tasks[taskIndex].media[mediaIndex].progress = max(media.progress, resolved)
        tasks[taskIndex].updatedAt = Date()
        persistTasks()
    }

    private func setState(_ taskID: UUID, _ state: CommunityPublishTaskState) {
        updateTask(taskID) {
            $0.state = state
            $0.errorMessage = nil
            $0.automaticallyRetryable = nil
        }
    }

    private func complete(taskID: UUID) {
        updateTask(taskID) {
            $0.state = .published
            $0.completedAt = Date()
            $0.errorMessage = nil
            $0.automaticallyRetryable = nil
            for index in $0.media.indices {
                $0.media[index].progress = 1
                $0.media[index].validated = true
            }
        }
        try? fileManager.removeItem(at: taskDirectoryURL(taskID: taskID))
        NotificationCenter.default.post(
            name: .communityPublishTaskDidFinish,
            object: taskID,
            userInfo: ["succeeded": true]
        )
    }

    private func fail(taskID: UUID, error: Error) {
        guard tasks.contains(where: { $0.id == taskID && $0.state != .cancelling }) else { return }
        logger.error("Community publish failed task=\(taskID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
        updateTask(taskID) {
            $0.state = .failed
            $0.errorMessage = error.localizedDescription
            $0.automaticallyRetryable = isAutomaticallyRetryable(error)
        }
        NotificationCenter.default.post(
            name: .communityPublishTaskDidFinish,
            object: taskID,
            userInfo: ["succeeded": false, "message": error.localizedDescription]
        )
    }

    private func finishCancellation(taskID: UUID) {
        updateTask(taskID) {
            $0.state = .cancelled
            $0.completedAt = Date()
            $0.errorMessage = nil
            $0.automaticallyRetryable = nil
        }
        try? fileManager.removeItem(at: taskDirectoryURL(taskID: taskID))
    }

    private func updateTask(_ taskID: UUID, mutation: (inout CommunityPublishTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        mutation(&tasks[index])
        tasks[index].updatedAt = Date()
        persistTasks()
    }

    private func isAutomaticallyRetryable(_ error: Error) -> Bool {
        if let transferError = error as? CommunityBackgroundTransferError,
           let statusCode = transferError.statusCode {
            return statusCode == 401
                || statusCode == 408
                || statusCode == 409
                || statusCode == 425
                || statusCode == 429
                || statusCode >= 500
        }

        let urlError = error as? URLError
            ?? (error as NSError).userInfo[NSUnderlyingErrorKey] as? URLError
        guard let urlError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed,
            .secureConnectionFailed
        ].contains(urlError.code)
    }

    private func updateMedia(
        taskID: UUID,
        mediaID: UUID,
        mutation: (inout CommunityPublishMediaItem) -> Void
    ) {
        updateTask(taskID) { task in
            guard let index = task.media.firstIndex(where: { $0.id == mediaID }) else { return }
            mutation(&task.media[index])
        }
    }

    private func requiredTask(_ taskID: UUID) throws -> CommunityPublishTask {
        guard let task = tasks.first(where: { $0.id == taskID }) else {
            throw CommunityServiceError.edgeFunctionRejected("本地发布任务已不存在。")
        }
        return task
    }

    private func requiredMedia(taskID: UUID, mediaID: UUID) throws -> CommunityPublishMediaItem {
        guard let media = try requiredTask(taskID).media.first(where: { $0.id == mediaID }) else {
            throw CommunityServiceError.edgeFunctionRejected("本地上传文件已不存在。")
        }
        return media
    }

    private func taskDirectory(taskID: UUID, create: Bool) throws -> URL {
        let url = taskDirectoryURL(taskID: taskID)
        if create {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try applyBackgroundFileProtection(to: url)
        } else if !fileManager.fileExists(atPath: url.path) {
            throw CommunityServiceError.edgeFunctionRejected("本地发布文件已被清理，请重新选择文件。")
        }
        return url
    }

    private func taskDirectoryURL(taskID: UUID) -> URL {
        publishRootDirectory.appendingPathComponent(taskID.uuidString.lowercased(), isDirectory: true)
    }

    private var publishRootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("CommunityPublishQueue", isDirectory: true)
    }

    private var manifestURL: URL {
        publishRootDirectory.appendingPathComponent("tasks.json")
    }

    private func persistTasks() {
        do {
            try fileManager.createDirectory(at: publishRootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: manifestURL, options: .atomic)
            try applyBackgroundFileProtection(to: manifestURL)
        } catch {
            logger.error("Persist community publish tasks failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func loadPersistedTasks() -> [CommunityPublishTask] {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([CommunityPublishTask].self, from: data) else {
            return []
        }
        let retentionCutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return decoded.filter {
            if $0.state == .published || $0.state == .cancelled {
                return ($0.completedAt ?? $0.updatedAt) >= retentionCutoff
            }
            return true
        }
    }

    private func applyBackgroundFileProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }
}

nonisolated final class LeafyBackgroundSessionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == CommunityBackgroundTransferManager.sessionIdentifier else {
            completionHandler()
            return
        }
        CommunityBackgroundTransferManager.shared.setBackgroundCompletionHandler(completionHandler)
    }
}

extension Notification.Name {
    static let communityPublishTaskDidFinish = Notification.Name("CommunityPublishTaskDidFinish")
}
