import XCTest
@testable import Leafy

@MainActor
final class CommunitySessionScopeTests: XCTestCase {
    func testDetachedSessionRejectsLateProfileRestore() async {
        let started = expectation(description: "Restore suspended")
        let repository = SuspendedIdentityRepository(started: started)
        let manager = CommunitySessionManager(repository: repository)
        let loading = Task { await manager.restoreProfileIfPossible() }
        await fulfillment(of: [started], timeout: 3)
        manager.detachFromSchoolSession()
        await repository.resume()
        await loading.value
        XCTAssertNil(manager.profile)
        XCTAssertNil(manager.bootstrapError)
    }

    func testDetachedSessionRejectsLateEmailMutation() async {
        let started = expectation(description: "Email update suspended")
        let repository = SuspendedIdentityRepository(started: started)
        let manager = CommunitySessionManager(repository: repository)
        let updating = Task { try await manager.requestEmailVerification(input: .init(email: "student@example.com")) }
        await fulfillment(of: [started], timeout: 3)
        manager.detachFromSchoolSession()
        await repository.resume()
        do { try await updating.value; XCTFail("Detached update applied") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(manager.profile)
    }
}

private actor SuspendedIdentityRepository: CommunityIdentitySessionRepository {
    nonisolated let currentAuthUserID: UUID? = UUID()
    private let started: XCTestExpectation
    private var continuation: CheckedContinuation<CommunityProfile, Never>?
    init(started: XCTestExpectation) { self.started = started }
    private func wait() async -> CommunityProfile {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }
    func resume() {
        continuation?.resume(returning: CommunityProfile(
            id: currentAuthUserID!, eduID: "old", nickname: "Old identity", displayName: nil,
            avatarPath: nil, major: nil, grade: nil, boundEmail: nil, pendingBoundEmail: nil,
            emailVerificationSentAt: nil, profileEditedAt: nil, isProfileComplete: true,
            createdAt: "2026-10-23T00:00:00Z", updatedAt: "2026-10-23T00:00:00Z",
            signedAvatarURL: nil, avatarURL: nil
        ))
        continuation = nil
    }
    func ensureAnonymousSession() async throws {}
    func fetchCurrentProfile() async throws -> CommunityProfile? { await wait() }
    func bootstrapCommunityUser(eduID: String, displayName: String, campusID: String) async throws -> CommunityProfile { await wait() }
    func signOut(localOnly: Bool) async {}
    func deleteCurrentAccount() async throws {}
    func updateProfile(input: CommunityProfileUpdateInput, avatar: CommunityImageUpload?, cover: CommunityImageUpload?, resetCoverToDefault: Bool) async throws -> CommunityProfile { await wait() }
    func requestEmailVerification(input: CommunityEmailBindingInput) async throws -> CommunityProfile { await wait() }
    func verifyEmailBinding(input: CommunityEmailVerificationInput) async throws -> CommunityProfile { await wait() }
    func submitCampusMembershipRequest(schoolName: String) async throws -> CommunityProfile { await wait() }
    func searchCommunityCampuses(query: String, limit: Int) async throws -> [CommunityCampusOption] { [] }
    func selectCommunityCampus(campusID: String) async throws -> CommunityProfile { await wait() }
    func fetchCurrentCampusMembershipRequest() async throws -> CommunityCampusMembershipRequest? { nil }
    func submitCommunitySchoolChangeRequest(campusID: String) async throws -> CommunityCampusMembershipRequest { throw CancellationError() }
}
