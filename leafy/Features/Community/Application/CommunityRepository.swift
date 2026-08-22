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

nonisolated struct LiveCommunityFeedChangeStream: CommunityFeedChangeStreaming {
    private let service: CommunityService

    init(service: CommunityService = .shared) {
        self.service = service
    }

    func feedEvents(campusID: String) async -> AsyncThrowingStream<Void, Error> {
        await service.feedEvents(campusID: campusID)
    }
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

struct LiveCommunityRepository: CommunityRepository {
    private let service: CommunityService

    nonisolated init(service: CommunityService = .shared) {
        self.service = service
    }

    func ensureAnonymousSession() async throws {
        try await service.ensureAnonymousSession()
    }

    @MainActor
    func enqueuePostPublication(
        input: CreatePostInput,
        images: [CommunityImageUpload],
        attachments: [CommunityAttachmentUpload]
    ) throws -> UUID {
        try CommunityPublishCoordinator.shared.enqueue(
            input: input,
            images: images,
            attachments: attachments
        )
    }

    func fetchPosts(query: CommunityFeedQuery) async throws -> [CommunityPost] {
        try await service.fetchPosts(query: query)
    }

    func fetchPost(postID: UUID) async throws -> CommunityPost? {
        try await service.fetchPost(postID: postID)
    }

    func fetchComments(postID: UUID) async throws -> [CommunityComment] {
        try await service.fetchComments(postID: postID)
    }

    func fetchCommentThreads(
        postID: UUID,
        cursor: CommunityCommentCursor?,
        limit: Int
    ) async throws -> CommunityCommentPage {
        try await service.fetchCommentThreads(postID: postID, cursor: cursor, limit: limit)
    }

    func createComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID?,
        replyToCommentID: UUID?
    ) async throws -> CommunityComment {
        try await service.createComment(
            postID: postID,
            body: body,
            parentCommentID: parentCommentID,
            replyToCommentID: replyToCommentID
        )
    }

    func createComment(
        postID: UUID,
        body: String,
        parentCommentID: UUID?,
        replyToCommentID: UUID?,
        requestID: UUID
    ) async throws -> CommunityComment {
        try await service.createComment(
            postID: postID,
            body: body,
            parentCommentID: parentCommentID,
            replyToCommentID: replyToCommentID,
            requestID: requestID
        )
    }

    func toggleCommentLike(commentID: UUID) async throws -> CommunityCommentLikeState {
        try await service.toggleCommentLike(commentID: commentID)
    }

    func attachmentDownloadURL(attachmentID: UUID) async throws -> CommunityAttachmentDownload {
        try await service.attachmentDownloadURL(attachmentID: attachmentID)
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        try await service.togglePostLike(postID: postID)
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        try await service.togglePostFavorite(postID: postID)
    }

    func reportPost(postID: UUID, reason: String) async throws {
        try await service.reportPost(postID: postID, reason: reason)
    }

    func reportComment(commentID: UUID, reason: String) async throws {
        try await service.reportComment(commentID: commentID, reason: reason)
    }

    func blockUser(userID: UUID, reason: String?) async throws {
        try await service.blockUser(userID: userID, reason: reason)
    }

    func deletePost(postID: UUID) async throws {
        try await service.deletePost(postID: postID)
    }

    func deleteComment(commentID: UUID) async throws {
        try await service.deleteComment(commentID: commentID)
    }

    func hasAcceptedCurrentTerms() async throws -> Bool {
        try await service.hasAcceptedCurrentTerms()
    }

    func fetchPolls(limit: Int) async throws -> [CommunityPoll] {
        try await service.fetchPolls(limit: limit)
    }

    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll] {
        try await service.fetchMyAuthoredPolls(limit: limit)
    }

    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll] {
        try await service.fetchMyVotedPolls(limit: limit)
    }

    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        try await service.createPoll(input: input)
    }

    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll {
        try await service.votePoll(pollID: pollID, optionID: optionID)
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        try await service.requestPollDeletion(pollID: pollID, reason: reason)
    }

    func deleteOwnPoll(pollID: UUID) async throws {
        try await service.deleteOwnPoll(pollID: pollID)
    }

    func fetchTeacherRatingSummaries(search: String, limit: Int, offset: Int) async throws -> [TeacherRatingSummary] {
        try await service.fetchTeacherRatingSummaries(search: search, limit: limit, offset: offset)
    }

    func fetchCourseRatingSummaries(search: String, category: String?, limit: Int, offset: Int) async throws -> [CourseRatingSummary] {
        try await service.fetchCourseRatingSummaries(search: search, category: category, limit: limit, offset: offset)
    }

    func fetchDishRatingSummaries(search: String, canteen: String?, location: String?, limit: Int, offset: Int) async throws -> [DishRatingSummary] {
        try await service.fetchDishRatingSummaries(
            search: search,
            canteen: canteen,
            location: location,
            limit: limit,
            offset: offset
        )
    }

    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {
        try await service.submitCatalogSuggestion(input: input)
    }

    func fetchUnreadNotificationCount() async throws -> Int {
        try await service.fetchUnreadNotificationCount()
    }

    func notificationEvents(profileID: UUID) async -> AsyncThrowingStream<Void, Error> {
        await service.notificationEvents(profileID: profileID)
    }

    func fetchNotificationFeed(limit: Int) async throws -> [NotificationFeedItem] {
        try await service.fetchNotificationFeed(limit: limit)
    }

    func fetchNotificationSettings() async throws -> CommunityNotificationSettings {
        try await service.fetchNotificationSettings()
    }

    func updateNotificationSettings(mutedAll: Bool) async throws -> CommunityNotificationSettings {
        try await service.updateNotificationSettings(mutedAll: mutedAll)
    }

    func markNotificationFeedRead(announcementLimit: Int) async throws {
        try await service.markNotificationFeedRead(announcementLimit: announcementLimit)
    }

    func dismissNotificationFeedItem(_ item: NotificationFeedItem) async throws {
        try await service.dismissNotificationFeedItem(item)
    }

    func markNotificationRead(notificationID: UUID) async throws {
        try await service.markNotificationRead(notificationID: notificationID)
    }

    func markSiteAnnouncementRead(announcementID: UUID) async throws {
        try await service.markSiteAnnouncementRead(announcementID: announcementID)
    }

    func fetchLinkedPost(postID: UUID) async throws -> CommunityPost? {
        try await service.fetchPost(postID: postID)
    }
}
