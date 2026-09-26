import Foundation

nonisolated protocol CommunitySessionRepository: CommunityTermsChecking {
    func ensureAnonymousSession() async throws
    func hasAcceptedCurrentTerms() async throws -> Bool
}

nonisolated protocol CommunityFeedRepository: CommunitySessionRepository {
    func fetchPosts(query: CommunityFeedQuery) async throws -> [CommunityPost]
    func fetchPolls(limit: Int) async throws -> [CommunityPoll]
    func togglePostLike(postID: UUID) async throws -> CommunityPost
    func togglePostFavorite(postID: UUID) async throws -> CommunityPost
    func reportPost(postID: UUID, reason: String) async throws
    func blockUser(userID: UUID, reason: String?) async throws
    func deletePost(postID: UUID) async throws
    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll
}

nonisolated protocol CommunityFeedChangeStreaming: Sendable {
    func feedEvents(campusID: String) async -> AsyncThrowingStream<Void, Error>
}



nonisolated protocol CommunityPostDetailRepository: CommunitySessionRepository {
    func fetchPost(postID: UUID) async throws -> CommunityPost?
    func fetchComments(postID: UUID) async throws -> [CommunityComment]
    func fetchCommentThreads(
        postID: UUID,
        cursor: CommunityCommentCursor?,
        limit: Int
    ) async throws -> CommunityCommentPage
    func createComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID?,
        replyToCommentID: UUID?
    ) async throws -> CommunityComment
    func createComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID?,
        replyToCommentID: UUID?,
        requestID: UUID
    ) async throws -> CommunityComment
    func toggleCommentLike(commentID: UUID) async throws -> CommunityCommentLikeState
    func attachmentDownloadURL(attachmentID: UUID) async throws -> CommunityAttachmentDownload
    func togglePostLike(postID: UUID) async throws -> CommunityPost
    func togglePostFavorite(postID: UUID) async throws -> CommunityPost
    func reportPost(postID: UUID, reason: String) async throws
    func reportComment(commentID: UUID, reason: String) async throws
    func blockUser(userID: UUID, reason: String?) async throws
    func deletePost(postID: UUID) async throws
    func deleteComment(commentID: UUID) async throws
}

extension CommunityPostDetailRepository {
    func createComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID?,
        replyToCommentID: UUID?,
        requestID _: UUID
    ) async throws -> CommunityComment {
        try await createComment(
            postID: postID,
            body: body,
            parentCommentID: parentCommentID,
            replyToCommentID: replyToCommentID
        )
    }
}

nonisolated protocol CommunityPollRepository: CommunitySessionRepository {
    func fetchPolls(limit: Int) async throws -> [CommunityPoll]
    func createPoll(input: CreatePollInput) async throws -> CommunityPoll
    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll
    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll
    func deleteOwnPoll(pollID: UUID) async throws
}

nonisolated protocol CommunityCatalogRatingRepository: CommunitySessionRepository {
    func fetchTeacherRatingSummaries(search: String, limit: Int, offset: Int) async throws -> [TeacherRatingSummary]
    func fetchCourseRatingSummaries(search: String, category: String?, limit: Int, offset: Int) async throws -> [CourseRatingSummary]
    func fetchDishRatingSummaries(search: String, canteen: String?, location: String?, limit: Int, offset: Int) async throws -> [DishRatingSummary]
    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws
}

nonisolated protocol CommunityNotificationRepository: CommunitySessionRepository {
    func fetchUnreadNotificationCount() async throws -> Int
    func notificationEvents(profileID: UUID) async -> AsyncThrowingStream<Void, Error>
    func fetchNotificationFeed(limit: Int) async throws -> [NotificationFeedItem]
    func fetchNotificationSettings() async throws -> CommunityNotificationSettings
    func updateNotificationSettings(mutedAll: Bool) async throws -> CommunityNotificationSettings
    func markNotificationFeedRead(announcementLimit: Int) async throws
    func dismissNotificationFeedItem(_ item: NotificationFeedItem) async throws
    func markNotificationRead(notificationID: UUID) async throws
    func markSiteAnnouncementRead(announcementID: UUID) async throws
    func fetchLinkedPost(postID: UUID) async throws -> CommunityPost?
}

nonisolated protocol CommunityRepository:
    CommunityFeedRepository,
    CommunityPostDetailRepository,
    CommunityPollRepository,
    CommunityCatalogRatingRepository,
    CommunityNotificationRepository {
    @MainActor
    func enqueuePostPublication(
        input: CreatePostInput,
        images: [CommunityImageUpload],
        attachments: [CommunityAttachmentUpload]
    ) throws -> UUID
    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll]
    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll]
}
