import Foundation
import OSLog
import Supabase

// MARK: - Feed and Posts

extension CommunityService {
    nonisolated func fetchPosts(query: CommunityFeedQuery = .default) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        try await requireBackendEdgeFunction(
            config.feedFunctionName,
            unavailableMessage: "社区内容服务当前不可用，请稍后重试。"
        )

        if let apiBaseURL = config.communityAPIBaseURL {
            let response = try await fetchPostsFromCommunityAPI(
                baseURL: apiBaseURL,
                functionName: config.feedFunctionName,
                query: query,
                accessToken: session.accessToken
            )
            return response.posts.map { postWithPublicStorageURLs($0, config: config) }
        }

        client.functions.setAuth(token: session.accessToken)

        do {
            let response: CommunityFeedResponse = try await client.functions.invoke(
                config.feedFunctionName,
                options: FunctionInvokeOptions(
                    method: .get,
                    query: communityFeedQueryItems(query),
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    region: config.edgeRegion
                )
            )

            return response.posts.map { postWithPublicStorageURLs($0, config: config) }
        } catch let error as FunctionsError {
            throw mapFunctionsError(error)
        }
    }

    func fetchPosts(authoredBy userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .eq("author_id", value: userID.uuidString)
            .in("status", values: ["published", "pending_review", "hidden"])
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func fetchPublicPosts(authoredBy userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .eq("campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
            .eq("author_id", value: userID.uuidString)
            .eq("status", value: "published")
            .eq("is_anonymous", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func fetchLikedPosts(by userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let likes: [CommunityPostLikeRecord] = try await client
            .from("post_likes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let postIDs = likes.map(\.postID)
        guard !postIDs.isEmpty else { return [] }

        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .in("id", values: postIDs.map(\.uuidString))
            .eq("status", value: "published")
            .execute()
            .value

        let orderMap = LeafyFirstValueMap.build(postIDs.enumerated().map { ($0.element, $0.offset) })
        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
            .sorted { (orderMap[$0.id] ?? Int.max) < (orderMap[$1.id] ?? Int.max) }
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func fetchFavoritedPosts(by userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let favorites: [CommunityPostFavoriteRecord] = try await client
            .from("post_favorites")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let postIDs = favorites.map(\.postID)
        guard !postIDs.isEmpty else { return [] }

        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .in("id", values: postIDs.map(\.uuidString))
            .eq("status", value: "published")
            .execute()
            .value

        let orderMap = LeafyFirstValueMap.build(postIDs.enumerated().map { ($0.element, $0.offset) })
        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
            .sorted { (orderMap[$0.id] ?? Int.max) < (orderMap[$1.id] ?? Int.max) }
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func createPendingPost(
        id: UUID,
        input: CreatePostInput,
        imageCount: Int,
        attachmentCount: Int
    ) async throws -> UUID {
        try await createPendingPost(
            id: id,
            requestID: id,
            input: input,
            imageCount: imageCount,
            attachmentCount: attachmentCount
        )
    }

    func createPendingPost(
        id: UUID,
        requestID: UUID,
        input: CreatePostInput,
        imageCount: Int,
        attachmentCount: Int
    ) async throws -> UUID {
        guard imageCount >= 0, imageCount <= CommunityImageUpload.postImageLimit,
              attachmentCount >= 0, attachmentCount <= CommunityPostAttachment.postAttachmentLimit else {
            throw CommunityServiceError.edgeFunctionRejected("帖子媒体数量无效。")
        }
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80 else {
            throw CommunityServiceError.edgeFunctionRejected("标题需为 1–80 个字符。")
        }
        guard !body.isEmpty, body.count <= 10_000 else {
            throw CommunityServiceError.edgeFunctionRejected("正文需为 1–10,000 个字符。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let actorProfile = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()
        try await enforcePostRateLimit(authorID: actorProfile.id, client: client)

        let _: CommunityPostRecord = try await client
            .rpc(
                "create_community_post_v4",
                params: CommunityCreatePostV4RPCParams(
                    id: id,
                    requestID: requestID,
                    title: title,
                    body: body,
                    category: CommunityPostCategory.normalized(input.category),
                    isAnonymous: input.isAnonymous,
                    imageCount: imageCount,
                    attachmentCount: attachmentCount
                )
            )
            .execute()
            .value
        return id
    }

    func pendingPostContext(postID: UUID) async throws -> CommunityPendingPostContext? {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityPendingPostContextRecord] = try await client
            .from("posts")
            .select("id,author_id,status")
            .eq("id", value: postID.uuidString)
            .limit(1)
            .execute()
            .value
        return records.first.map {
            CommunityPendingPostContext(postID: $0.id, authorID: $0.authorID, status: $0.status)
        }
    }

    func validateAndAttachPostImage(
        postID: UUID,
        imageID: UUID,
        fullPath: String,
        thumbnailPath: String,
        sortOrder: Int
    ) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)
        let validation: CommunityUploadValidationResponse = try await client.functions.invoke(
            "community-validate-upload",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: CommunityUploadValidationRequest(
                    postID: postID.uuidString.lowercased(),
                    fullPath: fullPath,
                    thumbnailPath: thumbnailPath
                )
            )
        )
        _ = try await client
            .rpc(
                "attach_community_post_image_v1",
                params: CommunityAttachPostImageRPCParams(
                    receiptID: validation.receiptID,
                    imageID: imageID,
                    sortOrder: sortOrder
                )
            )
            .execute()
    }

    func validateAndAttachPostAttachment(
        postID: UUID,
        attachmentID: UUID,
        objectPath: String,
        displayName: String,
        sortOrder: Int
    ) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)
        let validation: CommunityAttachmentValidationResponse = try await client.functions.invoke(
            "community-validate-attachment",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: CommunityAttachmentValidationRequest(
                    postID: postID.uuidString.lowercased(),
                    objectPath: objectPath,
                    displayName: displayName
                )
            )
        )
        _ = try await client
            .rpc(
                "attach_community_post_attachment_v1",
                params: CommunityAttachPostAttachmentRPCParams(
                    receiptID: validation.receiptID,
                    attachmentID: attachmentID,
                    sortOrder: sortOrder
                )
            )
            .execute()
    }

    func abortPendingPost(postID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        _ = try await client
            .rpc(
                "abort_community_post_upload_v1",
                params: CommunityPostIDRPCParams(postID: postID)
            )
            .execute()
    }

    func attachmentDownloadURL(attachmentID: UUID) async throws -> CommunityAttachmentDownload {
        try await requireBackendEdgeFunction(
            "community-attachment-download",
            unavailableMessage: "社区服务需要更新后才能下载附件，请稍后重试。"
        )
        let client = try LeafySupabase.shared.requireClient()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)
        let response: CommunityAttachmentDownloadResponse = try await client.functions.invoke(
            "community-attachment-download",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: CommunityAttachmentDownloadRequest(attachmentID: attachmentID)
            )
        )
        return CommunityAttachmentDownload(
            url: response.url,
            displayName: response.displayName,
            contentType: response.contentType,
            byteSize: response.byteSize
        )
    }
}
