import Foundation
import OSLog
import Supabase

// MARK: - Identity and Profile

extension CommunityService {
    func deleteCurrentAccount() async throws {
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)

        do {
            let response: CommunityAccountDeletionResponse = try await client.functions.invoke(
                "community-delete-account",
                options: FunctionInvokeOptions(
                    method: .post,
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    region: config.edgeRegion
                )
            )
            guard response.deleted else {
                throw CommunityServiceError.accountDeletionFailed
            }
        } catch let error as CommunityServiceError {
            throw error
        } catch {
            CommunityDiagnostics.log.error(
                "Community account deletion failed: \(error.localizedDescription, privacy: .public)"
            )
            throw CommunityServiceError.accountDeletionFailed
        }
    }

    func bootstrapCommunityUser(
        eduID: String,
        displayName: String?,
        campusID: String = ActiveCampusContext.descriptor.id.rawValue
    ) async throws -> CommunityProfile {
        let trimmedEduID = eduID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEduID.isEmpty else {
            throw CommunityServiceError.schoolSessionMissing
        }
        let trimmedDisplayName = trimmedText(displayName) ?? trimmedEduID
        let normalizedCampusID = campusID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)

        do {
            let response: CommunityBootstrapResponse = try await client.functions.invoke(
                config.bootstrapFunctionName,
                options: FunctionInvokeOptions(
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    body: CommunityBootstrapRequest(
                        eduID: trimmedEduID,
                        displayName: trimmedDisplayName,
                        campusID: normalizedCampusID.isEmpty ? CampusID.bjfu.rawValue : normalizedCampusID
                    )
                )
            )

            return response.profile
        } catch let error as FunctionsError {
            throw mapFunctionsError(error)
        }
    }

    func fetchCurrentProfile() async throws -> CommunityProfile? {
        let client = try LeafySupabase.shared.requireClient()
        guard let profileID = try await fetchCurrentProfileID(client: client) else {
            return nil
        }

        return try await fetchProfile(id: profileID, client: client)
    }

    func fetchCurrentProfile(userID: UUID) async throws -> CommunityProfile? {
        try await fetchProfile(id: userID)
    }

    func fetchPublicProfile(userID: UUID) async throws -> CommunityProfile? {
        try await fetchProfile(id: userID)
    }

    func searchCommunityCampuses(query: String, limit: Int = 20) async throws -> [CommunityCampusOption] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return try await client
            .rpc(
                "community_campuses_v1",
                params: CommunityCampusSearchParams(search: query, limit: limit)
            )
            .execute()
            .value
    }

    func fetchCurrentCampusMembershipRequest() async throws -> CommunityCampusMembershipRequest? {
        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .current)
        )
        return response.request
    }

    func selectCommunityCampus(campusID: String) async throws -> CommunityProfile {
        let trimmedCampusID = campusID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedCampusID.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请选择学校。")
        }

        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .selectExisting, campusID: trimmedCampusID)
        )
        if let profile = response.profile {
            return profile
        }
        if let profile = try await fetchCurrentProfile() {
            return profile
        }
        throw CommunityServiceError.missingAuthenticatedUser
    }

    func submitCommunitySchoolChangeRequest(campusID: String) async throws -> CommunityCampusMembershipRequest {
        let trimmedCampusID = campusID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedCampusID.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请选择新的学校。")
        }

        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .requestChange, campusID: trimmedCampusID)
        )
        guard let request = response.request else {
            throw CommunityServiceError.edgeFunctionRejected("学校更换申请未创建，请稍后重试。")
        }
        return request
    }

    func submitCampusMembershipRequest(schoolName: String) async throws -> CommunityProfile {
        let trimmedSchoolName = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSchoolName.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请填写学校名称。")
        }

        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .submitNewSchool, schoolName: trimmedSchoolName)
        )
        if let profile = response.profile {
            return profile
        }
        if let profile = try await fetchCurrentProfile() {
            return profile
        }
        throw CommunityServiceError.missingAuthenticatedUser
    }

    func invokeCampusRequest(_ body: CommunityCampusRequestSubmitRequest) async throws -> CommunityCampusRequestResponse {
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)

        do {
            return try await client.functions.invoke(
                "campus-request",
                options: FunctionInvokeOptions(
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    region: config.edgeRegion,
                    body: body
                )
            )
        } catch let error as FunctionsError {
            throw mapFunctionsError(error)
        }
    }

    func fetchProfileStats(profileIDs: [UUID]) async throws -> [CommunityProfileStats] {
        let uniqueProfileIDs = Array(Set(profileIDs))
        guard !uniqueProfileIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        let response: CommunityProfileStatsResponse = try await client
            .rpc(
                "community_profile_stats_v1",
                params: CommunityProfileStatsRPCParams(profileIDs: uniqueProfileIDs)
            )
            .execute()
            .value

        return response.profiles
    }

    func updateProfile(
        input: CommunityProfileUpdateInput,
        avatar: CommunityImageUpload?,
        cover: CommunityImageUpload? = nil,
        resetCoverToDefault: Bool = false
    ) async throws -> CommunityProfile {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let existingProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let trimmedNickname = CommunityNickname.normalized(input.nickname)
        guard !trimmedNickname.isEmpty else {
            throw CommunityServiceError.profileCompletionRequired
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let avatarPath = try await uploadProfileAvatarIfNeeded(avatar, userID: existingProfile.id) ?? existingProfile.avatarPath
        let coverPath: String?
        if resetCoverToDefault {
            coverPath = nil
        } else {
            coverPath = try await uploadProfileCoverIfNeeded(cover, userID: existingProfile.id) ?? existingProfile.coverPath
        }
        let update = CommunityProfileUpdate(
            nickname: trimmedNickname,
            avatarPath: avatarPath,
            coverPath: coverPath,
            bio: CommunityProfileBio.normalized(input.bio),
            major: trimmedText(input.major),
            grade: trimmedText(input.grade),
            profileEditedAt: now,
            isProfileComplete: true,
            showsEduVerificationBadge: input.showsEduVerificationBadge,
            updatedAt: now
        )

        _ = try await client
            .from("profiles")
            .update(update)
            .eq("id", value: existingProfile.id.uuidString)
            .execute()

        guard let profile = try await fetchProfile(id: existingProfile.id, client: client) else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return profile
    }

    func requestEmailVerification(input: CommunityEmailBindingInput) async throws -> CommunityProfile {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let email = CommunityEmailBinding.normalizedEmail(input.email)
        guard CommunityEmailBinding.isValidEmail(email) else {
            throw CommunityServiceError.invalidEmail
        }
        if CommunityEmailBinding.isAlreadyBound(
            boundEmail: currentProfile.boundEmail,
            requestedEmail: email
        ) {
            return currentProfile
        }

        do {
            if CommunityEmailBinding.shouldResendVerification(
                pendingEmail: currentProfile.pendingBoundEmail,
                requestedEmail: email
            ) {
                try await client.auth.resend(
                    email: email,
                    type: .emailChange,
                    emailRedirectTo: LeafySupabase.authCallbackURL
                )
            } else {
                _ = try await client.auth.update(
                    user: UserAttributes(email: email),
                    redirectTo: LeafySupabase.authCallbackURL
                )
            }
        } catch {
            throw mapEmailAuthError(error)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let update = CommunityPendingEmailUpdate(
            pendingBoundEmail: email,
            emailVerificationSentAt: now,
            updatedAt: now
        )

        _ = try await client
            .from("profiles")
            .update(update)
            .eq("id", value: currentProfile.id.uuidString)
            .execute()

        guard let profile = try await fetchProfile(id: currentProfile.id, client: client) else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return profile
    }

    func verifyEmailBinding(input: CommunityEmailVerificationInput) async throws -> CommunityProfile {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let email = CommunityEmailBinding.normalizedEmail(input.email)
        guard CommunityEmailBinding.isValidEmail(email) else {
            throw CommunityServiceError.invalidEmail
        }
        guard CommunityEmailBinding.isCompleteVerificationCode(input.code) else {
            throw CommunityServiceError.edgeFunctionRejected("请输入邮件中的 8 位验证码。")
        }

        do {
            _ = try await client.auth.verifyOTP(
                email: email,
                token: input.code,
                type: .emailChange,
                redirectTo: LeafySupabase.authCallbackURL
            )
        } catch {
            throw mapEmailAuthError(error)
        }

        let update = CommunityVerifiedEmailUpdate(
            boundEmail: email,
            pendingBoundEmail: nil,
            emailVerificationSentAt: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        do {
            _ = try await client
                .from("profiles")
                .update(update)
                .eq("id", value: currentProfile.id.uuidString)
                .execute()
        } catch {
            throw mapEmailAuthError(error)
        }

        guard let profile = try await fetchProfile(id: currentProfile.id, client: client) else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return profile
    }

    func hasAcceptedCurrentTerms() async throws -> Bool {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityTermsAcceptanceRecord] = try await client
            .from("community_terms_acceptances")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .eq("terms_version", value: CommunityTerms.currentVersion)
            .limit(1)
            .execute()
            .value

        return !records.isEmpty
    }

    func acceptCurrentTerms() async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "accept_community_terms",
                params: CommunityTermsAcceptanceRPCParams(termsVersion: CommunityTerms.currentVersion)
            )
            .execute()
    }

    func revokeCurrentTerms() async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "revoke_community_terms",
                params: CommunityTermsAcceptanceRPCParams(termsVersion: CommunityTerms.currentVersion)
            )
            .execute()
    }
}
