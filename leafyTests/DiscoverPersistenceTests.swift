import SwiftData
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import XCTest
@testable import Leafy

@MainActor
final class DiscoverPersistenceTests: XCTestCase {
    func testManualGradeFailurePreservesOtherPendingEditsAndOriginalFields() throws {
        let context = try memoryContext()
        let grade = Grade(term: "2026-1", courseName: "Math", credit: "2", score: "80", type: "Required")
        let other = Grade(term: "2026-1", courseName: "Physics", credit: "3", score: "70", type: "Required")
        context.insert(grade); context.insert(other)
        try context.save()
        other.score = "pending"
        let previousDate = grade.updatedAt
        XCTAssertThrowsError(try ManualGradeStore.save(draft: .init(term: "new", courseName: "Changed", credit: "4", score: "90", type: "Elective"), editing: grade, in: context, save: fail))
        XCTAssertEqual(grade.courseName, "Math")
        XCTAssertEqual(grade.updatedAt, previousDate)
        XCTAssertEqual(other.score, "pending")
        XCTAssertThrowsError(try ManualGradeStore.delete(grade, in: context, save: fail))
        XCTAssertFalse(grade.isDeleted)
        XCTAssertEqual(other.score, "pending")
    }

    func testManualGradeValidationRejectsInfinityAndNaN() {
        for credit in ["inf", "Infinity", "nan", "1e999"] {
            XCTAssertThrowsError(try ManualGradeDraft(term: "term", courseName: "name", credit: credit, score: "80").validated())
        }
    }

    func testResumeReplacementSaveFailureKeepsOldFileAndUnrelatedEdits() throws {
        let context = try memoryContext()
        let root = try temporaryDirectory()
        let old = root.appendingPathComponent("old.pdf")
        let replacement = root.appendingPathComponent("replacement.pdf")
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: replacement)
        let cleanup = LocalFileCleanup(queueURL: root.appendingPathComponent("cleanup.json"))
        let imported = try CareerResumePersistence.importFile(from: old, replacing: nil, in: context, cleanup: cleanup).document
        let oldURL = try XCTUnwrap(CareerDocumentFileStore.fileURL(for: imported))
        defer { try? FileManager.default.removeItem(at: oldURL) }
        let other = Grade(term: "term", courseName: "other", credit: "1", score: "80", type: "")
        context.insert(other); try context.save(); other.score = "pending"
        XCTAssertThrowsError(try CareerResumePersistence.importFile(from: replacement, replacing: imported, in: context, cleanup: cleanup, save: fail))
        XCTAssertEqual(imported.originalFilename, "old.pdf")
        XCTAssertEqual(try Data(contentsOf: oldURL), Data("old".utf8))
        XCTAssertEqual(other.score, "pending")
    }

    func testResumeReplacementCleanupFailureIsRetryableAfterCommit() throws {
        let context = try memoryContext()
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("resume.pdf")
        try Data("old".utf8).write(to: source)
        let queue = root.appendingPathComponent("cleanup.json")
        let cleanup = LocalFileCleanup(queueURL: queue)
        let imported = try CareerResumePersistence.importFile(from: source, replacing: nil, in: context, cleanup: cleanup).document
        let oldURL = try XCTUnwrap(CareerDocumentFileStore.fileURL(for: imported))
        try Data("new".utf8).write(to: source)
        let failingCleanup = LocalFileCleanup(queueURL: queue, removeFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        let result = try CareerResumePersistence.importFile(from: source, replacing: imported, in: context, cleanup: failingCleanup)
        let newURL = try XCTUnwrap(CareerDocumentFileStore.fileURL(for: imported))
        defer { try? FileManager.default.removeItem(at: newURL) }
        XCTAssertNotNil(result.cleanupWarning)
        XCTAssertNotEqual(oldURL, newURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        try cleanup.retry(in: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL), Data("new".utf8))
    }

    func testHonorBatchFailureLeavesNoPartialRecordsOrFiles() throws {
        let context = try memoryContext()
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("honor.pdf")
        try Data("pdf".utf8).write(to: source)
        let cleanup = LocalFileCleanup(queueURL: root.appendingPathComponent("cleanup.json"))
        let before = (try? FileManager.default.contentsOfDirectory(atPath: HonorRecordFileStore.directoryURL.path)) ?? []
        XCTAssertThrowsError(try HonorRecordPersistence.importFiles([source, root.appendingPathComponent("missing.pdf")], in: context, cleanup: cleanup))
        XCTAssertTrue(try context.fetch(FetchDescriptor<HonorRecord>()).isEmpty)
        let after = (try? FileManager.default.contentsOfDirectory(atPath: HonorRecordFileStore.directoryURL.path)) ?? []
        XCTAssertEqual(Set(before), Set(after))
    }

    func testMedicalSaveFailureRestoresEntryAndRetainsUnrelatedEdits() throws {
        let context = try memoryContext()
        let root = try temporaryDirectory()
        let entry = MedicalLedgerEntry(hospitalName: "Original", totalExpense: 123.456, note: " exact ")
        let other = Grade(term: "term", courseName: "other", credit: "1", score: "80", type: "")
        context.insert(entry); context.insert(other); try context.save()
        other.score = "pending"
        var draft = MedicalLedgerDraft(entry: entry)
        draft.hospitalName = "New"
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2), format: format).image { _ in UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 3, height: 2)) }
        let photo = MedicalLedgerPendingPhoto(originalFilename: "receipt.jpg", jpegData: try XCTUnwrap(image.jpegData(compressionQuality: 1)), image: image)
        let before = (try? FileManager.default.contentsOfDirectory(atPath: MedicalLedgerPhotoStore.directoryURL.path)) ?? []
        XCTAssertThrowsError(try MedicalLedgerPersistence.save(draft: draft, pendingPhotos: [photo], editing: entry, in: context,
            cleanup: LocalFileCleanup(queueURL: root.appendingPathComponent("cleanup.json")), save: fail))
        XCTAssertEqual(entry.hospitalName, "Original")
        XCTAssertEqual(entry.totalExpense, 123.456)
        XCTAssertEqual(entry.note, " exact ")
        XCTAssertEqual(other.score, "pending")
        XCTAssertTrue(try context.fetch(FetchDescriptor<MedicalLedgerPhoto>()).isEmpty)
        let after = (try? FileManager.default.contentsOfDirectory(atPath: MedicalLedgerPhotoStore.directoryURL.path)) ?? []
        XCTAssertEqual(Set(before), Set(after))
        XCTAssertEqual(draft.hospitalName, "New")
    }

    func testMedicalArchiveRejectsMissingReceiptInsteadOfReportingCompleteArchive() throws {
        let entry = MedicalLedgerEntry()
        let photo = MedicalLedgerPhoto(entryID: entry.id.uuidString, originalFilename: "missing.jpg", localFilename: "missing.jpg")
        XCTAssertThrowsError(try MedicalLedgerExporter.makeZipData(entries: [entry], photos: [photo], photoDataProvider: { _ in nil }))
    }

    func testNotificationBatchFailureRemovesEveryAttemptedRequest() async {
        let requests = ["first", "second", "third"].map {
            UNNotificationRequest(identifier: $0, content: UNMutableNotificationContent(), trigger: nil)
        }
        var added: [String] = []
        var removed: [String] = []
        do {
            _ = try await LocalNotificationBatch.install(requests, scope: CampusOperationScope(), isCurrent: { true }, add: {
                added.append($0.identifier)
                if $0.identifier == "second" { throw CocoaError(.fileWriteOutOfSpace) }
            }, remove: { removed = $0 })
            XCTFail("The partial batch must fail")
        } catch { }
        XCTAssertEqual(added, ["first", "second"])
        XCTAssertEqual(removed, ["first", "second"])
    }

    func testNotificationBatchRejectsSupersededRunAfterAwait() async {
        let request = UNNotificationRequest(identifier: "old-run", content: UNMutableNotificationContent(), trigger: nil)
        var current = true
        var removed: [String] = []
        do {
            _ = try await LocalNotificationBatch.install([request], scope: CampusOperationScope(), isCurrent: { current }, add: { _ in
                current = false
            }, remove: { removed = $0 })
            XCTFail("A superseded run must be rejected")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(removed, ["old-run"])
    }

    func testCorruptReminderSettingsAreNotOverwrittenByDefaults() throws {
        let name = "ReminderSettings-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let key = ScheduleReportSettingsStore.scopedStorageKey(defaults: defaults)
        let corrupt = Data("invalid".utf8)
        defaults.set(corrupt, forKey: key)
        XCTAssertThrowsError(try ScheduleReportSettingsStore.loadForEditing(defaults: defaults))
        XCTAssertThrowsError(try ScheduleReportSettingsStore.save(.disabled, defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: key), corrupt)
    }

    func testDeletingProjectKeepingContentsRestoresOwnershipWhenSaveFails() throws {
        let schema = Schema([LearningProject.self, LearningProjectTask.self, LearningMaterialDocument.self, StudyTimeRecord.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
        context.autosaveEnabled = false
        let project = LearningProject(title: "Project")
        let task = LearningProjectTask(projectID: project.id.uuidString, title: "Task")
        context.insert(project); context.insert(task); try context.save()
        let previousDate = task.updatedAt
        XCTAssertThrowsError(try LearningProjectContentRelocation.deleteProjectKeepingContents(project, materials: [], tasks: [task], records: [], modelContext: context, save: fail))
        XCTAssertEqual(task.projectID, project.id.uuidString)
        XCTAssertEqual(task.updatedAt, previousDate)
        XCTAssertFalse(project.isDeleted)
    }

    func testManualExamStorageUsesTwentyFourHourClockRegardlessOfDisplayLanguage() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 20, minute: 5)))
        let clock = DateFormatters.examTime.string(from: date)
        XCTAssertEqual(clock, "20:05")
        XCTAssertNotNil(DateFormatters.examStart.date(from: "2026-10-23 " + clock))
    }

    private func memoryContext() throws -> ModelContext {
        let schema = Schema([Grade.self, CareerResumeDocument.self, HonorRecord.self, MedicalLedgerEntry.self, MedicalLedgerPhoto.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
        context.autosaveEnabled = false
        return context
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func fail(_ context: ModelContext) throws { throw CocoaError(.fileWriteOutOfSpace) }
}
