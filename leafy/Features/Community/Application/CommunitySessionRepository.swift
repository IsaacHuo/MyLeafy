import Foundation

nonisolated protocol CommunityIdentitySessionRepository: Sendable {
    var currentAuthUserID: UUID? { get }

    func ensureAnonymousSession() async throws
    func fetchCurrentProfile() async throws -> CommunityProfile?
    func bootstrapCommunityUser(
        eduID: String,
        displayName: String,
        campusID: String
    ) async throws -> CommunityProfile
    func signOut(localOnly: Bool) async
    func deleteCurrentAccount() async throws
    func updateProfile(
        input: CommunityProfileUpdateInput,
        avatar: CommunityImageUpload?,
        cover: CommunityImageUpload?,
        resetCoverToDefault: Bool
    ) async throws -> CommunityProfile
    func requestEmailVerification(input: CommunityEmailBindingInput) async throws -> CommunityProfile
    func verifyEmailBinding(input: CommunityEmailVerificationInput) async throws -> CommunityProfile
    func submitCampusMembershipRequest(schoolName: String) async throws -> CommunityProfile
    func searchCommunityCampuses(query: String, limit: Int) async throws -> [CommunityCampusOption]
    func selectCommunityCampus(campusID: String) async throws -> CommunityProfile
    func fetchCurrentCampusMembershipRequest() async throws -> CommunityCampusMembershipRequest?
    func submitCommunitySchoolChangeRequest(campusID: String) async throws -> CommunityCampusMembershipRequest
}
