import SwiftData
import XCTest
@testable import Leafy

@MainActor
final class ScheduleMemoPersistenceTests: XCTestCase {
    func testFailedInsertRemovesOnlyNewMemoAndAllMedia() throws {
        let context = try makeContext()
        let other = ScheduleMemo(body: "original")
        context.insert(other)
        try context.save()
        other.updateBody("pending #keep")
        let memo = ScheduleMemo(body: "draft")
        let image = ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "new.jpg")
        let attachment = ScheduleMemoAttachment(memoID: memo.id, sortOrder: 0, originalFilename: "draft.pdf", localFilename: "new.pdf", contentTypeIdentifier: "com.adobe.pdf")
        let audio = ScheduleMemoAudio(memoID: memo.id, localFilename: "new.m4a", duration: 2)
        XCTAssertThrowsError(try ScheduleMemoPersistence.insert(memo, resources: [image, attachment, audio], in: context, save: failSave))
        XCTAssertEqual(other.body, "pending #keep")
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduleMemo>()).map(\.id), [other.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoAttachment>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoAudio>()), 0)
    }

    func testFailedUpdateRestoresFieldsAndRemovedMediaWithoutDiscardingOtherEdits() throws {
        let context = try makeContext()
        let memo = ScheduleMemo(body: "original #old", kind: .article, title: "Title")
        let other = ScheduleMemo(body: "other")
        let oldImage = ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "old.jpg")
        try ScheduleMemoPersistence.insert(memo, resources: [oldImage, other], in: context)
        let oldDate = memo.updatedAt
        other.updateBody("pending")
        let newImage = ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "new.jpg")
        let draft = "replacement #new"
        XCTAssertThrowsError(try ScheduleMemoPersistence.update(memo, title: "Replacement", body: draft, inserting: [newImage], removing: [oldImage], in: context, save: failSave))
        XCTAssertEqual(memo.title, "Title")
        XCTAssertEqual(memo.body, "original #old")
        XCTAssertEqual(memo.tags, ["old"])
        XCTAssertEqual(memo.updatedAt, oldDate)
        XCTAssertEqual(other.body, "pending")
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduleMemoImage>()).map(\.id), [oldImage.id])
    }

    func testCleanupFailureCommitsEditAndRetainsIntentForRetry() throws {
        let context = try makeContext()
        let directory = try temporaryDirectory()
        let memo = ScheduleMemo(body: "original")
        let image = ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "removed.jpg")
        try ScheduleMemoPersistence.insert(memo, resources: [image], in: context)
        let url = directory.appendingPathComponent(image.localFilename)
        try Data("image".utf8).write(to: url)
        let queue = directory.appendingPathComponent("cleanup.json")
        let warning = try ScheduleMemoPersistence.update(
            memo, title: nil, body: "saved", removing: [image], files: [.init(image, url: url)], in: context,
            cleanup: LocalFileCleanup(queueURL: queue, removeFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        )
        XCTAssertNotNil(warning)
        XCTAssertEqual(memo.body, "saved")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try LocalFileCleanup(queueURL: queue).retry(in: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(memo.body, "saved")
    }

    func testFailedEditKeepsRemovedFileAndRetryPreservesLiveMedia() throws {
        let context = try makeContext()
        let directory = try temporaryDirectory()
        let memo = ScheduleMemo(body: "original")
        let image = ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "live.jpg")
        try ScheduleMemoPersistence.insert(memo, resources: [image], in: context)
        let url = directory.appendingPathComponent(image.localFilename)
        try Data("image".utf8).write(to: url)
        let cleanup = LocalFileCleanup(queueURL: directory.appendingPathComponent("cleanup.json"))
        XCTAssertThrowsError(try ScheduleMemoPersistence.update(memo, title: nil, body: "draft", removing: [image], files: [.init(image, url: url)], in: context, cleanup: cleanup, save: failSave))
        try context.save()
        try cleanup.retry(in: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(memo.body, "original")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduleMemoImage>()).map(\.id), [image.id])
    }

    func testCorruptCleanupIntentPreventsAnyEditOrResourceMutation() throws {
        let context = try makeContext()
        let directory = try temporaryDirectory()
        let memo = ScheduleMemo(body: "original")
        let image = ScheduleMemoImage(memoID: memo.id, sortOrder: 0, localFilename: "old.jpg")
        try ScheduleMemoPersistence.insert(memo, resources: [image], in: context)
        let queue = directory.appendingPathComponent("cleanup.json")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: queue)
        var saved = false
        XCTAssertThrowsError(try ScheduleMemoPersistence.update(memo, title: nil, body: "draft", removing: [image], files: [.init(image, url: directory.appendingPathComponent(image.localFilename))], in: context, cleanup: LocalFileCleanup(queueURL: queue), save: { _ in saved = true }))
        XCTAssertFalse(saved)
        XCTAssertEqual(memo.body, "original")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleMemoImage>()), 1)
        XCTAssertEqual(try Data(contentsOf: queue), corrupt)
    }

    private func failSave(_ context: ModelContext) throws { throw CocoaError(.fileWriteOutOfSpace) }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([ScheduleMemo.self, ScheduleMemoImage.self, ScheduleMemoAttachment.self, ScheduleMemoAudio.self])
        let container = try ModelContainer(for: schema, configurations: [.init(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
