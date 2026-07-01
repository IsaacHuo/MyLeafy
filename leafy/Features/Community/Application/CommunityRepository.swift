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

nonisolated protocol CommunityPostDetailRepository: CommunitySessionRepository {
    func fetchPost(postID: UUID) async throws -> CommunityPost?
    func fetchComments(postID: UUID) async throws -> [CommunityComment]
    func createComment(postID: UUID, body: String) async throws -> CommunityComment
    func togglePostLike(postID: UUID) async throws -> CommunityPost
    func togglePostFavorite(postID: UUID) async throws -> CommunityPost
    func reportPost(postID: UUID, reason: String) async throws
    func reportComment(commentID: UUID, reason: String) async throws
    func blockUser(userID: UUID, reason: String?) async throws
    func deletePost(postID: UUID) async throws
    func deleteComment(commentID: UUID) async throws
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
}

nonisolated protocol CommunityRepository:
    CommunityFeedRepository,
    CommunityPostDetailRepository,
    CommunityPollRepository,
    CommunityCatalogRatingRepository,
    CommunityNotificationRepository {
    func createPost(input: CreatePostInput, images: [CommunityImageUpload]) async throws -> CommunityPost
    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll]
    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll]
}

extension CommunityRepository {
    func fetchPosts() async throws -> [CommunityPost] {
        try await fetchPosts(query: .default)
    }
}

struct LiveCommunityRepository: CommunityRepository {
    private let service: CommunityService

    nonisolated init(service: CommunityService = .shared) {
        self.service = service
    }

    func ensureAnonymousSession() async throws {
        try await service.ensureAnonymousSession()
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

    func createComment(postID: UUID, body: String) async throws -> CommunityComment {
        try await service.createComment(postID: postID, body: body)
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

    func createPost(input: CreatePostInput, images: [CommunityImageUpload]) async throws -> CommunityPost {
        try await service.createPost(input: input, images: images)
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
}
