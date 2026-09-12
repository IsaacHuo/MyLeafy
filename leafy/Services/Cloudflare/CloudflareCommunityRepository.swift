import Foundation
import Supabase
import OSLog

/// REST implementation of the existing feature repositories. It never delegates
/// business requests to Supabase; the old session is used only for explicit exchange.
nonisolated struct CloudflareCommunityRepository: CommunityRepository, CommunityActivityRepository, CommunityIdentitySessionRepository, CommunityBannerRepository, CommunityFeedChangeStreaming, CommunityPublishBackend {
    var currentAuthUserID: UUID? { MyLeafyBackendEnvironment.cachedUserID }
    func client() throws -> MyLeafyBackendClient { try MyLeafyBackendEnvironment.client() }
    struct Empty: Codable, Sendable {}
    func perform<B: Encodable & Sendable>(_ path: String, method: String = "POST", body: B) async throws {
        try await client().perform(path, method: method, body: body)
    }
    func perform(_ path: String, method: String = "POST") async throws { try await perform(path, method: method, body: Empty()) }
    func get<T: Decodable & Sendable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T { try await client().get(path, query: query) }
    func request<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, method: String = "POST", body: B) async throws -> T { try await client().request(path, method: method, body: body) }
    func query(_ values: [String: String?]) -> [URLQueryItem] { values.sorted { $0.key < $1.key }.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } } }
    func ensureAnonymousSession() async throws {
        let backend = try client()
        guard ActiveCampusContext.descriptor.id != .guest else { throw CommunityServiceError.missingAuthenticatedUser }
        if await backend.authUserID != nil { return }
        if let legacyClient = LeafySupabase.shared.client, legacyClient.auth.currentSession != nil {
            let legacy = try await legacyClient.auth.session
            try await backend.establishSession(legacyToken: legacy.accessToken, legacyAnonymous: legacy.user.isAnonymous)
            try await legacyClient.auth.signOut(scope: .local)
        } else {
            guard ActiveCampusContext.descriptor.id != .custom else { throw CustomCampusAuthError.missingSession }
            try await backend.establishSession()
        }
    }
    func signOut(localOnly: Bool) async {
        do { try await client().signOut(localOnly: localOnly) }
        catch { CommunityDiagnostics.log.error("Cloudflare sign out failed: \(error.localizedDescription, privacy: .public)") }
    }
    func fetchCurrentProfile() async throws -> CommunityProfile? {
        do { return try await get("/v1/profile") }
        catch let error as MyLeafyBackendError where error.code == "profile_required" { return nil }
    }
    func bootstrapCommunityUser(eduID: String, displayName: String, campusID: String) async throws -> CommunityProfile {
        let result: CommunityBootstrapResponse = try await request("/v1/profile/bootstrap", body: CommunityBootstrapRequest(eduID: eduID, displayName: displayName, campusID: campusID))
        return result.profile
    }
    func deleteCurrentAccount() async throws {
        let response: CommunityAccountDeletionResponse = try await request("/v1/account", method: "DELETE", body: Empty())
        guard response.deleted else { throw CommunityServiceError.accountDeletionFailed }
        try await client().signOut(localOnly: true)
    }
    func fetchProfile(userID: UUID) async throws -> CommunityProfile? {
        do { return try await get("/v1/profiles/\(userID)") }
        catch let error as MyLeafyBackendError where error.status == 404 { return nil }
    }
    func fetchProfileStats(profileIDs: [UUID]) async throws -> [CommunityProfileStats] {
        struct Input: Encodable { let profile_ids: [UUID] }
        let result: CommunityProfileStatsResponse = try await request("/v1/profiles/stats", body: Input(profile_ids: profileIDs))
        return result.profiles
    }
    func updateProfile(input: CommunityProfileUpdateInput, avatar: CommunityImageUpload?, cover: CommunityImageUpload?, resetCoverToDefault: Bool) async throws -> CommunityProfile {
        let nickname = CommunityNickname.normalized(input.nickname)
        guard !nickname.isEmpty else { throw CommunityServiceError.profileCompletionRequired }
        let avatarPath: String? = if let avatar { try await uploadProfileImage(avatar, kind: "avatar") } else { nil }
        let coverPath: String? = if !resetCoverToDefault, let cover { try await uploadProfileImage(cover, kind: "cover") } else { nil }
        return try await request("/v1/profile", method: "PATCH", body: ProfilePatch(nickname: nickname, bio: CommunityProfileBio.normalized(input.bio), major: input.major, grade: input.grade, showsBadge: input.showsEduVerificationBadge, avatarPath: avatarPath, coverPath: coverPath, resetCover: resetCoverToDefault))
    }
    private func uploadProfileImage(_ image: CommunityImageUpload, kind: String) async throws -> String {
        struct Uploaded: Decodable { let path: String }
        let uploaded: Uploaded = try await client().upload(data: image.data, contentType: image.mimeType, query: query(["kind":kind,"upload_id":image.id.uuidString.lowercased(),"name":"image.jpg"]))
        return uploaded.path
    }
    private struct ProfilePatch: Encodable {
        let nickname: String
        let bio: String?
        let major: String?
        let grade: String?
        let showsBadge: Bool
        let avatarPath: String?
        let coverPath: String?
        let resetCover: Bool
        enum Keys: String, CodingKey { case nickname, bio, major, grade; case showsBadge = "shows_edu_verification_badge"; case avatarPath = "avatar_path"; case coverPath = "cover_path" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(nickname, forKey: .nickname)
            try c.encodeIfPresent(bio, forKey: .bio)
            try c.encodeIfPresent(major, forKey: .major)
            try c.encodeIfPresent(grade, forKey: .grade)
            try c.encode(showsBadge, forKey: .showsBadge)
            try c.encodeIfPresent(avatarPath, forKey: .avatarPath)
            if resetCover { try c.encodeNil(forKey: .coverPath) }
            else { try c.encodeIfPresent(coverPath, forKey: .coverPath) }
        }
    }
    func requestEmailVerification(input: CommunityEmailBindingInput) async throws -> CommunityProfile {
        let email = CommunityEmailBinding.normalizedEmail(input.email)
        guard CommunityEmailBinding.isValidEmail(email) else { throw CommunityServiceError.invalidEmail }
        return try await request("/v1/profile/email/request", body: ["email":email])
    }
    func verifyEmailBinding(input: CommunityEmailVerificationInput) async throws -> CommunityProfile {
        guard CommunityEmailBinding.isCompleteVerificationCode(input.code) else { throw CommunityServiceError.edgeFunctionRejected("请输入邮件中的 8 位验证码。") }
        return try await request("/v1/profile/email/verify", body: ["email":CommunityEmailBinding.normalizedEmail(input.email),"otp":input.code])
    }
    func searchCommunityCampuses(query search: String, limit: Int) async throws -> [CommunityCampusOption] { try await get("/v1/campuses", query(["search":search,"limit":String(limit)])) }
    func selectCommunityCampus(campusID: String) async throws -> CommunityProfile { try await request("/v1/campus/select", body: ["campus_id":campusID]) }
    func fetchCurrentCampusMembershipRequest() async throws -> CommunityCampusMembershipRequest? { try await get("/v1/campus/membership") }
    func submitCommunitySchoolChangeRequest(campusID: String) async throws -> CommunityCampusMembershipRequest { try await request("/v1/campus/change", body: ["campus_id":campusID]) }
    func submitCampusMembershipRequest(schoolName: String) async throws -> CommunityProfile {
        let _: CommunityCampusMembershipRequest = try await request("/v1/campus/membership", body: ["school_name":schoolName])
        guard let profile = try await fetchCurrentProfile() else { throw CommunityServiceError.missingAuthenticatedUser }; return profile
    }
    func hasAcceptedCurrentTerms() async throws -> Bool {
        struct Terms: Decodable { let accepted: Bool }
        let result: Terms = try await get("/v1/community/terms"); return result.accepted
    }
    func acceptCurrentTerms() async throws { try await perform("/v1/community/terms") }
    func revokeCurrentTerms() async throws { try await perform("/v1/community/terms", method: "DELETE") }
    func fetchPosts(query: CommunityFeedQuery) async throws -> [CommunityPost] {
        let result: CommunityFeedResponse = try await get("/v1/community/feed", CommunityService.shared.communityFeedQueryItems(query))
        return result.posts
    }
    func fetchPost(postID: UUID) async throws -> CommunityPost? {
        do { return try await get("/v1/community/posts/\(postID)") }
        catch let error as MyLeafyBackendError where error.status == 404 { return nil }
    }
    func fetchLinkedPost(postID: UUID) async throws -> CommunityPost? { try await fetchPost(postID: postID) }
    func activityPosts(_ kind: String, _ userID: UUID, _ limit: Int) async throws -> [CommunityPost] { try await get("/v1/community/activity/posts", query(["kind":kind,"user_id":userID.uuidString,"limit":String(limit)])) }
    func fetchPosts(authoredBy userID: UUID, limit: Int) async throws -> [CommunityPost] { try await activityPosts("authored", userID, limit) }
    func fetchPublicPosts(authoredBy userID: UUID, limit: Int) async throws -> [CommunityPost] { try await activityPosts("public", userID, limit) }
    func fetchLikedPosts(by userID: UUID, limit: Int) async throws -> [CommunityPost] { try await activityPosts("liked", userID, limit) }
    func fetchFavoritedPosts(by userID: UUID, limit: Int) async throws -> [CommunityPost] { try await activityPosts("favorited", userID, limit) }
    func fetchMyComments(limit: Int) async throws -> [CommunityComment] { try await get("/v1/community/activity/comments", query(["limit":String(limit)])) }
    func fetchComments(postID: UUID) async throws -> [CommunityComment] { try await get("/v1/community/posts/\(postID)/comments") }
    func fetchCommentThreads(postID: UUID, cursor: CommunityCommentCursor?, limit: Int) async throws -> CommunityCommentPage {
        struct Page: Decodable { let comments: [CommunityComment]; let has_more: Bool; let next_cursor_created_at: String?; let next_cursor_id: UUID? }
        let result: Page = try await get("/v1/community/posts/\(postID)/comment-threads", query(["after_created_at":cursor?.createdAt,"after_id":cursor?.id.uuidString,"limit":String(limit)]))
        let grouped = Dictionary(grouping: result.comments, by: \.threadRootID)
        let threads = result.comments.filter { !$0.isReply }.map { root in CommunityCommentThread(root: root, replies: grouped[root.id, default: []].filter(\.isReply)) }
        let next: CommunityCommentCursor? = if result.has_more, let date = result.next_cursor_created_at, let id = result.next_cursor_id { CommunityCommentCursor(createdAt: date, id: id) } else { nil }
        return CommunityCommentPage(threads: threads, nextCursor: next)
    }
    func createComment(postID: UUID, body: String, parentCommentID: UUID?, replyToCommentID: UUID?) async throws -> CommunityComment { try await createComment(postID: postID, body: body, parentCommentID: parentCommentID, replyToCommentID: replyToCommentID, requestID: UUID()) }
    func createComment(postID: UUID, body: String, parentCommentID: UUID?, replyToCommentID: UUID?, requestID: UUID) async throws -> CommunityComment {
        struct Input: Encodable { let id: UUID; let request_id: UUID; let post_id: UUID; let body: String; let parent_comment_id: UUID?; let reply_to_comment_id: UUID?; let is_anonymous = false }
        return try await request("/v1/community/comments", body: Input(id: requestID, request_id: requestID, post_id: postID, body: body, parent_comment_id: parentCommentID, reply_to_comment_id: replyToCommentID))
    }
    func toggleCommentLike(commentID: UUID) async throws -> CommunityCommentLikeState {
        struct State: Decodable { let comment_id: UUID; let like_count: Int; let viewer_has_liked: Bool }
        let state: State = try await request("/v1/community/comments/\(commentID)/toggle-like", body: ["request_id":UUID().uuidString])
        return CommunityCommentLikeState(commentID: state.comment_id, likeCount: state.like_count, viewerHasLiked: state.viewer_has_liked)
    }
    func togglePostLike(postID: UUID) async throws -> CommunityPost { try await request("/v1/community/posts/\(postID)/toggle-like", body: Empty()) }
    func togglePostFavorite(postID: UUID) async throws -> CommunityPost { try await request("/v1/community/posts/\(postID)/toggle-favorite", body: Empty()) }
    func deletePost(postID: UUID) async throws { try await perform("/v1/community/posts/\(postID)", method: "DELETE") }
    func deleteComment(commentID: UUID) async throws { try await perform("/v1/community/comments/\(commentID)", method: "DELETE") }
    func reportPost(postID: UUID, reason: String) async throws { try await perform("/v1/community/reports", body: ["target_type":"post","post_id":postID.uuidString,"reason":reason]) }
    func reportComment(commentID: UUID, reason: String) async throws { try await perform("/v1/community/reports", body: ["target_type":"comment","comment_id":commentID.uuidString,"reason":reason]) }
    func blockUser(userID: UUID, reason: String?) async throws { try await perform("/v1/community/blocks/\(userID)", method: "PUT") }
    func fetchPolls(limit: Int) async throws -> [CommunityPoll] { try await get("/v1/community/polls", query(["kind":"feed","limit":String(limit)])) }
    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll] { try await get("/v1/community/polls", query(["kind":"authored","limit":String(limit)])) }
    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll] { try await get("/v1/community/polls", query(["kind":"voted","limit":String(limit)])) }
    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        guard input.validationError == nil else { throw CommunityServiceError.invalidPoll }
        struct Input: Encodable { let id = UUID(); let question: String; let options: [String]; let closes_at: String?; let detail: String? }
        return try await request("/v1/community/polls", body: Input(question: input.question, options: input.options, closes_at: input.closesAt, detail: input.normalizedDetail))
    }
    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll { try await request("/v1/community/polls/\(pollID)/vote", method: "PUT", body: ["option_id":optionID.uuidString]) }
    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll { try await request("/v1/community/polls/\(pollID)/deletion-request", body: ["reason":reason]) }
    func deleteOwnPoll(pollID: UUID) async throws { _ = try await requestPollDeletion(pollID: pollID, reason: nil) }
    func fetchActiveBanner(campusID: String) async throws -> CommunityBanner? { try await get("/v1/community/banner") }
    func feedEvents(campusID: String) async -> AsyncThrowingStream<Void, Error> { await events("feed") }
    func notificationEvents(profileID: UUID) async -> AsyncThrowingStream<Void, Error> { await events("notifications") }
    private func events(_ scope: String) async -> AsyncThrowingStream<Void, Error> {
        do { try await ensureAnonymousSession(); return try client().changeEvents(scope: scope) } catch { return AsyncThrowingStream { $0.finish(throwing: error) } }
    }
}
