import Foundation
import OSLog
import Supabase

enum CommunityServiceError: LocalizedError {
    case missingAuthenticatedUser
    case schoolSessionMissing
    case imageLimitExceeded
    case postRateLimitExceeded
    case profileCompletionRequired
    case invalidEmail
    case cannotLikeOwnPost
    case userMuted
    case termsAcceptanceRequired
    case contentRejected
    case invalidPoll
    case pollClosed
    case accountDeletionFailed
    case edgeFunctionRejected(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthenticatedUser:
            return "社区身份尚未建立，请稍后重试。"
        case .schoolSessionMissing:
            return "教务学号缺失，请连接校园网后重新登录教务系统。"
        case .imageLimitExceeded:
            return "单条帖子最多上传 \(CommunityImageUpload.postImageLimit) 张图片。"
        case .postRateLimitExceeded:
            return "发帖太频繁了，每小时最多发布 2 篇帖子。"
        case .profileCompletionRequired:
            return "请先完善社区资料后再继续。"
        case .invalidEmail:
            return "请输入有效的邮箱地址。"
        case .cannotLikeOwnPost:
            return "不能点赞自己的帖子。"
        case .userMuted:
            return "账号已被社区禁言，暂时不能发帖或评论。"
        case .termsAcceptanceRequired:
            return "请先阅读并同意社区条款。"
        case .contentRejected:
            return "内容包含可能违规的信息，请修改后再发布。"
        case .invalidPoll:
            return "投票内容不完整，请检查问题和选项。"
        case .pollClosed:
            return "投票已截止。"
        case .accountDeletionFailed:
            return "账户删除失败，线上数据和本机数据均未清除，请稍后重试。"
        case .edgeFunctionRejected(let message):
            return message
        }
    }
}

nonisolated enum LeafyFirstValueMap {
    static func build<Key: Hashable, Value>(_ pairs: [(Key, Value)]) -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in pairs where result[key] == nil {
            result[key] = value
        }
        return result
    }
}

actor CommunityService {
    static let shared = CommunityService()

    nonisolated static let storageBucket = "community-images"
    nonisolated static let publicImageCacheControl = "31536000"
    var activeEnsureSessionTask: Task<Void, Error>?

    init() {}

    func cancelInFlightWork() {
        activeEnsureSessionTask?.cancel()
        activeEnsureSessionTask = nil
    }

    func ensureAnonymousSession() async throws {
        if let activeEnsureSessionTask {
            do {
                try await activeEnsureSessionTask.value
            } catch {
                activeEnsureSessionTask.cancel()
                self.activeEnsureSessionTask = nil
                throw error
            }
            return
        }

        let task = Task.detached {
            try await Self.performEnsureAnonymousSession()
        }

        activeEnsureSessionTask = task
        defer { self.activeEnsureSessionTask = nil }
        do {
            try await task.value
        } catch {
            task.cancel()
            throw error
        }
    }

    static func performEnsureAnonymousSession() async throws {
        try Task.checkCancellation()
        let client = try LeafySupabase.shared.requireClient()

        if client.auth.currentSession != nil {
            do {
                try Task.checkCancellation()
                _ = try await client.auth.session
                return
            } catch {
                try await client.auth.signOut()
            }
        }

        try Task.checkCancellation()
        _ = try await client.auth.signInAnonymously()
    }
}

// MARK: - Shared Supabase Implementation

extension CommunityService {
    func createNotification(
        recipientID: UUID,
        actorID: UUID,
        postID: UUID,
        commentID: UUID?,
        type: CommunityNotificationType,
        title: String,
        body: String?
    ) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let params = CommunityNotificationRPCParams(
            recipientID: recipientID,
            actorID: actorID,
            postID: postID,
            commentID: commentID,
            type: type,
            title: title,
            body: body
        )

        _ = try await client
            .rpc("create_community_notification", params: params)
            .execute()
    }

    func reportCommunityContent(
        targetType: CommunityReportTargetType,
        postID: UUID?,
        commentID: UUID?,
        reportedUserID: UUID?,
        reason: String,
        detail: String?
    ) async throws {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请选择举报原因。")
        }
        guard (normalizedDetail?.count ?? 0) <= 1_000 else {
            throw CommunityServiceError.edgeFunctionRejected("举报说明最多 1,000 个字符。")
        }
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "report_community_content",
                params: CommunityReportContentRPCParams(
                    targetType: targetType,
                    postID: postID,
                    commentID: commentID,
                    reportedUserID: reportedUserID,
                    reason: normalizedReason,
                    detail: normalizedDetail
                )
            )
            .execute()
    }

    func enforcePostRateLimit(authorID: UUID, client: SupabaseClient) async throws {
        let threshold = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60 * 60))
        let recentPosts: [CommunityPostRateLimitRecord] = try await client
            .from("posts")
            .select("id")
            .eq("author_id", value: authorID.uuidString)
            .gte("created_at", value: threshold)
            .limit(2)
            .execute()
            .value

        if recentPosts.count >= 2 {
            throw CommunityServiceError.postRateLimitExceeded
        }
    }

    func markPostDeleted(postID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        _ = try await client
            .rpc(
                "soft_delete_own_post",
                params: CommunityPostSoftDeleteRPCParams(targetPostID: postID)
            )
            .execute()
    }

    func uploadProfileAvatarIfNeeded(_ avatar: CommunityImageUpload?, userID: UUID) async throws -> String? {
        guard let avatar else { return nil }

        let client = try LeafySupabase.shared.requireClient()
        let userPathComponent = userID.uuidString.lowercased()
        let avatarPathComponent = avatar.id.uuidString.lowercased()
        let objectPath = "avatars/\(userPathComponent)/\(avatarPathComponent).\(avatar.fileExtension)"

        _ = try await client.storage
            .from(Self.storageBucket)
            .upload(
                objectPath,
                data: avatar.data,
                options: FileOptions(
                    cacheControl: Self.publicImageCacheControl,
                    contentType: avatar.mimeType,
                    upsert: true
                )
            )

        do {
            try await validateProfileImageUpload(kind: "avatar", path: objectPath, client: client)
        } catch {
            _ = try? await client.storage.from(Self.storageBucket).remove(paths: [objectPath])
            throw error
        }

        return objectPath
    }

    func uploadProfileCoverIfNeeded(_ cover: CommunityImageUpload?, userID: UUID) async throws -> String? {
        guard let cover else { return nil }

        let client = try LeafySupabase.shared.requireClient()
        let userPathComponent = userID.uuidString.lowercased()
        let coverPathComponent = cover.id.uuidString.lowercased()
        let objectPath = "profile-covers/\(userPathComponent)/\(coverPathComponent).\(cover.fileExtension)"

        _ = try await client.storage
            .from(Self.storageBucket)
            .upload(
                objectPath,
                data: cover.data,
                options: FileOptions(
                    cacheControl: Self.publicImageCacheControl,
                    contentType: cover.mimeType,
                    upsert: true
                )
            )

        do {
            try await validateProfileImageUpload(kind: "cover", path: objectPath, client: client)
        } catch {
            _ = try? await client.storage.from(Self.storageBucket).remove(paths: [objectPath])
            throw error
        }

        return objectPath
    }

    func validateProfileImageUpload(
        kind: String,
        path: String,
        client: SupabaseClient
    ) async throws {
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)
        let response: CommunityProfileUploadValidationResponse = try await client.functions.invoke(
            "community-validate-upload",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: CommunityProfileUploadValidationRequest(kind: kind, objectPath: path)
            )
        )
        guard response.validated else {
            throw CommunityServiceError.edgeFunctionRejected("图片验证失败，请重新选择图片。")
        }
    }

    nonisolated func hydratePosts(
        from records: [CommunityPostRecord],
        client: SupabaseClient,
        viewerID: UUID?,
        pins: [CommunityPostPin] = []
    ) async throws -> [CommunityPost] {
        guard !records.isEmpty else { return [] }

        let authorIDs = Array(Set(records.map(\.authorID)))
        let postIDs = records.map(\.id)
        let profiles = try await fetchProfiles(ids: authorIDs, client: client)
        let images = try await fetchPostImages(postIDs: postIDs, client: client)
        let attachments = try await fetchPostAttachments(postIDs: postIDs, client: client)
        let likes = try await fetchPostLikes(postIDs: postIDs, client: client)
        let favorites = try await fetchPostFavorites(postIDs: postIDs, viewerID: viewerID, client: client)

        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })
        let imageMap = Dictionary(grouping: images, by: \.postID)
        let attachmentMap = Dictionary(grouping: attachments, by: \.postID)
        let likeMap = Dictionary(grouping: likes, by: \.postID)
        let favoritedPostIDs = Set(favorites.map(\.postID))
        let pinMap = preferredPinMap(from: pins)

        return records.map { record in
            let postLikes = likeMap[record.id] ?? []
            return CommunityPost(
                id: record.id,
                authorID: record.authorID,
                title: record.title,
                body: record.body,
                category: record.category,
                isAnonymous: record.isAnonymous,
                commentCount: record.commentCount,
                likeCount: postLikes.count,
                status: record.status,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                viewerHasLiked: postLikes.contains(where: { $0.userID == viewerID }),
                viewerHasFavorited: favoritedPostIDs.contains(record.id),
                pin: pinMap[record.id],
                author: profileMap[record.authorID],
                images: imageMap[record.id] ?? [],
                attachments: attachmentMap[record.id] ?? []
            )
        }
    }

    nonisolated func hydrateComments(
        from records: [CommunityCommentRecord],
        client: SupabaseClient
    ) async throws -> [CommunityComment] {
        guard !records.isEmpty else { return [] }

        let profiles = try await fetchProfiles(ids: Array(Set(records.map(\.authorID))), client: client)
        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })

        return records.map { record in
            CommunityComment(
                id: record.id,
                postID: record.postID,
                authorID: record.authorID,
                body: record.body,
                isAnonymous: record.isAnonymous,
                status: record.status,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                author: profileMap[record.authorID]
            )
        }
    }

    func hydrateNotifications(from records: [CommunityNotificationRecord]) async throws -> [CommunityNotification] {
        guard !records.isEmpty else { return [] }

        let actorIDs = records.compactMap(\.actorID)
        let profiles = try await fetchProfiles(ids: Array(Set(actorIDs)))
        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })

        return records.map { record in
            CommunityNotification(
                id: record.id,
                recipientID: record.recipientID,
                actorID: record.actorID,
                postID: record.postID,
                commentID: record.commentID,
                type: record.type,
                title: record.title,
                body: record.body,
                isRead: record.isRead,
                createdAt: record.createdAt,
                actor: record.actorID.flatMap { profileMap[$0] }
            )
        }
    }

    nonisolated func fetchProfiles(ids: [UUID], client providedClient: SupabaseClient? = nil) async throws -> [CommunityProfile] {
        guard !ids.isEmpty else { return [] }

        let client: SupabaseClient
        if let providedClient {
            client = providedClient
        } else {
            client = try LeafySupabase.shared.requireClient()
        }
        let profiles: [CommunityProfile] = try await client
            .from("profiles")
            .select()
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value

        return try await hydrateProfiles(profiles, client: client)
    }

    nonisolated func fetchProfile(id: UUID, client providedClient: SupabaseClient? = nil) async throws -> CommunityProfile? {
        try await fetchProfiles(ids: [id], client: providedClient).first
    }

    nonisolated func fetchActivePostPins(
        query: CommunityFeedQuery,
        client: SupabaseClient
    ) async throws -> [CommunityPostPin] {
        do {
            let records: [CommunityPostPin] = try await client
                .from("community_post_pins")
                .select()
                .eq("status", value: "active")
                .order("priority", ascending: false)
                .order("starts_at", ascending: false)
                .limit(50)
                .execute()
                .value

            return records.filter { pin in
                guard pin.isCurrentlyActive else { return false }
                switch pin.scope {
                case .global:
                    return true
                case .category:
                    guard let selectedCategory = query.category else { return false }
                    return normalizedCommunityText(pin.category) == normalizedCommunityText(selectedCategory)
                }
            }
        } catch {
            if isMissingPostPinsTable(error) {
                return []
            }
            throw error
        }
    }

    nonisolated func fetchActivePostPins(
        postIDs: [UUID],
        client: SupabaseClient
    ) async throws -> [CommunityPostPin] {
        guard !postIDs.isEmpty else { return [] }

        do {
            let records: [CommunityPostPin] = try await client
                .from("community_post_pins")
                .select()
                .eq("status", value: "active")
                .in("post_id", values: postIDs.map(\.uuidString))
                .order("priority", ascending: false)
                .order("starts_at", ascending: false)
                .execute()
                .value

            return records.filter(\.isCurrentlyActive)
        } catch {
            if isMissingPostPinsTable(error) {
                return []
            }
            throw error
        }
    }

    nonisolated func fetchCurrentProfileID(client: SupabaseClient) async throws -> UUID? {
        guard let currentUserID = client.auth.currentUser?.id else {
            return nil
        }

        do {
            let links: [CommunityProfileAuthLinkRecord] = try await client
                .from("profile_auth_links")
                .select()
                .eq("auth_user_id", value: currentUserID.uuidString)
                .limit(1)
                .execute()
                .value

            if let profileID = links.first?.profileID {
                return profileID
            }
        } catch where isMissingSchemaColumn(error, column: "campus_id") {
            let links: [CommunityProfileAuthLinkRecord] = try await client
                .from("profile_auth_links")
                .select()
                .eq("auth_user_id", value: currentUserID.uuidString)
                .limit(1)
                .execute()
                .value

            if let profileID = links.first?.profileID {
                return profileID
            }
        } catch {
            return currentUserID
        }

        return currentUserID
    }

    nonisolated func uniquePostRecords(_ records: [CommunityPostRecord]) -> [CommunityPostRecord] {
        var seen: Set<UUID> = []
        var result: [CommunityPostRecord] = []
        for record in records where !seen.contains(record.id) {
            seen.insert(record.id)
            result.append(record)
        }
        return result
    }

    nonisolated func preferredPinMap(from pins: [CommunityPostPin]) -> [UUID: CommunityPostPin] {
        Dictionary(grouping: pins, by: \.postID).compactMapValues { postPins in
            postPins.sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                let leftStart = CommunityTimestampFormatter.parse(lhs.startsAt) ?? .distantPast
                let rightStart = CommunityTimestampFormatter.parse(rhs.startsAt) ?? .distantPast
                return leftStart > rightStart
            }.first
        }
    }

    nonisolated func normalizedCommunityText(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated func communityFeedQueryItems(_ query: CommunityFeedQuery) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "limit", value: String(query.limit)),
            URLQueryItem(name: "campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
        ]
        if case .hot(let days) = query.mode.normalized {
            items.append(URLQueryItem(name: "mode", value: "hot"))
            items.append(URLQueryItem(name: "days", value: String(days)))
        }
        if let category = query.category {
            items.append(URLQueryItem(name: "category", value: category))
        }
        if let search = query.search {
            items.append(URLQueryItem(name: "search", value: search))
        }
        return items
    }

    nonisolated func fetchPostsFromCommunityAPI(
        baseURL: URL,
        functionName: String,
        query: CommunityFeedQuery,
        accessToken: String
    ) async throws -> CommunityFeedResponse {
        guard let url = communityAPIURL(baseURL: baseURL, functionName: functionName, query: query) else {
            throw CommunityServiceError.edgeFunctionRejected("社区接口地址无效。")
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommunityServiceError.edgeFunctionRejected("社区接口响应无效。")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let payload = try? JSONDecoder().decode(EdgeFunctionErrorPayload.self, from: data),
               let message = payload.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                throw CommunityServiceError.edgeFunctionRejected(message)
            }

            throw CommunityServiceError.edgeFunctionRejected("社区接口返回了 \(httpResponse.statusCode) 错误。")
        }

        do {
            return try JSONDecoder().decode(CommunityFeedResponse.self, from: data)
        } catch {
            throw CommunityServiceError.edgeFunctionRejected("社区接口数据解析失败：\(error.localizedDescription)")
        }
    }

    nonisolated func communityAPIURL(
        baseURL: URL,
        functionName: String,
        query: CommunityFeedQuery
    ) -> URL? {
        let trimmedFunctionName = functionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint: URL
        if trimmedFunctionName.isEmpty || baseURL.lastPathComponent == trimmedFunctionName {
            endpoint = baseURL
        } else {
            endpoint = baseURL.appendingPathComponent(trimmedFunctionName)
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let existingItems = components.queryItems ?? []
        components.queryItems = existingItems + communityFeedQueryItems(query)
        return components.url
    }

    nonisolated func publicStorageURL(path: String?, config _: SupabaseConfig) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              let client = LeafySupabase.shared.client else {
            return nil
        }

        return try? client.storage
            .from(Self.storageBucket)
            .getPublicURL(path: path)
    }

    nonisolated func postWithPublicStorageURLs(_ post: CommunityPost, config: SupabaseConfig) -> CommunityPost {
        CommunityPost(
            id: post.id,
            authorID: post.authorID,
            title: post.title,
            body: post.body,
            category: post.category,
            isAnonymous: post.isAnonymous,
            commentCount: post.commentCount,
            likeCount: post.likeCount,
            status: post.status,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
            viewerHasLiked: post.viewerHasLiked,
            viewerHasFavorited: post.viewerHasFavorited,
            pin: post.pin,
            author: post.author.map { profileWithPublicAvatarURL($0, config: config) },
            images: post.images.map { imageWithPublicStorageURLs($0, config: config) },
            attachments: post.attachments
        )
    }

    nonisolated func profileWithPublicAvatarURL(_ profile: CommunityProfile, config: SupabaseConfig) -> CommunityProfile {
        CommunityProfile(
            id: profile.id,
            eduID: profile.eduID,
            campusID: profile.campusID,
            communityCampusID: profile.communityCampusID,
            communityAccessStatusRaw: profile.communityAccessStatusRaw,
            communitySchoolName: profile.communitySchoolName,
            communityRejectionReason: profile.communityRejectionReason,
            nickname: profile.nickname,
            displayName: profile.displayName,
            avatarPath: profile.avatarPath,
            coverPath: profile.coverPath,
            bio: profile.bio,
            major: profile.major,
            grade: profile.grade,
            boundEmail: profile.boundEmail,
            pendingBoundEmail: profile.pendingBoundEmail,
            emailVerificationSentAt: profile.emailVerificationSentAt,
            profileEditedAt: profile.profileEditedAt,
            isProfileComplete: profile.isProfileComplete,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            signedAvatarURL: profile.signedAvatarURL,
            avatarURL: profile.avatarURL ?? publicStorageURL(path: profile.avatarPath, config: config),
            signedCoverURL: profile.signedCoverURL,
            coverURL: profile.coverURL ?? publicStorageURL(path: profile.coverPath, config: config),
            showsEduVerificationBadge: profile.showsEduVerificationBadge
        )
    }

    nonisolated func imageWithPublicStorageURLs(_ image: CommunityPostImage, config: SupabaseConfig) -> CommunityPostImage {
        CommunityPostImage(
            id: image.id,
            postID: image.postID,
            path: image.path,
            thumbnailPath: image.thumbnailPath,
            sortOrder: image.sortOrder,
            width: image.width,
            height: image.height,
            thumbnailWidth: image.thumbnailWidth,
            thumbnailHeight: image.thumbnailHeight,
            fullWidth: image.fullWidth,
            fullHeight: image.fullHeight,
            createdAt: image.createdAt,
            signedURL: image.signedURL,
            thumbnailURL: image.thumbnailURL ?? publicStorageURL(path: image.thumbnailPath ?? image.path, config: config),
            fullURL: image.fullURL ?? publicStorageURL(path: image.path, config: config)
        )
    }

    nonisolated func pollWithPublicAvatarURL(_ poll: CommunityPoll) throws -> CommunityPoll {
        let config = try LeafySupabase.shared.requireConfig()
        return CommunityPoll(
            id: poll.id,
            authorID: poll.authorID,
            question: poll.question,
            detail: poll.detail,
            status: poll.status,
            totalVoteCount: poll.totalVoteCount,
            viewerOptionID: poll.viewerOptionID,
            closesAt: poll.closesAt,
            deletionStatus: poll.deletionStatus,
            deletionRequestedAt: poll.deletionRequestedAt,
            deletionReason: poll.deletionReason,
            deletionReviewedAt: poll.deletionReviewedAt,
            deletionReviewReason: poll.deletionReviewReason,
            createdAt: poll.createdAt,
            updatedAt: poll.updatedAt,
            author: poll.author.map { profileWithPublicAvatarURL($0, config: config) },
            options: poll.options
        )
    }

    nonisolated func hydratePolls(
        from records: [CommunityPollRecord],
        client: SupabaseClient,
        viewerID: UUID?
    ) async throws -> [CommunityPoll] {
        guard !records.isEmpty else { return [] }

        let pollIDs = records.map(\.id)
        let authorIDs = Array(Set(records.map(\.authorID)))
        let profiles = try await fetchProfiles(ids: authorIDs, client: client)
        let options: [CommunityPollOption] = try await client
            .from("community_poll_options")
            .select()
            .in("poll_id", values: pollIDs.map(\.uuidString))
            .order("sort_order", ascending: true)
            .execute()
            .value

        let votes = try await fetchPollVotes(pollIDs: pollIDs, viewerID: viewerID, client: client)
        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })
        let optionMap = Dictionary(grouping: options, by: \.pollID)
        let voteMap = LeafyFirstValueMap.build(votes.map { ($0.pollID, $0.optionID) })

        return records.map { record in
            CommunityPoll(
                id: record.id,
                authorID: record.authorID,
                question: record.question,
                detail: record.detail,
                status: record.status,
                totalVoteCount: record.totalVoteCount,
                viewerOptionID: voteMap[record.id],
                closesAt: record.closesAt,
                deletionStatus: record.deletionStatus,
                deletionRequestedAt: record.deletionRequestedAt,
                deletionReason: record.deletionReason,
                deletionReviewedAt: record.deletionReviewedAt,
                deletionReviewReason: record.deletionReviewReason,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                author: profileMap[record.authorID],
                options: optionMap[record.id] ?? []
            )
        }
    }

    nonisolated func fetchPollVotes(
        pollIDs: [UUID],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityPollVoteRecord] {
        guard let viewerID, !pollIDs.isEmpty else { return [] }

        return try await client
            .from("community_poll_votes")
            .select()
            .eq("user_id", value: viewerID.uuidString)
            .in("poll_id", values: pollIDs.map(\.uuidString))
            .execute()
            .value
    }

    nonisolated func fetchPostImages(postIDs: [UUID], client: SupabaseClient) async throws -> [CommunityPostImage] {
        guard !postIDs.isEmpty else { return [] }

        let records: [CommunityPostImageRecord] = try await client
            .from("post_images")
            .select()
            .in("post_id", values: postIDs.map(\.uuidString))
            .order("sort_order", ascending: true)
            .execute()
            .value

        guard !records.isEmpty else { return [] }

        let paths = records
            .map(\.path)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            return records.map { record in
                CommunityPostImage(
                    id: record.id,
                    postID: record.postID,
                    path: record.path,
                    thumbnailPath: record.thumbnailPath,
                    sortOrder: record.sortOrder,
                    width: record.width,
                    height: record.height,
                    thumbnailWidth: record.thumbnailWidth,
                    thumbnailHeight: record.thumbnailHeight,
                    fullWidth: record.fullWidth,
                    fullHeight: record.fullHeight,
                    createdAt: record.createdAt,
                    signedURL: nil,
                    thumbnailURL: nil,
                    fullURL: nil
                )
            }
        }

        let signedResults = try await client.storage
            .from(Self.storageBucket)
            .createSignedURLs(paths: paths, expiresIn: 60 * 60 * 24)

        let signedPairs: [(String, URL)] = signedResults.compactMap { result in
            guard let signedURL = result.signedURL else { return nil }
            return (result.path, signedURL)
        }
        let signedMap = LeafyFirstValueMap.build(signedPairs)

        return records.map { record in
            CommunityPostImage(
                id: record.id,
                postID: record.postID,
                path: record.path,
                thumbnailPath: record.thumbnailPath,
                sortOrder: record.sortOrder,
                width: record.width,
                height: record.height,
                thumbnailWidth: record.thumbnailWidth,
                thumbnailHeight: record.thumbnailHeight,
                fullWidth: record.fullWidth,
                fullHeight: record.fullHeight,
                createdAt: record.createdAt,
                signedURL: signedMap[record.path],
                thumbnailURL: nil,
                fullURL: nil
            )
        }
    }

    nonisolated func fetchPostLikes(postIDs: [UUID], client: SupabaseClient) async throws -> [CommunityPostLikeRecord] {
        guard !postIDs.isEmpty else { return [] }

        return try await client
            .from("post_likes")
            .select()
            .in("post_id", values: postIDs.map(\.uuidString))
            .execute()
            .value
    }

    nonisolated func fetchPostAttachments(
        postIDs: [UUID],
        client: SupabaseClient
    ) async throws -> [CommunityPostAttachment] {
        guard !postIDs.isEmpty else { return [] }
        if await backendFeatureSupport(.communityPostAttachments) == false {
            let refreshed = try? await SupabaseBackendClient.shared.capabilities(forceRefresh: true)
            if refreshed?.supports(.communityPostAttachments) != true {
                CommunityDiagnostics.log.error(
                    "Backend feature unavailable after refresh: community_post_attachments version=\(refreshed?.version ?? -1, privacy: .public)"
                )
                throw CommunityServiceError.edgeFunctionRejected("社区服务需要更新后才能加载帖子，请稍后重试。")
            }
        }
        let records: [CommunityPostAttachmentRecord] = try await client
            .from("post_attachments")
            .select()
            .in("post_id", values: postIDs.map(\.uuidString))
            .order("sort_order", ascending: true)
            .execute()
            .value
        return records.map {
            CommunityPostAttachment(
                id: $0.id,
                postID: $0.postID,
                path: $0.path,
                displayName: $0.displayName,
                contentType: $0.contentType,
                fileExtension: $0.fileExtension,
                byteSize: $0.byteSize,
                sha256: $0.sha256,
                sortOrder: $0.sortOrder,
                createdAt: $0.createdAt
            )
        }
    }

    nonisolated func fetchPostFavorites(
        postIDs: [UUID],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityPostFavoriteRecord] {
        guard let viewerID, !postIDs.isEmpty else { return [] }

        return try await client
            .from("post_favorites")
            .select()
            .eq("user_id", value: viewerID.uuidString)
            .in("post_id", values: postIDs.map(\.uuidString))
            .execute()
            .value
    }

    nonisolated func fetchBlockedUserIDs(viewerID: UUID, client: SupabaseClient) async throws -> Set<UUID> {
        let records: [CommunityBlockRecord] = try await client
            .from("community_blocks")
            .select()
            .eq("blocker_id", value: viewerID.uuidString)
            .execute()
            .value

        return Set(records.map(\.blockedID))
    }

    nonisolated func filterBlockedPosts(
        _ posts: [CommunityPost],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityPost] {
        guard let viewerID else { return posts }
        let blockedIDs = try await fetchBlockedUserIDs(viewerID: viewerID, client: client)
        guard !blockedIDs.isEmpty else { return posts }
        return posts.filter { !blockedIDs.contains($0.authorID) }
    }

    nonisolated func filterBlockedComments(
        _ comments: [CommunityComment],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityComment] {
        guard let viewerID else { return comments }
        let blockedIDs = try await fetchBlockedUserIDs(viewerID: viewerID, client: client)
        guard !blockedIDs.isEmpty else { return comments }
        return comments.filter { !blockedIDs.contains($0.authorID) }
    }

    func fetchSiteAnnouncementReads(
        announcementIDs: [UUID],
        userID: UUID
    ) async throws -> [SiteAnnouncementReadRecord] {
        guard !announcementIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        return try await client
            .from("site_announcement_reads")
            .select()
            .eq("user_id", value: userID.uuidString)
            .in("announcement_id", values: announcementIDs.map(\.uuidString))
            .execute()
            .value
    }

    func isSiteAnnouncementActive(_ record: SiteAnnouncementRecord) -> Bool {
        guard record.status == "published" else { return false }

        let now = Date()
        if let publishedAt = record.publishedAt.flatMap(CommunityTimestampFormatter.parse),
           publishedAt > now {
            return false
        }

        if let expiresAt = record.expiresAt.flatMap(CommunityTimestampFormatter.parse),
           expiresAt <= now {
            return false
        }

        return true
    }

    nonisolated func hydrateProfiles(_ profiles: [CommunityProfile], client: SupabaseClient) async throws -> [CommunityProfile] {
        let storagePaths = profiles
            .flatMap { [$0.avatarPath, $0.coverPath] }
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !storagePaths.isEmpty else { return profiles }

        let signedResults = try await client.storage
            .from(Self.storageBucket)
            .createSignedURLs(paths: storagePaths, expiresIn: 60 * 60 * 24)

        let signedPairs: [(String, URL)] = signedResults.compactMap { result in
            guard let signedURL = result.signedURL else { return nil }
            return (result.path, signedURL)
        }
        let signedMap = LeafyFirstValueMap.build(signedPairs)

        return profiles.map { profile in
            CommunityProfile(
                id: profile.id,
                eduID: profile.eduID,
                campusID: profile.campusID,
                communityCampusID: profile.communityCampusID,
                communityAccessStatusRaw: profile.communityAccessStatusRaw,
                communitySchoolName: profile.communitySchoolName,
                communityRejectionReason: profile.communityRejectionReason,
                nickname: profile.nickname,
                displayName: profile.displayName,
                avatarPath: profile.avatarPath,
                coverPath: profile.coverPath,
                bio: profile.bio,
                major: profile.major,
                grade: profile.grade,
                boundEmail: profile.boundEmail,
                pendingBoundEmail: profile.pendingBoundEmail,
                emailVerificationSentAt: profile.emailVerificationSentAt,
                profileEditedAt: profile.profileEditedAt,
                isProfileComplete: profile.isProfileComplete,
                createdAt: profile.createdAt,
                updatedAt: profile.updatedAt,
                signedAvatarURL: profile.avatarPath.flatMap { signedMap[$0] },
                avatarURL: profile.avatarURL,
                signedCoverURL: profile.coverPath.flatMap { signedMap[$0] },
                coverURL: profile.coverURL,
                showsEduVerificationBadge: profile.showsEduVerificationBadge
            )
        }
    }

    func requireCompletedCurrentProfile() async throws -> CommunityProfile {
        guard let profile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let trimmedNickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profile.isProfileComplete && !trimmedNickname.isEmpty else {
            throw CommunityServiceError.profileCompletionRequired
        }

        return profile
    }

    func requireAcceptedCurrentTerms() async throws {
        guard try await hasAcceptedCurrentTerms() else {
            throw CommunityServiceError.termsAcceptanceRequired
        }
    }

    func trimmedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func mapEmailAuthError(_ error: Error) -> CommunityServiceError {
        if let serviceError = error as? CommunityServiceError {
            return serviceError
        }

        if let authError = error as? AuthError {
            CommunityDiagnostics.log.error(
                "Email verification failed authCode=\(String(describing: authError.errorCode), privacy: .public)"
            )
            switch authError.errorCode {
            case .otpExpired:
                return .edgeFunctionRejected("验证码已失效，请重新发送并使用最新邮件中的验证码。")
            case .overEmailSendRateLimit, .overRequestRateLimit:
                return .edgeFunctionRejected("验证码发送太频繁，请稍后再试。")
            case .emailExists, .userAlreadyExists, .conflict:
                return .edgeFunctionRejected("这个邮箱已被其他账号绑定或注册，请换一个邮箱。")
            case .emailProviderDisabled, .otpDisabled:
                return .edgeFunctionRejected("当前邮箱验证服务暂不可用，请稍后再试。")
            default:
                let message = authError.message
                if message.localizedCaseInsensitiveContains("otp")
                    || message.localizedCaseInsensitiveContains("token")
                    || message.localizedCaseInsensitiveContains("code") {
                    return .edgeFunctionRejected("验证码不正确，请核对邮件中的数字后重试。")
                }
                if message.localizedCaseInsensitiveContains("email") {
                    return .edgeFunctionRejected(message)
                }
            }
        }

        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("EMAIL_NOT_VERIFIED") {
            return .edgeFunctionRejected("邮箱尚未完成验证，请输入邮件验证码。")
        }
        if message.contains("23505")
            || message.localizedCaseInsensitiveContains("profiles_bound_email_unique")
            || message.localizedCaseInsensitiveContains("duplicate key") {
            return .edgeFunctionRejected("这个邮箱已被其他账号绑定或注册，请换一个邮箱。")
        }
        return .edgeFunctionRejected(message)
    }

    func isDuplicateCatalogSuggestion(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("23505")
            || message.contains("duplicate key")
            || message.contains("idx_catalog_suggestions_open_unique")
    }

    nonisolated func isMissingSchemaColumn(_ error: Error, column: String) -> Bool {
        let message = error.localizedDescription
        return message.contains(column) && message.localizedCaseInsensitiveContains("schema cache")
    }

    nonisolated func isMissingPostPinsTable(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("community_post_pins")
            && (
                message.localizedCaseInsensitiveContains("schema cache")
                || message.localizedCaseInsensitiveContains("does not exist")
                || message.localizedCaseInsensitiveContains("not found")
            )
    }

    nonisolated func backendFeatureSupport(_ feature: BackendFeature) async -> Bool? {
        do {
            return try await SupabaseBackendClient.shared.capabilities().supports(feature)
        } catch {
            CommunityDiagnostics.log.info("Backend capabilities unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated func backendRPCSupport(_ name: String) async -> Bool? {
        do {
            return try await SupabaseBackendClient.shared.capabilities().supportsRPC(name)
        } catch {
            CommunityDiagnostics.log.info("Backend RPC capability unavailable for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated func requireBackendRPC(
        _ name: String,
        unavailableMessage: String
    ) async throws {
        if await backendRPCSupport(name) == false {
            let refreshed = try? await SupabaseBackendClient.shared.capabilities(forceRefresh: true)
            if refreshed?.supportsRPC(name) != true {
                CommunityDiagnostics.log.error(
                    "Backend RPC unavailable after refresh: \(name, privacy: .public) version=\(refreshed?.version ?? -1, privacy: .public)"
                )
                throw CommunityServiceError.edgeFunctionRejected(unavailableMessage)
            }
        }
    }

    nonisolated func requireBackendEdgeFunction(
        _ name: String,
        unavailableMessage: String
    ) async throws {
        do {
            var capabilities = try await SupabaseBackendClient.shared.capabilities()
            if !capabilities.edgeFunctions.contains(name) {
                capabilities = try await SupabaseBackendClient.shared.capabilities(forceRefresh: true)
                if !capabilities.edgeFunctions.contains(name) {
                    CommunityDiagnostics.log.error(
                        "Backend Edge Function unavailable after refresh: \(name, privacy: .public) version=\(capabilities.version, privacy: .public)"
                    )
                    throw CommunityServiceError.edgeFunctionRejected(unavailableMessage)
                }
            }
        } catch let error as CommunityServiceError {
            throw error
        } catch {
            CommunityDiagnostics.log.info(
                "Backend Edge Function capability unavailable for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    nonisolated func mapFunctionsError(_ error: FunctionsError) -> CommunityServiceError {
        let envelope = SupabaseBackendClient.shared.mapFunctionsError(
            error,
            fallbackMessage: "社区函数调用失败，请稍后重试。"
        )
        return .edgeFunctionRejected(envelope.message)
    }

    func mapCommunityMutationError(_ error: Error, fallback: String) -> CommunityServiceError {
        let message = error.localizedDescription
        if message.contains("POST_RATE_LIMIT_EXCEEDED") {
            return .postRateLimitExceeded
        }
        if message.contains("COMMUNITY_USER_MUTED") {
            return .userMuted
        }
        if message.contains("COMMUNITY_PROFILE_REQUIRED") {
            return .missingAuthenticatedUser
        }
        if message.contains("PROFILE_COMPLETION_REQUIRED") {
            return .profileCompletionRequired
        }
        if message.contains("COMMUNITY_TERMS_REQUIRED") {
            return .termsAcceptanceRequired
        }
        if message.contains("CANNOT_LIKE_OWN_POST") {
            return .cannotLikeOwnPost
        }
        if message.contains("COMMUNITY_POST_NOT_FOUND") {
            return .edgeFunctionRejected("内容已不存在或不可见。")
        }
        if message.contains("COMMUNITY_CONTENT_REJECTED") {
            return .contentRejected
        }
        if message.contains("COMMUNITY_POLL_INVALID") {
            return .invalidPoll
        }
        if message.contains("COMMUNITY_POLL_CLOSED") {
            return .pollClosed
        }
        if message.contains("COMMUNITY_POLL_DELETION_PENDING") {
            return .edgeFunctionRejected("删除申请正在审核中。")
        }
        if message.contains("COMMUNITY_POLL_NOT_FOUND") || message.contains("COMMUNITY_POLL_OPTION_NOT_FOUND") {
            return .edgeFunctionRejected("投票已不存在或不可见。")
        }

        return .edgeFunctionRejected("\(fallback)：\(message)")
    }
}

nonisolated struct EdgeFunctionErrorPayload: Decodable, Sendable {
    let error: String?
    let errorEnvelope: BackendErrorEnvelope?
}

nonisolated enum CommunityCampusRequestAction: String, Encodable, Sendable {
    case current
    case submitNewSchool = "submit_new_school"
    case selectExisting = "select_existing"
    case requestChange = "request_change"
}

nonisolated struct CommunityCampusSearchParams: Encodable, Sendable {
    let search: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case search = "p_search"
        case limit = "p_limit"
    }
}

nonisolated struct CommunityCampusRequestSubmitRequest: Encodable, Sendable {
    let action: CommunityCampusRequestAction
    let schoolName: String?
    let campusID: String?

    init(
        action: CommunityCampusRequestAction,
        schoolName: String? = nil,
        campusID: String? = nil
    ) {
        self.action = action
        self.schoolName = schoolName
        self.campusID = campusID
    }

    enum CodingKeys: String, CodingKey {
        case action
        case schoolName = "school_name"
        case campusID = "campus_id"
    }
}

nonisolated struct CommunityCampusRequestResponse: Decodable, Sendable {
    let profile: CommunityProfile?
    let request: CommunityCampusMembershipRequest?
}

nonisolated struct CommunityBootstrapRequest: Encodable, Sendable {
    let eduID: String
    let displayName: String
    let campusID: String

    enum CodingKeys: String, CodingKey {
        case eduID = "edu_id"
        case displayName = "display_name"
        case campusID = "campus_id"
    }
}

nonisolated struct CommunityBootstrapResponse: Decodable, Sendable {
    let profile: CommunityProfile
    let isNewUser: Bool
    let isProfileComplete: Bool

    enum CodingKeys: String, CodingKey {
        case profile
        case isNewUser = "is_new_user"
        case isProfileComplete = "is_profile_complete"
    }
}

nonisolated struct CommunityAccountDeletionResponse: Decodable, Sendable {
    let deleted: Bool
}

nonisolated struct CommunityFeedResponse: Decodable, Sendable {
    let generatedAt: String?
    let posts: [CommunityPost]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case posts
    }
}

nonisolated struct CommunityProfileStatsRPCParams: Encodable, Sendable {
    let profileIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case profileIDs = "p_profile_ids"
    }
}

nonisolated struct CommunityProfileStatsResponse: Decodable, Sendable {
    let generatedAt: String?
    let profiles: [CommunityProfileStats]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case profiles
    }
}

nonisolated struct CommunityProfileAuthLinkRecord: Decodable, Sendable {
    let authUserID: UUID
    let profileID: UUID

    enum CodingKeys: String, CodingKey {
        case authUserID = "auth_user_id"
        case profileID = "profile_id"
    }
}

nonisolated struct CommunityProfileUpdate: Encodable, Sendable {
    let nickname: String
    let avatarPath: String?
    let coverPath: String?
    let bio: String?
    let major: String?
    let grade: String?
    let profileEditedAt: String
    let isProfileComplete: Bool
    let showsEduVerificationBadge: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case nickname
        case avatarPath = "avatar_path"
        case coverPath = "cover_path"
        case bio
        case major
        case grade
        case profileEditedAt = "profile_edited_at"
        case isProfileComplete = "is_profile_complete"
        case showsEduVerificationBadge = "shows_edu_verification_badge"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(avatarPath, forKey: .avatarPath)
        if let coverPath {
            try container.encode(coverPath, forKey: .coverPath)
        } else {
            try container.encodeNil(forKey: .coverPath)
        }
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(major, forKey: .major)
        try container.encodeIfPresent(grade, forKey: .grade)
        try container.encode(profileEditedAt, forKey: .profileEditedAt)
        try container.encode(isProfileComplete, forKey: .isProfileComplete)
        try container.encode(showsEduVerificationBadge, forKey: .showsEduVerificationBadge)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

nonisolated struct CommunityPendingEmailUpdate: Encodable, Sendable {
    let pendingBoundEmail: String
    let emailVerificationSentAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case pendingBoundEmail = "pending_bound_email"
        case emailVerificationSentAt = "email_verification_sent_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityVerifiedEmailUpdate: Encodable, Sendable {
    let boundEmail: String
    let pendingBoundEmail: String?
    let emailVerificationSentAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case boundEmail = "bound_email"
        case pendingBoundEmail = "pending_bound_email"
        case emailVerificationSentAt = "email_verification_sent_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(boundEmail, forKey: .boundEmail)
        try container.encodeNil(forKey: .pendingBoundEmail)
        try container.encodeNil(forKey: .emailVerificationSentAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

nonisolated struct CommunityPostSoftDeleteRPCParams: Encodable, Sendable {
    let targetPostID: UUID

    enum CodingKeys: String, CodingKey {
        case targetPostID = "target_post_id"
    }
}

nonisolated struct CommunityCommentSoftDeleteRPCParams: Encodable, Sendable {
    let targetCommentID: UUID

    enum CodingKeys: String, CodingKey {
        case targetCommentID = "target_comment_id"
    }
}

nonisolated struct CommunityTermsAcceptanceRecord: Decodable, Sendable {
    let userID: UUID
    let termsVersion: String
    let acceptedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case termsVersion = "terms_version"
        case acceptedAt = "accepted_at"
    }
}

nonisolated struct CommunityTermsAcceptanceRPCParams: Encodable, Sendable {
    let termsVersion: String

    enum CodingKeys: String, CodingKey {
        case termsVersion = "p_terms_version"
    }
}

nonisolated struct CommunityPostIDRPCParams: Encodable, Sendable {
    let postID: UUID

    enum CodingKeys: String, CodingKey {
        case postID = "p_post_id"
    }
}

nonisolated struct CommunityPollIDRPCParams: Encodable, Sendable {
    let pollID: UUID

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
    }
}

nonisolated struct CommunityPollListRPCParams: Encodable, Sendable {
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case limit = "p_limit"
    }
}

nonisolated struct CommunityRequestPollDeletionRPCParams: Encodable, Sendable {
    let pollID: UUID
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
        case reason = "p_reason"
    }
}

nonisolated struct CommunityVotePollRPCParams: Encodable, Sendable {
    let pollID: UUID
    let optionID: UUID

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
        case optionID = "p_option_id"
    }
}

nonisolated struct CommunityCreatePollRPCParams: Encodable, Sendable {
    let question: String
    let detail: String?
    let options: [String]
    let closesAt: String?

    init(input: CreatePollInput) {
        question = String(input.normalizedQuestion.prefix(CommunityPollRules.maxQuestionLength))
        detail = input.normalizedDetail.map { String($0.prefix(CommunityPollRules.maxDetailLength)) }
        options = input.normalizedOptions
            .prefix(CommunityPollRules.maxOptions)
            .map { String($0.prefix(CommunityPollRules.maxOptionLength)) }
        closesAt = input.closesAt
    }

    enum CodingKeys: String, CodingKey {
        case question = "p_question"
        case detail = "p_detail"
        case options = "p_options"
        case closesAt = "p_closes_at"
    }
}

nonisolated struct CommunityBlockRecord: Decodable, Sendable {
    let blockerID: UUID
    let blockedID: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityReportContentRPCParams: Encodable, Sendable {
    let targetType: CommunityReportTargetType
    let postID: UUID?
    let commentID: UUID?
    let reportedUserID: UUID?
    let reason: String
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case targetType = "p_target_type"
        case postID = "p_post_id"
        case commentID = "p_comment_id"
        case reportedUserID = "p_reported_user_id"
        case reason = "p_reason"
        case detail = "p_detail"
    }
}

nonisolated struct CommunityBlockUserRPCParams: Encodable, Sendable {
    let blockedID: UUID
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case blockedID = "p_blocked_id"
        case reason = "p_reason"
    }
}

nonisolated struct CommunityUnblockUserRPCParams: Encodable, Sendable {
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockedID = "p_blocked_id"
    }
}

nonisolated struct CommunityPostRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
    let commentCount: Int
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case title
        case body
        case category
        case isAnonymous = "is_anonymous"
        case commentCount = "comment_count"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityPendingPostContextRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case status
    }
}

nonisolated struct CommunityPostRateLimitRecord: Decodable, Sendable {
    let id: UUID
}

nonisolated struct CommunityPollRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let question: String
    let detail: String?
    let status: String
    let totalVoteCount: Int
    let closesAt: String?
    let deletionStatus: String
    let deletionRequestedAt: String?
    let deletionReason: String?
    let deletionReviewedAt: String?
    let deletionReviewReason: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case question
        case detail
        case status
        case totalVoteCount = "total_vote_count"
        case closesAt = "closes_at"
        case deletionStatus = "deletion_status"
        case deletionRequestedAt = "deletion_requested_at"
        case deletionReason = "deletion_reason"
        case deletionReviewedAt = "deletion_reviewed_at"
        case deletionReviewReason = "deletion_review_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorID = try container.decode(UUID.self, forKey: .authorID)
        question = try container.decode(String.self, forKey: .question)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        status = try container.decode(String.self, forKey: .status)
        totalVoteCount = try container.decode(Int.self, forKey: .totalVoteCount)
        closesAt = try container.decodeIfPresent(String.self, forKey: .closesAt)
        deletionStatus = try container.decodeIfPresent(String.self, forKey: .deletionStatus) ?? "none"
        deletionRequestedAt = try container.decodeIfPresent(String.self, forKey: .deletionRequestedAt)
        deletionReason = try container.decodeIfPresent(String.self, forKey: .deletionReason)
        deletionReviewedAt = try container.decodeIfPresent(String.self, forKey: .deletionReviewedAt)
        deletionReviewReason = try container.decodeIfPresent(String.self, forKey: .deletionReviewReason)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

nonisolated struct CommunityPollVoteRecord: Decodable, Sendable {
    let pollID: UUID
    let optionID: UUID
    let userID: UUID
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case pollID = "poll_id"
        case optionID = "option_id"
        case userID = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityPostLikeRecord: Decodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityPostFavoriteRecord: Decodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityNotificationRecord: Decodable, Sendable {
    let id: UUID
    let recipientID: UUID
    let actorID: UUID?
    let postID: UUID?
    let commentID: UUID?
    let type: CommunityNotificationType
    let title: String
    let body: String?
    let isRead: Bool
    let createdAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case recipientID = "recipient_id"
        case actorID = "actor_id"
        case postID = "post_id"
        case commentID = "comment_id"
        case type
        case title
        case body
        case isRead = "is_read"
        case createdAt = "created_at"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct CommunityNotificationSettingsRecord: Decodable, Sendable {
    let userID: UUID
    let mutedAll: Bool
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mutedAll = "muted_all"
        case updatedAt = "updated_at"
    }
}

nonisolated struct SiteAnnouncementRecord: Decodable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let level: SiteAnnouncementLevel
    let status: String
    let publishedAt: String?
    let expiresAt: String?
    let createdBy: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case level
        case status
        case publishedAt = "published_at"
        case expiresAt = "expires_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

nonisolated struct SiteAnnouncementReadRecord: Decodable, Sendable {
    let announcementID: UUID
    let userID: UUID
    let readAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case userID = "user_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct CommunityNotificationReadUpdate: Encodable, Sendable {
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
    }
}

nonisolated struct CommunityNotificationDismissUpdate: Encodable, Sendable {
    let isRead: Bool
    let dismissedAt: String

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct CommunityNotificationSettingsUpsert: Encodable, Sendable {
    let userID: UUID
    let mutedAll: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mutedAll = "muted_all"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityNotificationRPCParams: Encodable, Sendable {
    let recipientID: UUID
    let actorID: UUID
    let postID: UUID
    let commentID: UUID?
    let type: CommunityNotificationType
    let title: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case recipientID = "p_recipient_id"
        case actorID = "p_actor_id"
        case postID = "p_post_id"
        case commentID = "p_comment_id"
        case type = "p_type"
        case title = "p_title"
        case body = "p_body"
    }
}

nonisolated struct SiteAnnouncementReadInsert: Encodable, Sendable {
    let announcementID: UUID
    let userID: UUID
    let readAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case userID = "user_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct FeedbackSubmissionInsert: Encodable, Sendable {
    let userID: UUID?
    let issueType: String
    let body: String
    let contact: String?
    let deviceInfo: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case issueType = "issue_type"
        case body
        case contact
        case deviceInfo = "device_info"
    }
}

nonisolated struct CatalogSuggestionInsert: Encodable, Sendable {
    let suggestionType: String
    let userID: UUID?
    let name: String
    let unit: String
    let teacherName: String?
    let category: String?
    let credit: Double?
    let initialStars: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case suggestionType = "suggestion_type"
        case userID = "user_id"
        case name
        case unit
        case teacherName = "teacher_name"
        case category
        case credit
        case initialStars = "initial_stars"
        case note
    }
}

nonisolated struct TeacherRatingInsert: Encodable, Sendable {
    let teacherID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case teacherID = "teacher_id"
        case userID = "user_id"
        case stars
    }
}

nonisolated struct TeacherRatingStarsUpdate: Encodable, Sendable {
    let stars: Int
}

nonisolated struct CourseRatingInsert: Encodable, Sendable {
    let courseID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case userID = "user_id"
        case stars
    }
}

nonisolated struct DishRatingInsert: Encodable, Sendable {
    let dishID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case dishID = "dish_id"
        case userID = "user_id"
        case stars
    }
}

nonisolated struct CommunityCreatePostV4RPCParams: Encodable, Sendable {
    let id: UUID
    let requestID: UUID?
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
    let imageCount: Int
    let attachmentCount: Int

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case requestID = "p_request_id"
        case title = "p_title"
        case body = "p_body"
        case category = "p_category"
        case isAnonymous = "p_is_anonymous"
        case imageCount = "p_image_count"
        case attachmentCount = "p_attachment_count"
    }
}

nonisolated struct CommunityPostImageRecord: Decodable, Sendable {
    let id: UUID
    let postID: UUID
    let path: String
    let thumbnailPath: String?
    let sortOrder: Int
    let width: Int?
    let height: Int?
    let thumbnailWidth: Int?
    let thumbnailHeight: Int?
    let fullWidth: Int?
    let fullHeight: Int?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case path
        case thumbnailPath = "thumbnail_path"
        case sortOrder = "sort_order"
        case width
        case height
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
        case fullWidth = "full_width"
        case fullHeight = "full_height"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityPostAttachmentRecord: Decodable, Sendable {
    let id: UUID
    let postID: UUID
    let path: String
    let displayName: String
    let contentType: String
    let fileExtension: String
    let byteSize: Int
    let sha256: String
    let sortOrder: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case path
        case displayName = "display_name"
        case contentType = "content_type"
        case fileExtension = "file_extension"
        case byteSize = "byte_size"
        case sha256
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityUploadValidationRequest: Encodable, Sendable {
    let postID: String
    let fullPath: String
    let thumbnailPath: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case fullPath = "full_path"
        case thumbnailPath = "thumbnail_path"
    }
}

nonisolated struct CommunityAttachmentValidationRequest: Encodable, Sendable {
    let postID: String
    let objectPath: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case objectPath = "object_path"
        case displayName = "display_name"
    }
}

nonisolated struct CommunityAttachmentValidationResponse: Decodable, Sendable {
    let receiptID: UUID

    enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id"
    }
}

nonisolated struct CommunityAttachPostAttachmentRPCParams: Encodable, Sendable {
    let receiptID: UUID
    let attachmentID: UUID
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case receiptID = "p_receipt_id"
        case attachmentID = "p_attachment_id"
        case sortOrder = "p_sort_order"
    }
}

nonisolated struct CommunityAttachmentDownloadRequest: Encodable, Sendable {
    let attachmentID: UUID

    enum CodingKeys: String, CodingKey {
        case attachmentID = "attachment_id"
    }
}

nonisolated struct CommunityAttachmentDownloadResponse: Decodable, Sendable {
    let url: URL
    let displayName: String
    let contentType: String
    let byteSize: Int

    enum CodingKeys: String, CodingKey {
        case url
        case displayName = "display_name"
        case contentType = "content_type"
        case byteSize = "byte_size"
    }
}

nonisolated struct CommunityProfileUploadValidationRequest: Encodable, Sendable {
    let kind: String
    let objectPath: String

    enum CodingKeys: String, CodingKey {
        case kind
        case objectPath = "object_path"
    }
}

nonisolated struct CommunityProfileUploadValidationResponse: Decodable, Sendable {
    let validated: Bool
}

nonisolated struct CommunityUploadValidationResponse: Decodable, Sendable {
    let receiptID: UUID

    enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id"
    }
}

nonisolated struct CommunityAttachPostImageRPCParams: Encodable, Sendable {
    let receiptID: UUID
    let imageID: UUID
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case receiptID = "p_receipt_id"
        case imageID = "p_image_id"
        case sortOrder = "p_sort_order"
    }
}

nonisolated struct CommunityCommentRecord: Decodable, Sendable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let isAnonymous: Bool
    let status: String
    let createdAt: String
    let updatedAt: String
    let parentCommentID: UUID?
    let replyToCommentID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case isAnonymous = "is_anonymous"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case parentCommentID = "parent_comment_id"
        case replyToCommentID = "reply_to_comment_id"
    }
}

nonisolated struct CommunityCreateCommentV2RPCParams: Encodable, Sendable {
    let id: UUID
    let requestID: UUID?
    let postID: UUID
    let body: String
    let parentCommentID: UUID?
    let replyToCommentID: UUID?
    let isAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case requestID = "p_request_id"
        case postID = "p_post_id"
        case body = "p_body"
        case parentCommentID = "p_parent_comment_id"
        case replyToCommentID = "p_reply_to_comment_id"
        case isAnonymous = "p_is_anonymous"
    }
}

nonisolated struct CommunityCommentThreadPageRPCParams: Encodable, Sendable {
    let postID: UUID
    let afterCreatedAt: String?
    let afterID: UUID?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case postID = "p_post_id"
        case afterCreatedAt = "p_after_created_at"
        case afterID = "p_after_id"
        case limit = "p_limit"
    }
}

nonisolated struct CommunityCommentThreadPageRecord: Decodable, Sendable {
    let comments: [CommunityThreadCommentRecord]
    let hasMore: Bool
    let nextCursorCreatedAt: String?
    let nextCursorID: UUID?

    enum CodingKeys: String, CodingKey {
        case comments
        case hasMore = "has_more"
        case nextCursorCreatedAt = "next_cursor_created_at"
        case nextCursorID = "next_cursor_id"
    }
}

nonisolated struct CommunityThreadCommentRecord: Decodable, Sendable {
    let threadRootID: UUID
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let isAnonymous: Bool
    let status: String
    let createdAt: String
    let updatedAt: String
    let parentCommentID: UUID?
    let replyToCommentID: UUID?
    let replyToAuthorID: UUID?
    let replyTargetIsVisible: Bool
    let likeCount: Int
    let viewerHasLiked: Bool
    let isDeletedPlaceholder: Bool

    enum CodingKeys: String, CodingKey {
        case threadRootID = "thread_root_id"
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case isAnonymous = "is_anonymous"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case parentCommentID = "parent_comment_id"
        case replyToCommentID = "reply_to_comment_id"
        case replyToAuthorID = "reply_to_author_id"
        case replyTargetIsVisible = "reply_target_is_visible"
        case likeCount = "like_count"
        case viewerHasLiked = "viewer_has_liked"
        case isDeletedPlaceholder = "is_deleted_placeholder"
    }
}

nonisolated struct CommunityCommentIDRPCParams: Encodable, Sendable {
    let commentID: UUID
    let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case commentID = "p_comment_id"
        case requestID = "p_request_id"
    }
}

nonisolated struct CommunityCommentLikeStateRecord: Decodable, Sendable {
    let commentID: UUID
    let likeCount: Int
    let viewerHasLiked: Bool

    enum CodingKeys: String, CodingKey {
        case commentID = "comment_id"
        case likeCount = "like_count"
        case viewerHasLiked = "viewer_has_liked"
    }
}

nonisolated enum CommunityCommentLikeResponseValidator {
    static func state(
        from records: [CommunityCommentLikeStateRecord]
    ) throws -> CommunityCommentLikeState {
        guard records.count == 1, let record = records.first else {
            throw CommunityServiceError.edgeFunctionRejected("评论点赞返回数据异常，请稍后重试。")
        }
        return CommunityCommentLikeState(
            commentID: record.commentID,
            likeCount: record.likeCount,
            viewerHasLiked: record.viewerHasLiked
        )
    }
}
