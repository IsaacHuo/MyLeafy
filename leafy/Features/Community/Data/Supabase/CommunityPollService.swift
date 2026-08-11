import Foundation
import OSLog
import Supabase

// MARK: - Polls

extension CommunityService {
    func fetchPolls(limit: Int = 30) async throws -> [CommunityPoll] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let safeLimit = max(1, min(limit, 50))
        let records: [CommunityPollRecord] = try await client
            .from("community_polls")
            .select()
            .eq("campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
            .neq("status", value: "deleted")
            .order("created_at", ascending: false)
            .limit(safeLimit)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        return try await hydratePolls(from: records, client: client, viewerID: viewerID)
    }

    func fetchMyAuthoredPolls(limit: Int = 30) async throws -> [CommunityPoll] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        do {
            let records: [CommunityPoll] = try await client
                .rpc("my_authored_community_polls_v1", params: CommunityPollListRPCParams(limit: limit))
                .execute()
                .value
            return try records.map { try pollWithPublicAvatarURL($0) }
        } catch {
            throw mapCommunityMutationError(error, fallback: "我的投票加载失败")
        }
    }

    func fetchMyVotedPolls(limit: Int = 30) async throws -> [CommunityPoll] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        do {
            let records: [CommunityPoll] = try await client
                .rpc("my_voted_community_polls_v1", params: CommunityPollListRPCParams(limit: limit))
                .execute()
                .value
            return try records.map { try pollWithPublicAvatarURL($0) }
        } catch {
            throw mapCommunityMutationError(error, fallback: "我的投票加载失败")
        }
    }

    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        if input.validationError != nil {
            throw CommunityServiceError.invalidPoll
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        _ = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()

        let record: CommunityPoll
        do {
            record = try await client
                .rpc(
                    "create_community_poll_v1",
                    params: CommunityCreatePollRPCParams(input: input)
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "投票发布失败")
        }

        return try pollWithPublicAvatarURL(record)
    }

    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let record: CommunityPoll
        do {
            record = try await client
                .rpc(
                    "vote_community_poll_v1",
                    params: CommunityVotePollRPCParams(pollID: pollID, optionID: optionID)
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "投票失败")
        }

        return try pollWithPublicAvatarURL(record)
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        do {
            let record: CommunityPoll = try await client
                .rpc(
                    "request_delete_community_poll_v1",
                    params: CommunityRequestPollDeletionRPCParams(pollID: pollID, reason: reason)
                )
                .execute()
                .value
            return try pollWithPublicAvatarURL(record)
        } catch {
            throw mapCommunityMutationError(error, fallback: "删除申请提交失败")
        }
    }

    func deleteOwnPoll(pollID: UUID) async throws {
        _ = try await requestPollDeletion(pollID: pollID, reason: nil)
    }
}
