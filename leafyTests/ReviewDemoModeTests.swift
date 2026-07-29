import XCTest
@testable import Leafy

final class ReviewDemoModeTests: XCTestCase {
    func testDemoIdentityIsStableForOneInstallation() {
        let suiteName = "ReviewDemoModeTests.stable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ReviewDemoDataSeeder.demoEduID(userDefaults: defaults)
        let second = ReviewDemoDataSeeder.demoEduID(userDefaults: defaults)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("review-demo-"))
        XCTAssertNotEqual(first, "review-demo")
    }

    func testDemoIdentityIsUniquePerInstallationAndUsesBJFU() {
        let firstSuite = "ReviewDemoModeTests.first.\(UUID().uuidString)"
        let secondSuite = "ReviewDemoModeTests.second.\(UUID().uuidString)"
        guard let firstDefaults = UserDefaults(suiteName: firstSuite),
              let secondDefaults = UserDefaults(suiteName: secondSuite) else {
            return XCTFail("Could not create isolated UserDefaults")
        }
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }

        let first = ReviewDemoDataSeeder.demoEduID(userDefaults: firstDefaults)
        let second = ReviewDemoDataSeeder.demoEduID(userDefaults: secondDefaults)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(ReviewDemoDataSeeder.campusID, CampusID.bjfu.rawValue)
    }

    @MainActor
    func testColdStartRestoresInstallationUniqueDemoIdentity() {
        let wasEnabled = ReviewDemoMode.isEnabled
        defer { ReviewDemoMode.isEnabled = wasEnabled }

        let expectedEduID = ReviewDemoDataSeeder.demoEduID
        ReviewDemoMode.isEnabled = true

        let manager = SchoolNetworkManager()

        XCTAssertEqual(manager.authenticatedEduID, expectedEduID)
        XCTAssertNotEqual(manager.authenticatedEduID, "review-demo")
    }

    func testDemoAccountCannotEnterAccountDeletionFlow() {
        XCTAssertFalse(AppAccountDeletionPolicy.canDelete(isReviewDemoMode: true, eduID: nil))
        XCTAssertFalse(AppAccountDeletionPolicy.canDelete(isReviewDemoMode: false, eduID: "review-demo"))
        XCTAssertFalse(AppAccountDeletionPolicy.canDelete(
            isReviewDemoMode: false,
            eduID: "review-demo-7d9f06b3-f8c0-42e3-9c6f-0b54a0a2d3ca"
        ))
        XCTAssertTrue(AppAccountDeletionPolicy.canDelete(isReviewDemoMode: false, eduID: "230206108"))
    }

    @MainActor
    func testRemoteDeletionFailureDoesNotClearLocalData() async {
        var localCleanupRan = false

        do {
            _ = try await AppAccountDeletionCoordinator.delete {
                throw TestDeletionError.remote
            } locally: {
                localCleanupRan = true
            }
            XCTFail("Expected remote deletion failure")
        } catch {
            XCTAssertEqual(error as? TestDeletionError, .remote)
        }

        XCTAssertFalse(localCleanupRan)
    }

    @MainActor
    func testSuccessfulRemoteDeletionRunsLocalCleanup() async throws {
        var remoteDeletionRan = false
        var localCleanupRan = false

        let localError = try await AppAccountDeletionCoordinator.delete {
            remoteDeletionRan = true
        } locally: {
            localCleanupRan = true
        }

        XCTAssertTrue(remoteDeletionRan)
        XCTAssertTrue(localCleanupRan)
        XCTAssertNil(localError)
    }
}

private enum TestDeletionError: Error {
    case remote
}
