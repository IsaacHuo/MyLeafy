import XCTest
import SwiftData
@testable import Leafy

@MainActor
final class IOSReliabilityTests: XCTestCase {
    func testUnitTestHostIsIsolatedFromProductionBackend() {
        XCTAssertTrue(AppRuntimeEnvironment.isRunningUnitTests)
        XCTAssertThrowsError(try MyLeafyBackendEnvironment.client()) { error in
            XCTAssertEqual((error as? MyLeafyBackendError)?.code, "test_network_prohibited")
        }
    }

    func testDefaultSchoolTransportCannotMakeLiveRequestsInUnitTests() async {
        do {
            _ = try await ActiveCampusContext.networkManager
                .data(for: URLRequest(url: URL(string: "https://example.invalid")!))
            XCTFail("Default transport must refuse a live request")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
        }
    }
    func testFailedBackupNeverRemovesAnyOriginalStoreComponent() throws {
        let directory = try temporaryDirectory()
        let store = directory.appendingPathComponent("Leafy.store")
        let wal = URL(fileURLWithPath: store.path + "-wal")
        try Data("original".utf8).write(to: store)
        try Data("pending".utf8).write(to: wal)
        var copies = 0
        var opened = false
        XCTAssertThrowsError(try AppModelContainerFactory.rebuildStore(at: store, copyFile: { source, destination in
            copies += 1
            if copies == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.copyItem(at: source, to: destination)
        }, open: {
            opened = true
            return try self.memoryContainer()
        }))
        XCTAssertFalse(opened)
        XCTAssertEqual(try Data(contentsOf: store), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: wal), Data("pending".utf8))
    }

    func testCorruptBackupFailsVerificationAndKeepsOriginal() throws {
        let directory = try temporaryDirectory()
        let store = directory.appendingPathComponent("Leafy.store")
        try Data("original".utf8).write(to: store)
        XCTAssertThrowsError(try AppModelContainerFactory.rebuildStore(at: store, copyFile: { _, destination in
            try Data("wrong".utf8).write(to: destination)
        }, open: { try self.memoryContainer() }))
        XCTAssertEqual(try Data(contentsOf: store), Data("original".utf8))
    }

    func testFailedExplicitRebuildRestoresOriginalStoreAndWAL() throws {
        let directory = try temporaryDirectory()
        let store = directory.appendingPathComponent("Leafy.store")
        let wal = URL(fileURLWithPath: store.path + "-wal")
        try Data("original".utf8).write(to: store)
        try Data("pending".utf8).write(to: wal)
        XCTAssertThrowsError(try AppModelContainerFactory.rebuildStore(at: store) {
            try Data("replacement".utf8).write(to: store)
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertEqual(try Data(contentsOf: store), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: wal), Data("pending".utf8))
    }

    func testOperationScopeRejectsOldIdentityPortalAndSessionGeneration() throws {
        let manager = ActiveCampusContext.networkManager
        defer { manager.clearSession() }
        manager.persistAuthenticatedIdentity(eduID: "scope-a", displayName: "A")
        let a = CampusOperationScope()
        XCTAssertNoThrow(try a.check())
        manager.persistAuthenticatedIdentity(eduID: "scope-b", displayName: "B")
        XCTAssertThrowsError(try a.check())
        let b = CampusOperationScope()
        manager.currentPortal = .graduate
        XCTAssertThrowsError(try b.check())
        let graduate = CampusOperationScope()
        manager.cancelInFlightRequests()
        XCTAssertThrowsError(try graduate.check())
    }

    func testCancelledPrefetchCannotClearReplacementTaskOrWriteCooldown() async throws {
        let manager = ActiveCampusContext.networkManager
        defer { manager.clearSession() }
        manager.currentPortal = .undergraduate
        manager.persistAuthenticatedIdentity(eduID: "replacement-test", displayName: "Test")
        manager.isLoggedIn = true
        let suite = "PrefetchReplacement-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = SchoolDataPrefetchCoordinator(userDefaults: defaults)
        let container = try memoryContainer()
        var old: CheckedContinuation<SchoolDataSyncOutcome, Never>?
        var replacement: CheckedContinuation<SchoolDataSyncOutcome, Never>?
        XCTAssertEqual(
            coordinator
                .prefetchIfNeeded(modelContext: container.mainContext, language: .zhHans,
                                  trigger: .foreground) { _, _ in
                    await withCheckedContinuation { old = $0 }
                },
            .started
        )
        for _ in 0 ..< 20 { if old != nil { break }; await Task.yield() }
        XCTAssertNotNil(old)
        coordinator.cancel()
        XCTAssertEqual(
            coordinator
                .prefetchIfNeeded(modelContext: container.mainContext, language: .zhHans,
                                  trigger: .foreground) { _, _ in
                    await withCheckedContinuation { replacement = $0 }
                },
            .started
        )
        for _ in 0 ..< 20 { if replacement != nil { break }; await Task.yield() }
        XCTAssertNotNil(replacement)
        old?.resume(returning: .success("obsolete"))
        for _ in 0 ..< 20 { await Task.yield() }
        XCTAssertEqual(
            coordinator
                .prefetchIfNeeded(modelContext: container.mainContext, language: .zhHans,
                                  trigger: .foreground) { _, _ in
                    .success("unexpected") },
            .skipped(.alreadyRunning)
        )
        replacement?.resume(returning: .cancelled)
        for _ in 0 ..< 20 { await Task.yield() }
        XCTAssertEqual(
            coordinator
                .prefetchIfNeeded(modelContext: container.mainContext, language: .zhHans,
                                  trigger: .foreground) { _, _ in
                    .cancelled },
            .started
        )
        coordinator.cancel()
    }

    func testNoteSaveFailurePreservesOriginalAndUnrelatedPendingEdit() throws {
        let schema = Schema([CourseNote.self, CourseOccurrenceNote.self, CourseReminderSetting.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [.init(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let note = CourseNote(courseKey: "course", text: "original")
        let other = CourseNote(courseKey: "other", text: "old")
        context.insert(note); context.insert(other); try context.save()
        other.text = "pending"
        XCTAssertThrowsError(try TimetableLocalEdits.setCourseNote(
            "replacement",
            courseKey: "course",
            in: context,
            save: { _ in throw CocoaError(.fileWriteOutOfSpace) }
        ))
        XCTAssertEqual(note.text, "original")
        XCTAssertEqual(other.text, "pending")
        XCTAssertThrowsError(try TimetableLocalEdits.setCourseNote(
            "",
            courseKey: "course",
            in: context,
            save: { _ in throw CocoaError(.fileWriteOutOfSpace) }
        ))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseNote>()).count, 2)
        XCTAssertEqual(note.text, "original")
    }

    func testReminderSaveFailureRestoresSettingAndRemovesFailedInsert() throws {
        let schema = Schema([CourseReminderSetting.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [.init(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let existing = CourseReminderSetting(courseKey: "course", minutesBefore: 10, anchorPeriod: 1)
        context.insert(existing); try context.save()
        XCTAssertThrowsError(try TimetableLocalEdits.setReminder(
            courseKey: "course",
            minutesBefore: 30,
            anchorPeriod: 3,
            in: context,
            save: { _ in throw CocoaError(.fileWriteOutOfSpace) }
        ))
        XCTAssertEqual(existing.minutesBefore, 10)
        XCTAssertEqual(existing.anchorPeriod, 1)
        XCTAssertThrowsError(try TimetableLocalEdits.setReminder(
            courseKey: "new",
            minutesBefore: 30,
            anchorPeriod: 3,
            in: context,
            save: { _ in throw CocoaError(.fileWriteOutOfSpace) }
        ))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CourseReminderSetting>()), 1)
    }

    func testFileDeletionSaveFailureKeepsFileAndRestoresOnlyDeletedModels() throws {
        let (container, image, file, queue) = try fileFixture()
        let context = container.mainContext
        let cleanup = LocalFileCleanup(queueURL: queue)
        XCTAssertThrowsError(try cleanup.delete(
            [image],
            files: [.init(image, url: file)],
            in: context,
            save: { _ in throw CocoaError(.fileWriteOutOfSpace) }
        ))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 1)
        try cleanup.retry(in: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testFailedFileCleanupSurvivesRestartAndRetriesAfterMetadataCommit() throws {
        let (container, image, file, queue) = try fileFixture()
        let cleanup = LocalFileCleanup(queueURL: queue, removeFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertThrowsError(try cleanup.delete([image], files: [.init(image, url: file)], in: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try LocalFileCleanup(queueURL: queue).retry(in: container.mainContext)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCorruptCleanupQueueDoesNotDeleteModelsOrFiles() throws {
        let (container, image, file, queue) = try fileFixture()
        try Data("corrupt".utf8).write(to: queue)
        var saved = false
        XCTAssertThrowsError(try LocalFileCleanup(queueURL: queue).delete(
            [image],
            files: [.init(image, url: file)],
            in: container.mainContext,
            save: { _ in saved = true }
        ))
        XCTAssertFalse(saved)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: queue), Data("corrupt".utf8))
    }

    func testCleanupIntentWriteFailurePreventsMetadataDeletion() throws {
        let (container, image, file, queue) = try fileFixture()
        let blocked = queue.deletingLastPathComponent().appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocked)
        XCTAssertThrowsError(try LocalFileCleanup(queueURL: blocked.appendingPathComponent("queue.json")).delete(
            [image],
            files: [.init(image, url: file)],
            in: container.mainContext
        ))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    private func fileFixture() throws -> (ModelContainer, ScheduleMemoImage, URL, URL) {
        let directory = try temporaryDirectory()
        let schema = Schema([ScheduleMemoImage.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [.init(schema: schema, isStoredInMemoryOnly: true)]
        )
        let image = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "image.jpg")
        container.mainContext.insert(image)
        try container.mainContext.save()
        let file = directory.appendingPathComponent(image.localFilename)
        try Data("image".utf8).write(to: file)
        return (container, image, file, directory.appendingPathComponent("cleanup.json"))
    }

    func testBatchImportMissingSecondFileLeavesNoRowsAndRemovesCopiedPrefix() throws {
        let directory = try temporaryDirectory()
        let schema = Schema([LearningMaterialDocument.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [.init(schema: schema, isStoredInMemoryOnly: true)]
        )
        let source = directory.appendingPathComponent("first.pdf")
        try Data("pdf".utf8).write(to: source)
        let cleanup = LocalFileCleanup(queueURL: directory.appendingPathComponent("cleanup.json"))
        let sources = [
            LearningMaterialBatchImport.Source(url: source),
            .init(url: directory.appendingPathComponent("missing.pdf"))
        ]
        XCTAssertThrowsError(try LearningMaterialBatchImport.importFiles(
            sources,
            to: .fixed(.courseware),
            in: container.mainContext,
            cleanup: cleanup
        ))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<LearningMaterialDocument>()), 0)
        XCTAssertEqual(
            try JSONDecoder().decode(
                [LocalFileCleanup.File].self,
                from: Data(contentsOf: directory.appendingPathComponent("cleanup.json"))
            ).count,
            0
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testBatchImportSaveFailureKeepsStagingAndRetryCreatesOneDocument() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.pdf")
        try Data("pdf".utf8).write(to: source)
        let schema = Schema([LearningMaterialDocument.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [.init(schema: schema, isStoredInMemoryOnly: true)]
        )
        let store = ExternalLearningMaterialImportStore(rootDirectory: directory.appendingPathComponent("staging"))
        let batch = try store.makeBatch(from: [source], source: .openIn)
        let coordinator = ExternalLearningMaterialImportCoordinator(store: store)
        let cleanup = LocalFileCleanup(queueURL: directory.appendingPathComponent("cleanup.json"))
        let navigation = AppNavigationCoordinator()
        XCTAssertThrowsError(try coordinator.importBatch(
            batch,
            to: .fixed(.courseware),
            modelContext: container.mainContext,
            appNavigation: navigation,
            save: { _ in throw CocoaError(.fileWriteOutOfSpace) },
            cleanup: cleanup
        ))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<LearningMaterialDocument>()), 0)
        XCTAssertNoThrow(try store.loadManifest(id: batch.id))
        XCTAssertEqual(
            try coordinator
                .importBatch(batch, to: .fixed(.courseware), modelContext: container.mainContext,
                             appNavigation: navigation, cleanup: cleanup),
            1
        )
        let document = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<LearningMaterialDocument>()).first)
        defer { try? LearningMaterialFileStore.deleteFile(named: document.localFilename) }
        XCTAssertEqual(document.id, batch.items[0].id)
        let repeated = try LearningMaterialBatchImport.importFiles(
            [.init(id: batch.items[0].id, url: source)],
            to: .fixed(.courseware),
            in: container.mainContext,
            cleanup: cleanup
        )
        XCTAssertEqual(repeated.documents.count, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<LearningMaterialDocument>()), 1)
        XCTAssertNotNil(LearningMaterialFileStore.fileURL(for: document))
    }

    func testMixedValidAndMalformedExamRowsRejectEntireResult() throws {
        let html = """
        <table id="dataList"><tr><th>序号</th><th>课程代码</th><th>课程名称</th><th>考试时间</th><th>教室</th></tr>
        <tr><td>1</td><td>A</td><td>正常课程</td><td>2026-06-20 09:00-11:00</td><td>205</td></tr>
        <tr><td>2</td><td>B</td><td>异常课程</td><td>格式未知</td><td>206</td></tr></table>
        """
        XCTAssertThrowsError(try HTMLParser.parseExams(html: html)) { error in
            guard case HTMLParserError.tableRowsUnparseable("考试安排") = error
            else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertTrue(try HTMLParser
            .parseExams(
                html: "<table id='dataList'><tr><th>课程名称</th><th>考试时间</th></tr><tr><td colspan='2'>暂无数据</td></tr></table>"
            )
            .isEmpty)
    }

    func testFreshPersistentStoreCreatesDirectoryWithoutRecovery() throws {
        let directory = try temporaryDirectory()
        let schema = Schema([Course.self])
        let url = directory.appendingPathComponent("nested/Leafy.store")
        _ = try AppModelContainerFactory.open(schema: schema, configuration: .init(schema: schema, url: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExplicitRebuildArchivesOldCleanupIntentsInsteadOfReplayingAgainstEmptyStore() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("Leafy.store")
        let queue = directory.appendingPathComponent("PendingLocalFileCleanup.json")
        try Data("store".utf8).write(to: url)
        try Data("old-cleanup-intents".utf8).write(to: queue)
        _ = try AppModelContainerFactory.rebuildStore(at: url) { try self.memoryContainer() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.path))
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("LeafyStoreBackups"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(
            try Data(contentsOf: backups[0].appendingPathComponent(queue.lastPathComponent)),
            Data("old-cleanup-intents".utf8)
        )
    }

    func testOldTeachingResponseCannotWriteNewIdentityCacheOrStartNextRequest() async throws {
        let manager = ActiveCampusContext.networkManager
        let suffix = UUID().uuidString
        manager.persistAuthenticatedIdentity(eduID: "teaching-a-" + suffix)
        defer { SchoolDataCache.clearDiscoverCaches(); manager.clearSession() }
        let provider = SuspendedAcademicProvider()
        let task = Task { await TeachingCultivationRefreshUseCase(networkManager: provider).refresh() }
        for _ in 0 ..< 30 { if provider.continuation != nil { break }; await Task.yield() }
        let continuation = try XCTUnwrap(provider.continuation)
        manager.persistAuthenticatedIdentity(eduID: "teaching-b-" + suffix)
        SchoolDataCache.saveTeachingPlan([TeachingPlanSection(term: "B sentinel", courses: [])], notifies: false)
        continuation.resume(returning: "old-response")
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(provider.graduationCalls, 0)
        XCTAssertEqual(SchoolDataCache.loadTeachingPlan().map(\.term), ["B sentinel"])
    }

    func testPublishManifestFailureDoesNotAcceptTaskStartWorkerOrDeleteDraft() async throws {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "publish-test-" + UUID().uuidString)
        defer { manager.clearSession() }
        let directory = try temporaryDirectory()
        let backend = CountingPublishBackend()
        let coordinator = CommunityPublishCoordinator(
            backend: backend,
            rootDirectory: directory.appendingPathComponent("queue"),
            writeManifest: { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        )
        let repository = LocalCommunityPostDraftRepository(rootDirectory: directory, appliesFileProtection: false)
        let ownerID = UUID()
        let draftID = UUID()
        let input = CreatePostInput(title: "Title", body: "Body", category: nil, isAnonymous: false)
        _ = try repository.saveDraft(id: draftID, ownerProfileID: ownerID, input: input, images: [], attachments: [])
        XCTAssertThrowsError(try CommunityPostDraftPublishHandoff.enqueue(
            draftID: draftID,
            ownerProfileID: ownerID,
            repository: repository
        ) {
            try coordinator.enqueue(input: input, images: [], attachments: [])
        })
        for _ in 0 ..< 10 { await Task.yield() }
        let calls = await backend.capabilityCalls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(coordinator.tasks.isEmpty)
        XCTAssertNoThrow(try repository.loadDraft(id: draftID, ownerProfileID: ownerID))
    }

    func testCorruptPublishQueueIsReportedAndNeverOverwritten() throws {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "corrupt-publish-" + UUID().uuidString)
        defer { manager.clearSession() }
        let directory = try temporaryDirectory()
        let manifest = directory.appendingPathComponent("tasks.json")
        let original = Data("corrupt-manifest".utf8)
        try original.write(to: manifest)
        let coordinator = CommunityPublishCoordinator(backend: CountingPublishBackend(), rootDirectory: directory)
        XCTAssertNotNil(coordinator.storageError)
        coordinator.configureAndResume()
        XCTAssertThrowsError(try coordinator.enqueue(
            input: .init(title: "Title", body: "Body", category: nil, isAnonymous: false),
            images: [],
            attachments: []
        ))
        XCTAssertEqual(try Data(contentsOf: manifest), original)
    }

    func testRestoredPublicationDoesNotResumeForAnotherIdentity() async throws {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "publish-a-" + UUID().uuidString)
        let scopeA = try XCTUnwrap(ActiveCampusContext.identity?.scopeKey)
        defer { manager.clearSession() }
        let directory = try temporaryDirectory()
        let now = Date()
        let task = CommunityPublishTask(
            id: UUID(),
            input: .init(title: "Private A", body: "Body A", category: nil, isAnonymous: false),
            createdAt: now,
            updatedAt: now,
            state: .queued,
            media: [],
            authorID: nil,
            errorMessage: nil,
            completedAt: nil,
            backendAuthority: MyLeafyBackendEnvironment.publicationAuthority,
            ownerScopeKey: scopeA
        )
        try JSONEncoder().encode([task]).write(to: directory.appendingPathComponent("tasks.json"))
        manager.persistAuthenticatedIdentity(eduID: "publish-b-" + UUID().uuidString)
        let backend = CountingPublishBackend()
        let coordinator = CommunityPublishCoordinator(backend: backend, rootDirectory: directory)
        coordinator.configureAndResume()
        for _ in 0 ..< 10 { await Task.yield() }
        let calls = await backend.capabilityCalls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(coordinator.visibleTasks.isEmpty)
        XCTAssertEqual(coordinator.tasks.count, 1)
    }

    func testRecordingPermissionReturningAfterDismissDoesNotStartRecording() async throws {
        var permission: CheckedContinuation<Bool, Never>?
        let recorder =
            ScheduleMemoAudioRecorder(permissionRequest: { await withCheckedContinuation { permission = $0 } })
        let start = Task { await recorder.start() }
        for _ in 0 ..< 30 { if permission != nil { break }; await Task.yield() }
        let response = try XCTUnwrap(permission)
        XCTAssertEqual(recorder.state, .requestingPermission)
        recorder.discard()
        start.cancel()
        response.resume(returning: true)
        await start.value
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.recordingURL)
    }

    func testOldRecordingPermissionCannotOverwriteReplacementRequest() async throws {
        var permissions: [CheckedContinuation<Bool, Never>] = []
        let recorder =
            ScheduleMemoAudioRecorder(permissionRequest: { await withCheckedContinuation { permissions.append($0) } })
        let old = Task { await recorder.start() }
        for _ in 0 ..< 30 { if permissions.count == 1 { break }; await Task.yield() }
        XCTAssertEqual(permissions.count, 1)
        let current = Task { await recorder.start() }
        for _ in 0 ..< 30 { if permissions.count == 2 { break }; await Task.yield() }
        guard permissions.count == 2
        else {
            recorder.discard(); old.cancel(); current.cancel(); return XCTFail("Permission requests did not start") }
        permissions[0].resume(returning: false)
        await old.value
        XCTAssertEqual(recorder.state, .requestingPermission)
        permissions[1].resume(returning: false)
        await current.value
        guard case .failed = recorder.state else { return XCTFail("Current denial must be shown") }
        recorder.discard()
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSReliability-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func memoryContainer() throws -> ModelContainer {
        let schema = Schema([Course.self])
        return try ModelContainer(for: schema, configurations: [.init(schema: schema, isStoredInMemoryOnly: true)])
    }
}

@MainActor
private final class SuspendedAcademicProvider: CampusAcademicProviding {
    var continuation: CheckedContinuation<String, Never>?
    var graduationCalls = 0
    func fetchTeachingPlan() async throws -> String { await withCheckedContinuation { continuation = $0 } }
    func fetchGraduationRequirements() async throws -> String { graduationCalls += 1; return "unused" }
    func fetchExamSchedule() async throws -> String { throw URLError(.unsupportedURL) }
    func fetchGradeRankings() async throws -> String { throw URLError(.unsupportedURL) }
}

private actor CountingPublishBackend: CommunityPublishBackend {
    var capabilityCalls = 0
    func requireCapabilities(for mediaKinds: Set<CommunityPublishMediaKind>) async throws {
        capabilityCalls += 1; throw URLError(.unsupportedURL) }
    func pendingPostContext(postID: UUID) async throws -> CommunityPendingPostContext? { nil }
    func abortPendingPost(postID: UUID) async throws {}
    func createPendingPost(id: UUID, input: CreatePostInput, imageCount: Int,
                           attachmentCount: Int) async throws -> UUID { throw URLError(.unsupportedURL) }
    func fetchPost(postID: UUID) async throws -> CommunityPost? { nil }
    func validateAndAttachPostImage(
        postID: UUID,
        imageID: UUID,
        fullPath: String,
        thumbnailPath: String,
        sortOrder: Int
    ) async throws {}
    func validateAndAttachPostAttachment(
        postID: UUID,
        attachmentID: UUID,
        objectPath: String,
        displayName: String,
        sortOrder: Int
    ) async throws {}
    func uploadMedia(
        kind: String,
        taskID: UUID,
        mediaID: UUID,
        name: String,
        contentType: String,
        fileURL: URL,
        descriptor: CommunityBackgroundTransferDescriptor
    ) async throws -> String { throw URLError(.unsupportedURL) }
}
