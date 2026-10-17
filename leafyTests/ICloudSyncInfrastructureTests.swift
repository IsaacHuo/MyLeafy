import CloudKit
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
