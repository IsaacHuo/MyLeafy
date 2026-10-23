import CloudKit
import Foundation
import SwiftData
import XCTest
@testable import Leafy

@MainActor
final class ICloudSyncInfrastructureTests: XCTestCase {
    func testBurstOfLocalNotificationsCollectsOnceAndBackgroundFlushDoesNotRepeatIt() {
        let work = ICloudSyncWorkScheduler()
        var collections = 0
        for _ in 0..<25 {
            work.schedule(after: .seconds(3_600)) { collections += 1 }
        }
        XCTAssertEqual(collections, 0)
        work.flush()
        XCTAssertEqual(collections, 1)
        work.flush()
        XCTAssertEqual(collections, 1)
    }

    func testIdentityChangeOrDisablingCancelsPendingCollection() {
        let work = ICloudSyncWorkScheduler()
        var collections = 0
        work.schedule(after: .seconds(3_600)) { collections += 1 }
        work.cancel()
        work.flush()
        XCTAssertEqual(collections, 0)
    }

    func testInitializationRecoveryBacksOffAndHonorsServerRetryAfter() {
        let delays = (1...5).map { ICloudSyncScheduling.recoveryDelay(failures: $0) }
        XCTAssertEqual(delays, [300, 600, 1_200, 1_800, 1_800])
        XCTAssertEqual(ICloudSyncScheduling.recoveryDelay(failures: 1, retryAfter: 3_600), 3_600)
    }

    func testDeferredOfflineEditsKeepLatestNoteAndDeletionInPersistentQueue() throws {
        var journal = ICloudSyncJournal()
        let first = ICloudSyncValue(key: "CourseNote/note", payload: Data("first".utf8), modifiedAt: Date())
        var edited = first
        edited.payload = Data("edited".utf8)
        edited.revision = "new-revision"
        journal.capture([first])
        journal.capture([edited])
        XCTAssertEqual(journal.pending, [first.key])
        XCTAssertEqual(journal.records[first.key]?.payload, edited.payload)
        journal.capture([])
        journal.automaticRetryAt = Date().addingTimeInterval(300)
        let reloaded = try JSONDecoder().decode(ICloudSyncJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertEqual(reloaded.pending, [first.key])
        XCTAssertEqual(reloaded.records[first.key]?.deleted, true)
        XCTAssertEqual(reloaded.automaticRetryAt, journal.automaticRetryAt)
    }

    func testJournalWithoutRecoveryDeadlineRetainsExistingPendingRecords() throws {
        var journal = ICloudSyncJournal()
        let value = ICloudSyncValue(key: "CustomSchedule/event", payload: Data("schedule".utf8), modifiedAt: Date())
        journal.capture([value])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
        json.removeValue(forKey: "automaticRetryAt")
        let reloaded = try JSONDecoder().decode(ICloudSyncJournal.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(reloaded.automaticRetryAt)
        XCTAssertEqual(reloaded.pending, journal.pending)
        XCTAssertEqual(reloaded.records, journal.records)
    }

    func testUnchangedLocalCaptureDoesNotRequestAnotherRetryWhilePending() {
        var journal = ICloudSyncJournal()
        let value = ICloudSyncValue(key: "preference/theme", payload: Data("green".utf8), modifiedAt: Date())
        XCTAssertTrue(journal.capture([value]))
        XCTAssertFalse(journal.pending.isEmpty)
        XCTAssertFalse(journal.capture([value]))
        XCTAssertFalse(journal.pending.isEmpty)
    }
    func testExistingZoneDoesNotTriggerAnotherZoneWrite() async throws {
        var reads = 0, writes = 0
        try await ICloudZonePreparation.ensure(fetch: { reads += 1 }, create: { writes += 1 })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(writes, 0)
    }
    func testOnlyMissingZoneCanTriggerCreation() async throws {
        var writes = 0
        try await ICloudZonePreparation.ensure(fetch: { throw CKError(.zoneNotFound) }, create: { writes += 1 })
        XCTAssertEqual(writes, 1)
    }
    func testServerRejectionIsPropagatedWithoutCreatingOrReplacingZone() async {
        var writes = 0
        do {
            try await ICloudZonePreparation.ensure(fetch: { throw CKError(.serverRejectedRequest) }, create: { writes += 1 })
            XCTFail("Server rejection must remain visible")
        } catch { XCTAssertEqual((error as? CKError)?.code, .serverRejectedRequest) }
        XCTAssertEqual(writes, 0)
    }
    func testZoneCreationFailureIsNotHidden() async {
        do {
            try await ICloudZonePreparation.ensure(fetch: { throw CKError(.zoneNotFound) }, create: { throw CKError(.permissionFailure) })
            XCTFail("Creation failure must remain visible")
        } catch { XCTAssertEqual((error as? CKError)?.code, .permissionFailure) }
    }
    func testHTTP500DiagnosticContainsStageAndRequestWithoutPayloadOrHeaders() {
        let underlying = NSError(domain: "CKInternalErrorDomain", code: 2000,
            userInfo: ["CKHTTPStatus": 500, "RequestUUID": "request-123", "CKDHTTPHeaders": ["Authorization": "secret-header"]])
        let error = NSError(domain: CKErrorDomain, code: CKError.serverRejectedRequest.rawValue,
            userInfo: [NSUnderlyingErrorKey: underlying, "recordPayload": "private-course-note"])
        let diagnostic = ICloudSyncDiagnostic(error: error, phase: .cloudSpace,
            container: "iCloud.com.isaachuo.leafy", environment: "Development")
        XCTAssertTrue(diagnostic.message.contains("准备云端空间"))
        XCTAssertTrue(diagnostic.message.contains("HTTP 500"))
        XCTAssertTrue(diagnostic.details.contains("RequestUUID：request-123"))
        XCTAssertTrue(diagnostic.details.contains("Development"))
        XCTAssertFalse(diagnostic.details.contains("secret-header"))
        XCTAssertFalse(diagnostic.details.contains("private-course-note"))
    }
    func testPartialFailureExplainsRealCauseInsteadOfBatchCancellation() {
        let error = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue, userInfo: [
            CKPartialErrorsByItemIDKey: ["cancelled": CKError(.batchRequestFailed), "cause": CKError(.missingEntitlement)]
        ])
        let diagnostic = ICloudSyncDiagnostic(error: error, phase: .upload, container: "container", environment: "Production")
        XCTAssertTrue(diagnostic.message.contains("签名配置不可用"))
        XCTAssertTrue(diagnostic.details.contains("CKErrorDomain"))
    }
}

extension ICloudSyncInfrastructureTests {
    func testDuplicateCaptureReferencesDeduplicateButConflictingIDsAreRejected() throws {
        let file = ICloudSyncValue(key: "file/images/same.jpg", payload: Data(), modifiedAt: Date(), filePath: "images/same.jpg", fileDigest: "same")
        var repeated = file
        repeated.revision = "another-capture"
        XCTAssertEqual(try ICloudLocalData.uniqueCaptureValues([file, repeated]).count, 1)
        repeated.fileDigest = "different"
        XCTAssertThrowsError(try ICloudLocalData.uniqueCaptureValues([file, repeated]))
    }

    func testFailedCloudMergePreservesJournalAndRetriesOneConflictCopy() throws {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "merge-failure-" + UUID().uuidString)
        let identity = try XCTUnwrap(ActiveCampusContext.identity)
        let directory = try XCTUnwrap(CampusStoreScope.scopedStoreURL(for: identity)).deletingLastPathComponent()
        defer { manager.clearSession(); try? FileManager.default.removeItem(at: directory) }
        let container = try AppModelContainerFactory.make().container
        let note = CourseNote(courseKey: "course", text: "offline edit")
        container.mainContext.insert(note); try container.mainContext.save()
        let key = "CourseNote/" + note.id.uuidString.lowercased()
        let local = ICloudSyncValue(key: key, payload: try ICloudLocalData.encode(SyncedCourseNote(note)), modifiedAt: Date(timeIntervalSince1970: 1), revision: "local")
        var journal = ICloudSyncJournal()
        journal.records[key] = local
        journal.pending = [key]
        try journal.save(to: directory.appendingPathComponent("ICloudSync/journal.json"))
        let coordinator = ICloudSyncCoordinator()
        coordinator.configure(context: container.mainContext)
        var dto = SyncedCourseNote(note)
        dto.text = "remote edit"
        let remote = ICloudSyncValue(key: key, payload: try ICloudLocalData.encode(dto), modifiedAt: Date(timeIntervalSince1970: 2), revision: "remote")
        let record = CKRecord(recordType: "PersonalValue", recordID: .init(recordName: remote.recordName, zoneID: .init(zoneName: "personal-" + identity.scopeKey)))
        record["value"] = try ICloudLocalData.encode(remote) as NSData
        try coordinator.receive(record)
        XCTAssertThrowsError(try coordinator.applyInbox(save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(coordinator.journal.records[key], local)
        XCTAssertEqual(coordinator.journal.records.count, 1)
        XCTAssertEqual(coordinator.journal.pending, [key])
        XCTAssertNotNil(coordinator.journal.inbox[key])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CourseNote>()).map(\.text), ["offline edit"])
        try coordinator.applyInbox()
        let notes = try ModelContext(container).fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(Set(notes.map(\.text)), ["offline edit", "remote edit"])
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(coordinator.journal.inbox.isEmpty)
    }
}


extension ICloudSyncInfrastructureTests {
    func testWaitingAssetDoesNotHideNewlyCommittedLocalNoteFromMerge() throws {
        let manager = ActiveCampusContext.networkManager
        manager.persistAuthenticatedIdentity(eduID: "waiting-asset-" + UUID().uuidString)
        let identity = try XCTUnwrap(ActiveCampusContext.identity)
        let directory = try XCTUnwrap(CampusStoreScope.scopedStoreURL(for: identity)).deletingLastPathComponent()
        defer { manager.clearSession(); try? FileManager.default.removeItem(at: directory) }
        let container = try AppModelContainerFactory.make().container
        let note = CourseNote(courseKey: "course", text: "previously journaled")
        container.mainContext.insert(note); try container.mainContext.save()
        let key = "CourseNote/" + note.id.uuidString.lowercased()
        var journal = ICloudSyncJournal()
        journal.records[key] = .init(key: key, payload: try ICloudLocalData.encode(SyncedCourseNote(note)), modifiedAt: Date(timeIntervalSince1970: 1), revision: "old")
        try journal.save(to: directory.appendingPathComponent("ICloudSync/journal.json"))
        let coordinator = ICloudSyncCoordinator()
        coordinator.configure(context: container.mainContext)
        func receive(_ value: ICloudSyncValue) throws {
            let record = CKRecord(recordType: "PersonalValue", recordID: .init(recordName: value.recordName, zoneID: .init(zoneName: "personal-" + identity.scopeKey)))
            record["value"] = try ICloudLocalData.encode(value) as NSData
            try coordinator.receive(record)
        }
        let image = ScheduleMemoImage(memoID: UUID(), sortOrder: 0, localFilename: UUID().uuidString + ".jpg")
        let waiting = ICloudSyncValue(key: "ScheduleMemoImage/" + image.id.uuidString.lowercased(), payload: try ICloudLocalData.encode(SyncedScheduleMemoImage(image)), modifiedAt: Date())
        try receive(waiting)
        note.text = "new local edit while waiting"
        note.updatedAt = Date()
        try container.mainContext.save()
        var remote = SyncedCourseNote(note)
        remote.text = "new remote edit"
        try receive(.init(key: key, payload: try ICloudLocalData.encode(remote), modifiedAt: Date().addingTimeInterval(10), revision: "remote"))
        try coordinator.applyInbox()
        let saved = try ModelContext(container).fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(Set(saved.map(\.text)), ["new local edit while waiting", "new remote edit"])
        XCTAssertEqual(saved.count, 2)
        XCTAssertNotNil(coordinator.journal.inbox[waiting.key])
    }

    func testMalformedRemoteCourseAndCellDoNotReplaceValidLocalData() throws {
        let schema = Schema([Course.self, TimetableCellReminder.self])
        let container = try ModelContainer(for: schema, configurations: [.init(schema: schema, isStoredInMemoryOnly: true)])
        let course = Course(courseName: "Keep", teacher: "T", room: "R", location: "L", dayOfWeek: 1, weeks: [1], duration: [1])
        container.mainContext.insert(course); try container.mainContext.save()
        var invalid = SyncedCourse(course)
        invalid.weeks = [Int.max]
        let value = ICloudSyncValue(key: "school/courses", payload: try ICloudLocalData.encode([invalid]), modifiedAt: Date())
        XCTAssertThrowsError(try ICloudLocalData.apply(value, context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Course>()).map(\.courseName), ["Keep"])
        let cell = TimetableCellReminder(week: Int.max, dayOfWeek: 1, period: 1, title: "Invalid")
        let malformed = ICloudSyncValue(key: "TimetableCellReminder/" + cell.id.uuidString.lowercased(), payload: try ICloudLocalData.encode(SyncedTimetableCellReminder(cell)), modifiedAt: Date())
        XCTAssertThrowsError(try ICloudLocalData.apply(malformed, context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TimetableCellReminder>()), 0)
    }
}


extension ICloudSyncInfrastructureTests {
    func testReplayedRemotePayloadDoesNotBecomeANewPendingLocalEdit() {
        let key = "CourseNote/replayed"
        let previous = ICloudSyncValue(key: key, payload: Data("previous".utf8),
            modifiedAt: Date(timeIntervalSince1970: 1), revision: "previous")
        let remote = ICloudSyncValue(key: key, payload: Data("remote already applied".utf8),
            modifiedAt: Date(timeIntervalSince1970: 2), revision: "remote")
        var current = remote
        current.modifiedAt = Date(timeIntervalSince1970: 90)
        current.revision = "fresh-capture"
        var journal = ICloudSyncJournal()
        journal.records[key] = previous
        journal.inbox[key] = remote

        XCTAssertFalse(journal.captureBeforeMerge([current], incoming: [remote], now: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(journal.pending.isEmpty)
        XCTAssertEqual(journal.records[key], previous)
        XCTAssertEqual(journal.inbox[key], remote)
        XCTAssertEqual(ICloudSyncValue.winner(local: journal.records[key]!, remote: remote), remote)
    }

    func testMissingCommittedLocalRecordPreservesDeletionPriorityBeforeMerge() throws {
        let key = "CourseNote/deleted-locally"
        let previous = ICloudSyncValue(key: key, payload: Data("previous".utf8),
            modifiedAt: Date(timeIntervalSince1970: 1), revision: "previous")
        let remote = ICloudSyncValue(key: key, payload: Data("newer remote edit".utf8),
            modifiedAt: Date(timeIntervalSince1970: 20), revision: "remote")
        let deletionDate = Date(timeIntervalSince1970: 10)
        var journal = ICloudSyncJournal()
        journal.records[key] = previous
        journal.inbox[key] = remote

        XCTAssertTrue(journal.captureBeforeMerge([], incoming: [remote], now: deletionDate))
        let deleted = try XCTUnwrap(journal.records[key])
        XCTAssertTrue(deleted.deleted)
        XCTAssertTrue(deleted.payload.isEmpty)
        XCTAssertEqual(deleted.modifiedAt, deletionDate)
        XCTAssertNotEqual(deleted.revision, previous.revision)
        XCTAssertEqual(journal.pending, [key])
        XCTAssertEqual(journal.inbox[key], remote)
        XCTAssertEqual(ICloudSyncValue.winner(local: deleted, remote: remote), deleted)
    }
}

extension ICloudSyncInfrastructureTests {
    func testFailedCellMergeReplaysOneJSONConflictCopyAndAcknowledgesOnlyAfterCommit() throws {
        let defaults = UserDefaults.standard
        let previousIdentity = ActiveCampusContext.identity
        let wasDemoEnabled = ReviewDemoMode.isEnabled
        let identity = CampusIdentity(campusID: .bjfu, eduID: "json-conflict-" + UUID().uuidString,
            displayName: nil, portal: .undergraduate)
        let directory = try XCTUnwrap(CampusStoreScope.scopedStoreURL(for: identity)).deletingLastPathComponent()
        let legacyKey = CustomScheduleStore.storageKeyForTesting()
        let scopedKey = CampusScopedDefaults.key(legacyKey, identity: identity)
        let previousLegacy = defaults.object(forKey: legacyKey)
        let previousScoped = defaults.object(forKey: scopedKey)
        defer {
            defaults.set(previousLegacy, forKey: legacyKey)
            defaults.set(previousScoped, forKey: scopedKey)
            if let previousIdentity { CampusIdentityStore.activate(previousIdentity) } else { CampusIdentityStore.clear() }
            ReviewDemoMode.isEnabled = wasDemoEnabled
            try? FileManager.default.removeItem(at: directory)
        }
        // Prevent legacy-data adoption and restore both namespaces after the test.
        defaults.set(try JSONEncoder().encode([CustomScheduleEvent]()), forKey: scopedKey)
        ReviewDemoMode.disable()
        CampusIdentityStore.activate(identity)
        let container = try AppModelContainerFactory.make().container
        let startsAt = Date(timeIntervalSince1970: 2_000_000_000)
        let cell = TimetableCellReminder(week: 1, dayOfWeek: 1, period: 1, endPeriod: 2,
            title: "offline schedule", startsAt: startsAt, endsAt: startsAt.addingTimeInterval(3_600),
            updatedAt: Date(timeIntervalSince1970: 1))
        cell.cellKey = "audit-json-" + UUID().uuidString
        container.mainContext.insert(cell)
        try container.mainContext.save()
        let key = "TimetableCellReminder/" + cell.id.uuidString.lowercased()
        let local = ICloudSyncValue(key: key, payload: try ICloudLocalData.encode(SyncedTimetableCellReminder(cell)),
            modifiedAt: Date(timeIntervalSince1970: 1), revision: "local-json-conflict")
        var journal = ICloudSyncJournal()
        journal.records[key] = local
        journal.pending = [key]
        let journalURL = directory.appendingPathComponent("ICloudSync/journal.json")
        try journal.save(to: journalURL)
        let coordinator = ICloudSyncCoordinator()
        coordinator.configure(context: container.mainContext)
        var remoteCell = SyncedTimetableCellReminder(cell)
        remoteCell.title = "remote schedule"
        remoteCell.updatedAt = Date(timeIntervalSince1970: 2)
        let remote = ICloudSyncValue(key: key, payload: try ICloudLocalData.encode(remoteCell),
            modifiedAt: Date(timeIntervalSince1970: 2), revision: "remote-json-conflict")
        let record = CKRecord(recordType: "PersonalValue", recordID: .init(recordName: remote.recordName,
            zoneID: .init(zoneName: "personal-" + identity.scopeKey)))
        record["value"] = try ICloudLocalData.encode(remote) as NSData
        try coordinator.receive(record)

        XCTAssertThrowsError(try coordinator.applyInbox(save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TimetableCellReminder>()).map(\.title), ["offline schedule"])
        let firstCopies = try CustomScheduleStore.loadForSync()
        let firstCopy = try XCTUnwrap(firstCopies.first)
        XCTAssertEqual(firstCopies.count, 1)
        XCTAssertEqual(firstCopy.title, "offline schedule（冲突副本）")
        XCTAssertEqual(firstCopy.startsAt, startsAt)
        let copyKey = "CustomSchedule/" + firstCopy.id
        XCTAssertEqual(coordinator.journal.records[key], local)
        XCTAssertEqual(coordinator.journal.pending, [key])
        XCTAssertNil(coordinator.journal.records[copyKey])
        XCTAssertEqual(coordinator.journal.inbox[key], remote)
        let failedJournal = try ICloudSyncJournal.load(from: journalURL)
        XCTAssertEqual(failedJournal.records[key], local)
        XCTAssertEqual(failedJournal.inbox[key], remote)
        XCTAssertNil(failedJournal.records[copyKey])

        try coordinator.applyInbox()
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<TimetableCellReminder>()).map(\.title), ["remote schedule"])
        let retriedCopies = try CustomScheduleStore.loadForSync()
        XCTAssertEqual(retriedCopies.map(\.id), [firstCopy.id])
        XCTAssertEqual(retriedCopies.first?.title, firstCopy.title)
        XCTAssertEqual(coordinator.journal.records[key], remote)
        XCTAssertNil(coordinator.journal.inbox[key])
        XCTAssertFalse(coordinator.journal.pending.contains(key))
        XCTAssertEqual(coordinator.journal.pending, [copyKey])
        XCTAssertNotNil(coordinator.journal.records[copyKey])
        let committedJournal = try ICloudSyncJournal.load(from: journalURL)
        XCTAssertEqual(committedJournal.records[key], remote)
        XCTAssertNil(committedJournal.inbox[key])
        XCTAssertEqual(committedJournal.pending, [copyKey])

        try coordinator.receive(record)
        try coordinator.applyInbox()
        XCTAssertEqual(try CustomScheduleStore.loadForSync().map(\.id), [firstCopy.id])
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<TimetableCellReminder>()), 1)
        XCTAssertNil(coordinator.journal.inbox[key])
    }
}

extension ICloudSyncInfrastructureTests {
    func testCommittedIncomingTextSupersedesNewerStalePendingJournalAfterRetry() throws {
        let previousIdentity = ActiveCampusContext.identity
        let wasDemoEnabled = ReviewDemoMode.isEnabled
        let identity = CampusIdentity(campusID: .bjfu, eduID: "committed-remote-" + UUID().uuidString,
            displayName: nil, portal: .undergraduate)
        let directory = try XCTUnwrap(CampusStoreScope.scopedStoreURL(for: identity)).deletingLastPathComponent()
        let defaults = UserDefaults.standard
        let legacyKey = CustomScheduleStore.storageKeyForTesting()
        let scopedKey = CampusScopedDefaults.key(legacyKey, identity: identity)
        let previousLegacy = defaults.object(forKey: legacyKey)
        let previousScoped = defaults.object(forKey: scopedKey)
        defer {
            defaults.set(previousLegacy, forKey: legacyKey)
            defaults.set(previousScoped, forKey: scopedKey)
            if let previousIdentity { CampusIdentityStore.activate(previousIdentity) } else { CampusIdentityStore.clear() }
            ReviewDemoMode.isEnabled = wasDemoEnabled
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(try JSONEncoder().encode([CustomScheduleEvent]()), forKey: scopedKey)
        ReviewDemoMode.disable()
        CampusIdentityStore.activate(identity)
        let container = try AppModelContainerFactory.make().container
        let committed = CourseNote(courseKey: "course", text: "committed B", updatedAt: Date(timeIntervalSince1970: 20))
        container.mainContext.insert(committed)
        try container.mainContext.save()
        let key = "CourseNote/" + committed.id.uuidString.lowercased()
        var staleDTO = SyncedCourseNote(committed)
        staleDTO.text = "stale pending A"
        staleDTO.updatedAt = Date(timeIntervalSince1970: 30)
        let stale = ICloudSyncValue(key: key, payload: try ICloudLocalData.encode(staleDTO),
            modifiedAt: Date(timeIntervalSince1970: 30), revision: "stale-A")
        let remote = ICloudSyncValue(key: key, payload: try ICloudLocalData.encode(SyncedCourseNote(committed)),
            modifiedAt: Date(timeIntervalSince1970: 20), revision: "incoming-B")
        var journal = ICloudSyncJournal()
        journal.records[key] = stale
        journal.pending = [key]
        let journalURL = directory.appendingPathComponent("ICloudSync/journal.json")
        try journal.save(to: journalURL)
        let coordinator = ICloudSyncCoordinator()
        coordinator.configure(context: container.mainContext)
        let record = CKRecord(recordType: "PersonalValue", recordID: .init(recordName: remote.recordName,
            zoneID: .init(zoneName: "personal-" + identity.scopeKey)))
        record["value"] = try ICloudLocalData.encode(remote) as NSData
        try coordinator.receive(record)

        XCTAssertThrowsError(try coordinator.applyInbox(save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(coordinator.journal.records[key], stale)
        XCTAssertEqual(coordinator.journal.pending, [key])
        XCTAssertEqual(coordinator.journal.inbox[key], remote)
        XCTAssertEqual(coordinator.journal.records.count, 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CourseNote>()).map(\.text), ["committed B"])

        try coordinator.applyInbox()
        let notes = try ModelContext(container).fetch(FetchDescriptor<CourseNote>())
        XCTAssertEqual(notes.map(\.id), [committed.id])
        XCTAssertEqual(notes.map(\.text), ["committed B"])
        XCTAssertEqual(coordinator.journal.records[key], remote)
        XCTAssertEqual(coordinator.journal.records.count, 1, "A stale journal value must not create a conflict upload")
        XCTAssertTrue(coordinator.journal.pending.isEmpty)
        XCTAssertTrue(coordinator.journal.inbox.isEmpty)
        let persisted = try ICloudSyncJournal.load(from: journalURL)
        XCTAssertEqual(persisted.records[key], remote)
        XCTAssertTrue(persisted.pending.isEmpty)
        XCTAssertTrue(persisted.inbox.isEmpty)
    }
}
