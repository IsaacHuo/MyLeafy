package com.myleafy.android.services.cloudflare

import com.myleafy.android.shared.model.*
import kotlinx.serialization.json.*

class CommunityService(private val client: BackendClient) {
    val hasSession: Boolean get() = client.hasSession
    fun events(scope: String) = client.events(scope)
    suspend fun hasAcceptedTerms(): Boolean = client.request<JsonObject>("/v1/community/terms").getValue("accepted").jsonPrimitive.boolean
    suspend fun acceptTerms() { client.requestText("/v1/community/terms", "POST") }

    val catalogRatings by lazy { CatalogRatingService(client) }
    val timetableSharing by lazy { TimetableSharingService(client) }

    suspend fun bootstrapCommunityUser(eduId: String, displayName: String, campusId: String): BootstrapResponse {
        client.establishSession()
        return client.request("/v1/profile/bootstrap", "POST", buildJsonObject {
            put("edu_id", eduId); put("display_name", displayName); put("campus_id", campusId)
        })
    }

    suspend fun updateProfile(profileId: String, nickname: String, bio: String?, major: String?, grade: String?): ProfileDto {
        require(nickname.isNotBlank()) { "昵称不能为空" }
        return client.request("/v1/profile", "PATCH", buildJsonObject {
            put("nickname", nickname.trim()); put("bio", bio.normalized()); put("major", major.normalized()); put("grade", grade.normalized())
        })
    }

    suspend fun signOut() = client.signOut()
    fun closeLocally() = client.close()

    suspend fun fetchFeed(query: FeedQuery): List<PostDto> = fetchFeedPage(query).posts
    suspend fun fetchFeedPage(query: FeedQuery): FeedResponse = client.request<FeedResponse>("/v1/community/feed", query = mapOf(
        "limit" to query.limit.toString(), "campus_id" to query.campus_id, "mode" to query.mode,
        "days" to query.days?.toString(), "category" to query.category, "search" to query.search, "cursor" to query.cursor,
    ))

    suspend fun fetchPost(postId: String): PostDto? = try {
        client.request<PostDto>("/v1/community/posts/$postId")
    } catch (failure: BackendError) { if (failure.status == 404) null else throw failure }

    suspend fun fetchCommentThreads(postId: String, limit: Int = 20): CommentThreadPageDto =
        client.request("/v1/community/posts/$postId/comment-threads", query = mapOf("limit" to limit.toString()))
    suspend fun togglePostLike(postId: String): PostDto = client.request("/v1/community/posts/$postId/toggle-like", "POST")
    suspend fun togglePostFavorite(postId: String): PostDto = client.request("/v1/community/posts/$postId/toggle-favorite", "POST")
    suspend fun fetchNotifications(profileId: String, limit: Int = 50): List<NotificationDto> {
        val notifications = client.request<List<NotificationDto>>("/v1/notifications", query = mapOf("limit" to limit.toString()))
        val announcements = client.request<List<JsonObject>>("/v1/announcements", query = mapOf("limit" to "100")).map { row ->
            NotificationDto(id = "announcement:${row.getValue("id").jsonPrimitive.content}", recipient_id = profileId,
                type = "announcement", title = row.getValue("title").jsonPrimitive.content, body = row.getValue("body").jsonPrimitive.content,
                is_read = row["read_at"]?.let { it != JsonNull } == true,
                created_at = row["published_at"]?.jsonPrimitive?.contentOrNull ?: row["created_at"]?.jsonPrimitive?.content.orEmpty())
        }
        return (notifications + announcements).sortedByDescending { it.created_at }
    }
    suspend fun unreadNotificationCount(): Int = client.request<JsonObject>("/v1/notifications/unread-count").getValue("count").jsonPrimitive.int
    suspend fun markNotificationRead(notificationId: String) {
        val path = if (notificationId.startsWith("announcement:")) "/v1/announcements/${notificationId.removePrefix("announcement:")}/read" else "/v1/notifications/$notificationId/read"
        client.requestText(path, "POST")
    }
    suspend fun markAllNotificationsRead(profileId: String) { client.requestText("/v1/notifications/read-all", "POST") }
    suspend fun deletePost(postId: String) { client.requestText("/v1/community/posts/$postId", "DELETE") }
    suspend fun deleteComment(commentId: String) { client.requestText("/v1/community/comments/$commentId", "DELETE") }
    suspend fun reportPost(postId: String, reason: String, detail: String?) = report("post", postId, reason, detail)
    suspend fun reportComment(commentId: String, reason: String, detail: String?) = report("comment", commentId, reason, detail)
    private suspend fun report(type: String, id: String, reason: String, detail: String?) {
        client.requestText("/v1/community/reports", "POST", buildJsonObject {
            put("target_type", type); put("${type}_id", id); put("reason", reason); put("detail", detail.normalized())
        })
    }
    suspend fun blockUser(userId: String, reason: String?) {
        client.requestText("/v1/community/blocks/$userId", "PUT", buildJsonObject { put("reason", reason.normalized()) })
    }

    suspend fun createPost(postId: String, requestId: String, title: String, body: String, category: String?,
        isAnonymous: Boolean, imageCount: Int = 0, attachmentCount: Int = 0): PostDto =
        client.request("/v1/community/posts", "POST", buildJsonObject {
            put("id", postId); put("request_id", requestId); put("title", title); put("body", body)
            put("category", category.normalized()); put("is_anonymous", isAnonymous)
            put("image_count", imageCount); put("attachment_count", attachmentCount)
        })

    suspend fun uploadPostImage(profileId: String, postId: String, imageId: String, fullBytes: ByteArray,
        thumbnailBytes: ByteArray, sortOrder: Int) {
        // An attachment may have committed even when the response was lost.
        val post = fetchPost(postId) ?: error("帖子不存在，请重新发布。")
        if (post.images.any { it.id.equals(imageId, ignoreCase = true) }) return
        check(post.status == "pending_review") { "帖子状态已改变，请返回查看。" }
        val full = client.upload(postId, imageId, "full", fullBytes)
        val thumb = client.upload(postId, imageId, "thumb", thumbnailBytes)
        val receipt = client.request<JsonObject>("/v1/files/validate-images", "POST", buildJsonObject {
            put("post_id", postId); put("full_path", full); put("thumbnail_path", thumb)
        }).getValue("receipt_id")
        client.requestText("/v1/files/attach-image", "POST", buildJsonObject {
            put("receipt_id", receipt); put("id", imageId); put("sort_order", sortOrder)
        })
    }

    suspend fun createComment(commentId: String, requestId: String, postId: String, body: String,
        parentCommentId: String?, replyToCommentId: String?, isAnonymous: Boolean = false): CommentDto =
        client.request("/v1/community/comments", "POST", buildJsonObject {
            put("id", commentId); put("request_id", requestId); put("post_id", postId); put("body", body)
            put("parent_comment_id", parentCommentId.normalized()); put("reply_to_comment_id", replyToCommentId.normalized())
            put("is_anonymous", isAnonymous)
        })

    private fun String?.normalized(): JsonElement = this?.trim()?.takeIf(String::isNotEmpty)?.let(::JsonPrimitive) ?: JsonNull
}
