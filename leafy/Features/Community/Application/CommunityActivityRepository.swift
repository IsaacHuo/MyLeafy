import Foundation

protocol CommunityActivityRepository: Sendable {
    func hasAcceptedCurrentTerms() async throws -> Bool
    func acceptCurrentTerms() async throws
    func revokeCurrentTerms() async throws
    func submitFeedback(issueType: String, body: String, contact: String?, deviceInfo: [String: String]) async throws
    func fetchProfile(userID: UUID) async throws -> CommunityProfile?
    func fetchProfileStats(profileIDs: [UUID]) async throws -> [CommunityProfileStats]
    func fetchPublicPosts(authoredBy userID: UUID, limit: Int) async throws -> [CommunityPost]
    func fetchPosts(authoredBy userID: UUID, limit: Int) async throws -> [CommunityPost]
    func fetchLikedPosts(by userID: UUID, limit: Int) async throws -> [CommunityPost]
    func fetchFavoritedPosts(by userID: UUID, limit: Int) async throws -> [CommunityPost]
    func fetchMyComments(limit: Int) async throws -> [CommunityComment]
    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll]
    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll]
    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll
    func deletePost(postID: UUID) async throws
    func deleteComment(commentID: UUID) async throws
    func togglePostLike(postID: UUID) async throws -> CommunityPost
    func togglePostFavorite(postID: UUID) async throws -> CommunityPost
    func submitTeacherRating(teacherID: Int64, stars: Int) async throws -> TeacherRatingSummary
    func submitCourseRating(courseID: Int64, stars: Int) async throws -> CourseRatingSummary
    func submitDishRating(dishID: Int64, stars: Int) async throws -> DishRatingSummary
}

extension CommunityActivityRepository {
    func fetchPosts(authoredBy userID: UUID) async throws -> [CommunityPost] {
        try await fetchPosts(authoredBy: userID, limit: 20)
    }

    func fetchLikedPosts(by userID: UUID) async throws -> [CommunityPost] {
        try await fetchLikedPosts(by: userID, limit: 20)
    }

    func fetchFavoritedPosts(by userID: UUID) async throws -> [CommunityPost] {
        try await fetchFavoritedPosts(by: userID, limit: 20)
    }

    func fetchPublicPosts(authoredBy userID: UUID) async throws -> [CommunityPost] {
        try await fetchPublicPosts(authoredBy: userID, limit: 20)
    }

    func fetchMyComments() async throws -> [CommunityComment] {
        try await fetchMyComments(limit: 80)
    }

    func fetchMyAuthoredPolls() async throws -> [CommunityPoll] {
        try await fetchMyAuthoredPolls(limit: 30)
    }

    func fetchMyVotedPolls() async throws -> [CommunityPoll] {
        try await fetchMyVotedPolls(limit: 30)
    }
}

struct LiveCommunityActivityRepository: CommunityActivityRepository {
    private let service: CommunityService

    nonisolated init(service: CommunityService = .shared) {
        self.service = service
    }

    func hasAcceptedCurrentTerms() async throws -> Bool {
        try await service.hasAcceptedCurrentTerms()
    }

    func acceptCurrentTerms() async throws {
        try await service.acceptCurrentTerms()
    }

    func revokeCurrentTerms() async throws {
        try await service.revokeCurrentTerms()
    }

    func submitFeedback(issueType: String, body: String, contact: String?, deviceInfo: [String: String]) async throws {
        try await service.submitFeedback(
            issueType: issueType,
            body: body,
            contact: contact,
            deviceInfo: deviceInfo
        )
    }

    func fetchProfile(userID: UUID) async throws -> CommunityProfile? {
        try await service.fetchPublicProfile(userID: userID)
    }

    func fetchProfileStats(profileIDs: [UUID]) async throws -> [CommunityProfileStats] {
        try await service.fetchProfileStats(profileIDs: profileIDs)
    }

    func fetchPublicPosts(authoredBy userID: UUID, limit: Int) async throws -> [CommunityPost] {
        try await service.fetchPublicPosts(authoredBy: userID, limit: limit)
    }

    func fetchPosts(authoredBy userID: UUID, limit: Int) async throws -> [CommunityPost] {
        try await service.fetchPosts(authoredBy: userID, limit: limit)
    }

    func fetchLikedPosts(by userID: UUID, limit: Int) async throws -> [CommunityPost] {
        try await service.fetchLikedPosts(by: userID, limit: limit)
    }

    func fetchFavoritedPosts(by userID: UUID, limit: Int) async throws -> [CommunityPost] {
        try await service.fetchFavoritedPosts(by: userID, limit: limit)
    }

    func fetchMyComments(limit: Int) async throws -> [CommunityComment] {
        try await service.fetchMyComments(limit: limit)
    }

    func fetchMyAuthoredPolls(limit: Int) async throws -> [CommunityPoll] {
        try await service.fetchMyAuthoredPolls(limit: limit)
    }

    func fetchMyVotedPolls(limit: Int) async throws -> [CommunityPoll] {
        try await service.fetchMyVotedPolls(limit: limit)
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        try await service.requestPollDeletion(pollID: pollID, reason: reason)
    }

    func deletePost(postID: UUID) async throws {
        try await service.deletePost(postID: postID)
    }

    func deleteComment(commentID: UUID) async throws {
        try await service.deleteComment(commentID: commentID)
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        try await service.togglePostLike(postID: postID)
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        try await service.togglePostFavorite(postID: postID)
    }

    func submitTeacherRating(teacherID: Int64, stars: Int) async throws -> TeacherRatingSummary {
        try await service.submitTeacherRating(teacherID: teacherID, stars: stars)
    }

    func submitCourseRating(courseID: Int64, stars: Int) async throws -> CourseRatingSummary {
        try await service.submitCourseRating(courseID: courseID, stars: stars)
    }

    func submitDishRating(dishID: Int64, stars: Int) async throws -> DishRatingSummary {
        try await service.submitDishRating(dishID: dishID, stars: stars)
    }
}
