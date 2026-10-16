import CloudKit
import XCTest
@testable import Leafy

@MainActor
final class ICloudSyncInfrastructureTests: XCTestCase {
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
