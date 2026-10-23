import Foundation
import SwiftData
import XCTest
@testable import Leafy

@MainActor
final class AppPersistenceAuditTests: XCTestCase {
    func testBulkDeleteFailureRestoresModelsAndPendingFields() throws {
        let context = try makeContext([CourseNote.self, Grade.self])
        let note = CourseNote(courseKey: "pending", text: "original")
        let grade = Grade(term: "2026-2027-1", courseName: "Original", credit: "1", score: "90", type: "必修")
        context.insert(note); context.insert(grade); try context.save()
        note.text = "pending"
        let queue = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: queue) }
        XCTAssertThrowsError(try AppSessionResetter.deleteLocalRecords(in: context, cleanup: .init(queueURL: queue), save: failSave))
        XCTAssertEqual(note.text, "pending")
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CourseNote>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Grade>()), 1)
    }

    func testLocalRecordDeletionFailureKeepsFileAndSuccessfulRetryCleansIt() throws {
        let context = try makeContext([CareerResumeDocument.self])
        let filename = UUID().uuidString + ".pdf"
        let resume = CareerResumeDocument(title: "Resume", originalFilename: "resume.pdf", localFilename: filename, contentTypeIdentifier: "com.adobe.pdf")
        context.insert(resume); try context.save()
        let directory = CareerDocumentFileStore.directoryURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(filename)
        let queue = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: queue) }
        try Data("resume".utf8).write(to: file)
        let cleanup = LocalFileCleanup(queueURL: queue)
        XCTAssertThrowsError(try AppSessionResetter.deleteLocalRecords(in: context, cleanup: cleanup, save: failSave))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerResumeDocument>()), 1)
        let warning = try AppSessionResetter.deleteLocalRecords(in: context, cleanup: cleanup)
        XCTAssertNil(warning)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareerResumeDocument>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanupProtectsCurrentFileButRemovesReplacedFileWithSameOwnerID() throws {
        let context = try makeContext([CareerResumeDocument.self])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resume = CareerResumeDocument(title: "Resume", originalFilename: "resume.pdf", localFilename: "old.pdf", contentTypeIdentifier: "com.adobe.pdf")
        context.insert(resume); try context.save()
        let old = directory.appendingPathComponent("old.pdf")
        let new = directory.appendingPathComponent("new.pdf")
        try Data("old".utf8).write(to: old); try Data("new".utf8).write(to: new)
        let cleanup = LocalFileCleanup(queueURL: directory.appendingPathComponent("queue.json"))
        try cleanup.enqueue([.init(resume, url: old), .init(resume, url: new)])
        resume.localFilename = "new.pdf"
        try context.save()
        try cleanup.retry(in: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
    }

    func testDemoSeedFailurePreservesDataOtherEditsAndBackup() throws {
        let context = try makeContext([Course.self, Grade.self, FavoriteClassroom.self, CourseNote.self])
        let course = Course(courseName: "Original", teacher: "T", room: "R", location: "L", dayOfWeek: 1, weeks: [1], duration: [1])
        let note = CourseNote(courseKey: "other", text: "original")
        context.insert(course); context.insert(note); try context.save()
        note.text = "pending"
        let defaults = try isolatedDefaults()
        XCTAssertThrowsError(try ReviewDemoDataSeeder.seed(using: context, defaults: defaults, save: failSave))
        XCTAssertEqual(note.text, "pending")
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).map(\.id), [course.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Grade>()), 0)
        XCTAssertNotNil(defaults.data(forKey: "reviewDemoMode.backup.courses"))
    }

    func testDemoRestoreRejectsCorruptOrPartialBackupBeforeDeletingData() throws {
        let context = try makeContext([Course.self, Grade.self])
        let course = Course(courseName: "Keep", teacher: "T", room: "R", location: "L", dayOfWeek: 1, weeks: [1], duration: [1])
        context.insert(course); try context.save()
        let defaults = try isolatedDefaults()
        let invalid = Data("invalid".utf8)
        defaults.set(invalid, forKey: "reviewDemoMode.backup.courses")
        let wasEnabled = ReviewDemoMode.isEnabled
        defer { ReviewDemoMode.isEnabled = wasEnabled }
        ReviewDemoMode.isEnabled = true
        XCTAssertThrowsError(try ReviewDemoDataSeeder.exit(using: context, defaults: defaults))
        XCTAssertTrue(ReviewDemoMode.isEnabled)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).map(\.id), [course.id])
        XCTAssertEqual(defaults.data(forKey: "reviewDemoMode.backup.courses"), invalid)
    }

    func testDemoRestoreSaveFailureKeepsBackupAndCurrentDataForRetry() throws {
        let context = try makeContext([Course.self, Grade.self, FavoriteClassroom.self])
        let course = Course(courseName: "Keep", teacher: "T", room: "R", location: "L", dayOfWeek: 1, weeks: [1], duration: [1])
        context.insert(course); try context.save()
        let defaults = try isolatedDefaults()
        XCTAssertThrowsError(try ReviewDemoDataSeeder.seed(using: context, defaults: defaults, save: failSave))
        let backup = defaults.data(forKey: "reviewDemoMode.backup.courses")
        let wasEnabled = ReviewDemoMode.isEnabled
        defer { ReviewDemoMode.isEnabled = wasEnabled }
        ReviewDemoMode.isEnabled = true
        XCTAssertThrowsError(try ReviewDemoDataSeeder.exit(using: context, defaults: defaults, save: failSave))
        XCTAssertTrue(ReviewDemoMode.isEnabled)
        XCTAssertEqual(defaults.data(forKey: "reviewDemoMode.backup.courses"), backup)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).map(\.id), [course.id])
    }

    func testAccountDeletionDoesNotCleanNewIdentityAfterRemoteCompletion() async {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "delete-a-" + UUID().uuidString)
        defer { manager.clearSession() }
        var cleaned = false
        do {
            _ = try await AppAccountDeletionCoordinator.delete(remotely: {
                manager.persistAuthenticatedIdentity(eduID: "delete-b-" + UUID().uuidString)
            }, locally: { cleaned = true })
            XCTFail("A completed remote deletion must not clean a replacement identity")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("身份已变化"))
        }
        XCTAssertFalse(cleaned)
        XCTAssertTrue(manager.authenticatedEduID?.hasPrefix("delete-b-") == true)
    }

    func testSharedFileSurvivesUntilItsLastModelReferenceIsDeleted() throws {
        let context = try makeContext([ScheduleMemoImage.self])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "shared.jpg")
        let second = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: "shared.jpg")
        context.insert(first); context.insert(second); try context.save()
        let file = directory.appendingPathComponent("shared.jpg")
        try Data("shared".utf8).write(to: file)
        let cleanup = LocalFileCleanup(queueURL: directory.appendingPathComponent("queue.json"))
        try cleanup.delete([first], files: [.init(first, url: file)], in: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try cleanup.delete([second], files: [.init(second, url: file)], in: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testDemoSuccessfulRestoreRetainsIDsSemesterAndGradeEditTime() throws {
        let context = try makeContext([Course.self, Grade.self, FavoriteClassroom.self])
        let courseID = UUID(), gradeID = UUID()
        let semester = "2024-2025-2"
        let updatedAt = Date(timeIntervalSince1970: 1234)
        let course = Course(id: courseID, courseName: "Original", teacher: "T", room: "R", location: "L", dayOfWeek: 1, weeks: [1], duration: [1], sourceSemesterID: semester)
        let grade = Grade(id: gradeID, term: semester, courseName: "Original", credit: "2", score: "90", type: "必修")
        grade.updatedAt = updatedAt
        let stableKey = course.stableCourseKey
        context.insert(course); context.insert(grade); try context.save()
        let defaults = try isolatedDefaults()
        XCTAssertThrowsError(try ReviewDemoDataSeeder.seed(using: context, defaults: defaults, save: failSave))
        course.courseName = "Demo replacement"
        grade.score = "100"
        try context.save()
        let wasEnabled = ReviewDemoMode.isEnabled
        defer { ReviewDemoMode.isEnabled = wasEnabled }
        try ReviewDemoDataSeeder.exit(using: context, defaults: defaults)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<Course>()).first)
        let restoredGrade = try XCTUnwrap(context.fetch(FetchDescriptor<Grade>()).first)
        XCTAssertEqual(restored.id, courseID)
        XCTAssertEqual(restored.sourceSemesterID, semester)
        XCTAssertEqual(restored.stableCourseKey, stableKey)
        XCTAssertEqual(restoredGrade.id, gradeID)
        XCTAssertEqual(restoredGrade.updatedAt, updatedAt)
        XCTAssertEqual(restoredGrade.score, "90")
        XCTAssertNil(defaults.data(forKey: "reviewDemoMode.backup.courses"))
    }

    func testWidgetLogoutArchiveClearsCachedWeather() {
        let archive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(courses: [], isAuthenticated: false,
            date: Date(), weather: .init(celsius: 25, observedAt: Date()))
        XCTAssertNil(archive.weather)
    }

    private func failSave(_ context: ModelContext) throws { throw CocoaError(.fileWriteOutOfSpace) }
    private func makeContext(_ types: [any PersistentModel.Type]) throws -> ModelContext {
        let schema = Schema(types)
        let container = try ModelContainer(for: schema, configurations: [.init(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "AppPersistenceAudit-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
