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
