import Foundation
import Supabase

nonisolated struct LiveCommunitySessionRepository: CommunityIdentitySessionRepository {
    private let service = CommunityService.shared

    var currentAuthUserID: UUID? {
        LeafySupabase.shared.client?.auth.currentUser?.id
    }

    func ensureAnonymousSession() async throws {
        try await service.ensureAnonymousSession()
    }

    func fetchCurrentProfile() async throws -> CommunityProfile? {
        try await service.fetchCurrentProfile()
    }

    func bootstrapCommunityUser(
        eduID: String,
        displayName: String,
        campusID: String
    ) async throws -> CommunityProfile {
        try await service.bootstrapCommunityUser(
            eduID: eduID,
            displayName: displayName,
            campusID: campusID
        )
    }

    func signOut(localOnly: Bool) async {
        guard let client = LeafySupabase.shared.client else { return }
        if localOnly {
            try? await client.auth.signOut(scope: .local)
        } else {
            try? await client.auth.signOut()
        }
    }

    func deleteCurrentAccount() async throws {
        try await service.deleteCurrentAccount()
    }

    func updateProfile(
        input: CommunityProfileUpdateInput,
        avatar: CommunityImageUpload?,
        cover: CommunityImageUpload?,
        resetCoverToDefault: Bool
    ) async throws -> CommunityProfile {
        try await service.updateProfile(
            input: input,
            avatar: avatar,
            cover: cover,
            resetCoverToDefault: resetCoverToDefault
        )
    }

    func requestEmailVerification(input: CommunityEmailBindingInput) async throws -> CommunityProfile {
        try await service.requestEmailVerification(input: input)
    }

    func verifyEmailBinding(input: CommunityEmailVerificationInput) async throws -> CommunityProfile {
        try await service.verifyEmailBinding(input: input)
    }

    func submitCampusMembershipRequest(schoolName: String) async throws -> CommunityProfile {
        try await service.submitCampusMembershipRequest(schoolName: schoolName)
    }

    func searchCommunityCampuses(query: String, limit: Int) async throws -> [CommunityCampusOption] {
        try await service.searchCommunityCampuses(query: query, limit: limit)
    }

    func selectCommunityCampus(campusID: String) async throws -> CommunityProfile {
        try await service.selectCommunityCampus(campusID: campusID)
    }

    func fetchCurrentCampusMembershipRequest() async throws -> CommunityCampusMembershipRequest? {
        try await service.fetchCurrentCampusMembershipRequest()
    }

    func submitCommunitySchoolChangeRequest(campusID: String) async throws -> CommunityCampusMembershipRequest {
        try await service.submitCommunitySchoolChangeRequest(campusID: campusID)
    }
}
