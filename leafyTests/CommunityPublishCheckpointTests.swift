import XCTest
@testable import Leafy

@MainActor
final class CommunityPublishCheckpointTests: XCTestCase {
    func testByteProgressDoesNotWriteManifestOrChangeRestartCheckpoint() throws {
        let (directory, task) = try fixture()
        var writes = 0
        let coordinator = CommunityPublishCoordinator(backend: CheckpointPublishBackend(), rootDirectory: directory, writeManifest: { data, url in
            writes += 1
            try data.write(to: url, options: .atomic)
        })
        for value in 1...200 { coordinator.applyProgress(descriptor: descriptor(task), progress: Double(value) / 200) }
        coordinator.applyProgress(descriptor: descriptor(task), progress: 0.1)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(coordinator.tasks.first?.media.first?.progress ?? -1, 0.5, accuracy: 0.001)
        let restored = CommunityPublishCoordinator(backend: CheckpointPublishBackend(), rootDirectory: directory)
        XCTAssertEqual(restored.tasks.first?.media.first?.progress, 0)
        XCTAssertEqual(restored.tasks.first?.media.first?.remotePath, nil)
    }

    func testUploadAndValidationPersistRecoveryPathsBeforeFinalFailure() async throws {
        let (directory, task) = try fixture()
        var checkpoints: [CommunityPublishTask] = []
        let failed = expectation(description: "Final publish failure persisted")
        let coordinator = CommunityPublishCoordinator(backend: CheckpointPublishBackend(), rootDirectory: directory, writeManifest: { data, url in
            let saved = try JSONDecoder().decode([CommunityPublishTask].self, from: data)
            checkpoints.append(contentsOf: saved)
            try data.write(to: url, options: .atomic)
            if saved.first?.state == .failed { failed.fulfill() }
        })
        coordinator.configureAndResume()
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertTrue(checkpoints.contains { $0.media.first?.fullUploaded == true && $0.media.first?.remotePath == "full" })
        XCTAssertTrue(checkpoints.contains { $0.media.first?.thumbnailUploaded == true && $0.media.first?.thumbnailRemotePath == "thumb" })
        XCTAssertTrue(checkpoints.contains { $0.media.first?.validated == true })
        let restored = CommunityPublishCoordinator(backend: CheckpointPublishBackend(), rootDirectory: directory)
        XCTAssertEqual(restored.tasks.first?.id, task.id)
        XCTAssertEqual(restored.tasks.first?.state, .failed)
        XCTAssertEqual(restored.tasks.first?.media.first?.validated, true)
    }

    func testProgressCannotClearCheckpointWriteFailure() throws {
        let (directory, task) = try fixture()
        let coordinator = CommunityPublishCoordinator(backend: CheckpointPublishBackend(), rootDirectory: directory, writeManifest: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        coordinator.configureAndResume()
        let error = try XCTUnwrap(coordinator.storageError)
        coordinator.applyProgress(descriptor: descriptor(task), progress: 0.6)
        XCTAssertEqual(coordinator.storageError, error)
        XCTAssertEqual(coordinator.tasks.first?.state, .uploading)
        let saved = try JSONDecoder().decode([CommunityPublishTask].self, from: Data(contentsOf: directory.appendingPathComponent("tasks.json")))
        XCTAssertEqual(saved.first?.media.first?.progress, 0)
    }

    func testLateProgressIsIgnoredForOtherIdentityAndStoppedTasks() throws {
        let (directory, task) = try fixture()
        let coordinator = CommunityPublishCoordinator(backend: CheckpointPublishBackend(), rootDirectory: directory)
        ActiveCampusContext.networkManager.persistAuthenticatedIdentity(eduID: "another-publish-owner-" + UUID().uuidString)
        coordinator.applyProgress(descriptor: descriptor(task), progress: 1)
        XCTAssertEqual(coordinator.tasks.first?.media.first?.progress, 0)
        for state in [CommunityPublishTaskState.failed, .cancelling, .cancelled, .published] {
            var stopped = task
            stopped.state = state
            stopped.ownerScopeKey = ActiveCampusContext.identity?.scopeKey
            try JSONEncoder().encode([stopped]).write(to: directory.appendingPathComponent("tasks.json"))
            let restored = CommunityPublishCoordinator(backend: CheckpointPublishBackend(), rootDirectory: directory)
            restored.applyProgress(descriptor: descriptor(task), progress: 1)
            XCTAssertEqual(restored.tasks.first?.media.first?.progress, 0)
        }
    }

    private func descriptor(_ task: CommunityPublishTask) -> CommunityBackgroundTransferDescriptor {
        .init(publishTaskID: task.id, mediaID: task.media[0].id, component: .imageFull, offset: 0, byteCount: 100)
    }

    private func fixture() throws -> (URL, CommunityPublishTask) {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "checkpoint-" + UUID().uuidString)
        addTeardownBlock { @MainActor in manager.clearSession() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let media = CommunityPublishMediaItem(id: UUID(), kind: .image, displayName: "Image", contentType: "image/jpeg", fileExtension: "jpg", byteSize: 100, sortOrder: 0, localRelativePath: "full.jpg", thumbnailRelativePath: "thumb.jpg", remotePath: nil, thumbnailRemotePath: nil, fullUploaded: false, thumbnailUploaded: false, validated: false, progress: 0, tusUploadURL: nil, tusOffset: 0, errorMessage: nil)
        let task = CommunityPublishTask(id: UUID(), input: .init(title: "Title", body: "Body", category: nil, isAnonymous: false), createdAt: Date(), updatedAt: Date(), state: .uploading, media: [media], authorID: UUID(), errorMessage: nil, completedAt: nil, backendAuthority: MyLeafyBackendEnvironment.publicationAuthority, ownerScopeKey: ActiveCampusContext.identity?.scopeKey)
        let taskDirectory = directory.appendingPathComponent(task.id.uuidString.lowercased())
        try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
        try Data("thumbnail".utf8).write(to: taskDirectory.appendingPathComponent("thumb.jpg"))
        try JSONEncoder().encode([task]).write(to: directory.appendingPathComponent("tasks.json"))
        return (directory, task)
    }
}

private actor CheckpointPublishBackend: CommunityPublishBackend {
    func requireCapabilities(for mediaKinds: Set<CommunityPublishMediaKind>) async throws {}
    func pendingPostContext(postID: UUID) async throws -> CommunityPendingPostContext? { nil }
    func abortPendingPost(postID: UUID) async throws {}
    func createPendingPost(id: UUID, input: CreatePostInput, imageCount: Int, attachmentCount: Int) async throws -> UUID { id }
    func fetchPost(postID: UUID) async throws -> CommunityPost? { nil }
    func validateAndAttachPostImage(postID: UUID, imageID: UUID, fullPath: String, thumbnailPath: String, sortOrder: Int) async throws {}
    func validateAndAttachPostAttachment(postID: UUID, attachmentID: UUID, objectPath: String, displayName: String, sortOrder: Int) async throws {}
    func uploadMedia(kind: String, taskID: UUID, mediaID: UUID, name: String, contentType: String, fileURL: URL, descriptor: CommunityBackgroundTransferDescriptor) async throws -> String { kind }
}
