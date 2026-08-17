import Foundation
import OSLog
import Supabase

// MARK: - Post Detail and Moderation

extension CommunityService {
    nonisolated func fetchPost(postID: UUID) async throws -> CommunityPost? {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .eq("id", value: postID.uuidString)
            .eq("status", value: "published")
            .limit(1)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let pins = try await fetchActivePostPins(postIDs: records.map(\.id), client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID,
            pins: pins
        )
        let config = try LeafySupabase.shared.requireConfig()
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
            .first
            .map { postWithPublicStorageURLs($0, config: config) }
    }

    nonisolated func fetchComments(postID: UUID) async throws -> [CommunityComment] {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityCommentRecord] = try await client
            .from("comments")
            .select()
            .eq("post_id", value: postID.uuidString)
            .eq("status", value: "published")
            .order("created_at", ascending: true)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let comments = try await hydrateComments(from: records, client: client)
        return try await filterBlockedComments(comments, viewerID: viewerID, client: client)
    }

    nonisolated func fetchCommentThreads(
        postID: UUID,
        cursor: CommunityCommentCursor?,
        limit: Int = 20
    ) async throws -> CommunityCommentPage {
        let client = try LeafySupabase.shared.requireClient()
        try await requireBackendRPC(
            "list_community_comment_threads_v1",
            unavailableMessage: "社区服务需要更新后才能加载两级评论，请稍后重试。"
        )
        let response: CommunityCommentThreadPageRecord = try await client
            .rpc(
                "list_community_comment_threads_v1",
                params: CommunityCommentThreadPageRPCParams(
                    postID: postID,
                    afterCreatedAt: cursor?.createdAt,
                    afterID: cursor?.id,
                    limit: max(1, min(limit, 50))
                )
            )
            .execute()
            .value

        let profileIDs = Set(
            response.comments.map(\.authorID)
                + response.comments.compactMap(\.replyToAuthorID)
        )
        let profiles = try await fetchProfiles(ids: Array(profileIDs), client: client)
        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })
        let viewerID = try? await fetchCurrentProfileID(client: client)
        let blockedIDs = if let viewerID {
            try await fetchBlockedUserIDs(viewerID: viewerID, client: client)
        } else {
            Set<UUID>()
        }

        let hydrated = response.comments.map { record in
            CommunityComment(
                id: record.id,
                postID: record.postID,
                authorID: record.authorID,
                body: record.body,
                isAnonymous: record.isAnonymous,
                status: record.status,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                threadRootID: record.threadRootID,
                parentCommentID: record.parentCommentID,
                replyToCommentID: record.replyToCommentID,
                replyToAuthorID: record.replyToAuthorID,
                replyTargetIsVisible: record.replyTargetIsVisible,
                likeCount: record.likeCount,
                viewerHasLiked: record.viewerHasLiked,
                isDeletedPlaceholder: record.isDeletedPlaceholder,
                author: (record.isDeletedPlaceholder || record.isAnonymous)
                    ? nil
                    : profileMap[record.authorID],
                replyToAuthor: record.replyToAuthorID.flatMap { profileMap[$0] }
            )
        }

        let grouped = Dictionary(grouping: hydrated, by: \.threadRootID)
        let orderedRootIDs = hydrated
            .filter { !$0.isReply }
            .map(\.id)
        let threads = orderedRootIDs.compactMap { rootID -> CommunityCommentThread? in
            guard let values = grouped[rootID],
                  var root = values.first(where: { !$0.isReply }) else {
                return nil
            }
            let replies = values
                .filter(\.isReply)
                .filter { !blockedIDs.contains($0.authorID) }
            if blockedIDs.contains(root.authorID) {
                guard !replies.isEmpty else { return nil }
                root = CommunityComment(
                    id: root.id,
                    postID: root.postID,
                    authorID: root.authorID,
                    body: "",
                    isAnonymous: true,
                    status: root.status,
                    createdAt: root.createdAt,
                    updatedAt: root.updatedAt,
                    threadRootID: root.threadRootID,
                    likeCount: 0,
                    isDeletedPlaceholder: true,
                    author: nil
                )
            }
            return CommunityCommentThread(root: root, replies: replies)
        }

        let nextCursor: CommunityCommentCursor? = if response.hasMore,
                                                    let createdAt = response.nextCursorCreatedAt,
                                                    let id = response.nextCursorID {
            CommunityCommentCursor(createdAt: createdAt, id: id)
        } else {
            nil
        }
        return CommunityCommentPage(threads: threads, nextCursor: nextCursor)
    }

    func fetchMyComments(limit: Int = 80) async throws -> [CommunityComment] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityCommentRecord] = try await client
            .from("comments")
            .select()
            .eq("author_id", value: currentProfile.id.uuidString)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .limit(max(1, min(limit, 100)))
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let comments = try await hydrateComments(from: records, client: client)
        return try await filterBlockedComments(comments, viewerID: viewerID, client: client)
    }

    func createComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID?,
        replyToCommentID: UUID?
    ) async throws -> CommunityComment {
        try await createComment(
            postID: postID,
            body: body,
            parentCommentID: parentCommentID,
            replyToCommentID: replyToCommentID,
            requestID: UUID()
        )
    }

    func createComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID?,
        replyToCommentID: UUID?,
        requestID: UUID
    ) async throws -> CommunityComment {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty, normalizedBody.count <= 2_000 else {
            throw CommunityServiceError.edgeFunctionRejected("评论需为 1–2,000 个字符。")
        }
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        try await requireBackendRPC(
            "create_community_comment_v2_idempotent",
            unavailableMessage: "社区服务需要更新后才能发布回复，请稍后重试。"
        )
        let actorProfile = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()

        let createdRecord: CommunityCommentRecord
        do {
            createdRecord = try await client
                .rpc(
                    "create_community_comment_v2",
                    params: CommunityCreateCommentV2RPCParams(
                        id: UUID(),
                        requestID: requestID,
                        postID: postID,
                        body: normalizedBody,
                        parentCommentID: parentCommentID,
                        replyToCommentID: replyToCommentID,
                        isAnonymous: false
                    )
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "评论发布失败")
        }

        return CommunityComment(
            id: createdRecord.id,
            postID: createdRecord.postID,
            authorID: createdRecord.authorID,
            body: createdRecord.body,
            isAnonymous: createdRecord.isAnonymous,
            status: createdRecord.status,
            createdAt: createdRecord.createdAt,
            updatedAt: createdRecord.updatedAt,
            threadRootID: createdRecord.parentCommentID ?? createdRecord.id,
            parentCommentID: createdRecord.parentCommentID,
            replyToCommentID: createdRecord.replyToCommentID,
            author: actorProfile
        )
    }

    func toggleCommentLike(commentID: UUID) async throws -> CommunityCommentLikeState {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        try await requireBackendRPC(
            "toggle_community_comment_like_v1",
            unavailableMessage: "社区服务需要更新后才能点赞评论，请稍后重试。"
        )
        let records: [CommunityCommentLikeStateRecord]
        do {
            records = try await client
                .rpc(
                    "toggle_community_comment_like_v1",
                    params: CommunityCommentIDRPCParams(
                        commentID: commentID,
                        requestID: UUID()
                    )
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "评论点赞失败")
        }
        return try CommunityCommentLikeResponseValidator.state(from: records)
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        try await requireBackendRPC(
            "toggle_post_like_v1",
            unavailableMessage: "社区服务需要更新后才能点赞，请稍后重试。"
        )

        let record: CommunityPost
        do {
            record = try await client
                .rpc(
                    "toggle_post_like_v1",
                    params: CommunityPostIDRPCParams(postID: postID)
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "点赞失败")
        }

        let config = try LeafySupabase.shared.requireConfig()
        return postWithPublicStorageURLs(record, config: config)
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        try await requireBackendRPC(
            "toggle_post_favorite_v1",
            unavailableMessage: "社区服务需要更新后才能收藏，请稍后重试。"
        )

        let record: CommunityPost
        do {
            record = try await client
                .rpc(
                    "toggle_post_favorite_v1",
                    params: CommunityPostIDRPCParams(postID: postID)
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "收藏失败")
        }

        let config = try LeafySupabase.shared.requireConfig()
        return postWithPublicStorageURLs(record, config: config)
    }

    func deleteComment(commentID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "soft_delete_own_comment",
                params: CommunityCommentSoftDeleteRPCParams(targetCommentID: commentID)
            )
            .execute()
    }

    func deletePost(postID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        try await markPostDeleted(postID: postID)
    }

    func reportPost(postID: UUID, reason: String, detail: String? = nil) async throws {
        try await reportCommunityContent(
            targetType: .post,
            postID: postID,
            commentID: nil,
            reportedUserID: nil,
            reason: reason,
            detail: detail
        )
    }

    func reportComment(commentID: UUID, reason: String, detail: String? = nil) async throws {
        try await reportCommunityContent(
            targetType: .comment,
            postID: nil,
            commentID: commentID,
            reportedUserID: nil,
            reason: reason,
            detail: detail
        )
    }

    func reportUser(userID: UUID, reason: String, detail: String? = nil) async throws {
        try await reportCommunityContent(
            targetType: .user,
            postID: nil,
            commentID: nil,
            reportedUserID: userID,
            reason: reason,
            detail: detail
        )
    }

    func blockUser(userID: UUID, reason: String? = nil) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "block_community_user",
                params: CommunityBlockUserRPCParams(blockedID: userID, reason: reason)
            )
            .execute()
    }

    func unblockUser(userID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc("unblock_community_user", params: CommunityUnblockUserRPCParams(blockedID: userID))
            .execute()
    }
}
