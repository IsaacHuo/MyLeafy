package com.myleafy.android.services

import com.myleafy.android.services.supabase.*

import com.myleafy.android.shared.model.*

/** Product-facing contracts shared by the explicitly selected backend. */
interface CommunityService {
    val catalogRatings: CatalogRatingService
    val timetableSharing: TimetableSharingService
    suspend fun ensureAnonymousSession()
    suspend fun bootstrapCommunityUser(eduId: String, displayName: String, campusId: String): BootstrapResponse
    suspend fun updateProfile(profileId: String, nickname: String, bio: String?, major: String?, grade: String?): ProfileDto
    suspend fun signOut()
    suspend fun fetchFeed(query: FeedQuery): List<PostDto>
    suspend fun fetchPost(postId: String): PostDto?
    suspend fun fetchCommentThreads(postId: String, limit: Int = 20): CommentThreadPageDto
    suspend fun togglePostLike(postId: String): PostDto
    suspend fun togglePostFavorite(postId: String): PostDto
    suspend fun fetchNotifications(profileId: String, limit: Int = 50): List<NotificationDto>
    suspend fun markNotificationRead(notificationId: String)
    suspend fun markAllNotificationsRead(profileId: String)
    suspend fun deletePost(postId: String)
    suspend fun deleteComment(commentId: String)
    suspend fun reportPost(postId: String, reason: String, detail: String?)
    suspend fun reportComment(commentId: String, reason: String, detail: String?)
    suspend fun blockUser(userId: String, reason: String?)
    suspend fun createPost(postId: String, requestId: String, title: String, body: String, category: String?, isAnonymous: Boolean): PostDto
    suspend fun createComment(commentId: String, requestId: String, postId: String, body: String, parentCommentId: String?, replyToCommentId: String?, isAnonymous: Boolean = false): CommentDto
}

interface CatalogRatingService {
    suspend fun fetchCatalog(kind: RatingCatalogKind, search: String, filterValue: String?, offset: Int, limit: Int): List<RatingCatalogItemDto>
    suspend fun fetchMyRatings(kind: RatingCatalogKind, profileId: String): List<UserCatalogRatingDto>
    suspend fun submitRating(kind: RatingCatalogKind, itemId: Long, profileId: String, stars: Int)
    suspend fun submitSuggestion(insert: CatalogSuggestionInsert)
}

interface TimetableSharingService {
    suspend fun isBackendAvailable(): Boolean
    suspend fun publish(campusId: String, ownerId: String, semesterId: String, courses: List<SharedTimetableCourseDto>): SharedTimetableSnapshotDto
    suspend fun mySnapshot(campusId: String, ownerId: String, semesterId: String): SharedTimetableSnapshotDto?
    suspend fun viewableSnapshots(campusId: String, ownerId: String, semesterId: String): List<SharedTimetableSnapshotDto>
    suspend fun members(campusId: String, ownerId: String): List<TimetableShareMemberDto>
    suspend fun invites(campusId: String, ownerId: String): List<TimetableInviteDto>
    suspend fun createInvite(): TimetableInviteDto
    suspend fun accept(code: String): SharedTimetableSnapshotDto
    suspend fun revoke(ownerId: String, viewerId: String)
    suspend fun stopSharing()
    suspend fun leave(ownerId: String)

    companion object {
        fun normalizeCode(code: String): String = code.uppercase().filter { it in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" }
    }
}
