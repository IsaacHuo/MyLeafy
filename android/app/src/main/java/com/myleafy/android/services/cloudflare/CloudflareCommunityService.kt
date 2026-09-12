package com.myleafy.android.services.cloudflare

import com.myleafy.android.services.CatalogRatingService
import com.myleafy.android.services.CommunityService
import com.myleafy.android.services.TimetableSharingService
import com.myleafy.android.shared.model.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*

class CloudflareCommunityService(private val client: MyLeafyBackendClient) : CommunityService {
    override val catalogRatings: CatalogRatingService by lazy { CloudflareCatalogRatingService(client) }
    override val timetableSharing: TimetableSharingService by lazy { CloudflareTimetableSharingService(client) }
    private val reactions = Mutex()

    override suspend fun ensureAnonymousSession() = client.ensureAnonymousSession()

    override suspend fun bootstrapCommunityUser(eduId: String, displayName: String, campusId: String): BootstrapResponse {
        ensureAnonymousSession()
        return client.decodeRequest("/v1/profile/bootstrap", "POST", buildJsonObject {
            put("edu_id", eduId); put("display_name", displayName); put("campus_id", campusId)
        })
    }

    override suspend fun updateProfile(profileId: String, nickname: String, bio: String?, major: String?, grade: String?): ProfileDto {
        require(nickname.trim().isNotEmpty()) { "昵称不能为空" }
        return client.decodeRequest("/v1/profile", "PATCH", buildJsonObject {
            put("nickname", nickname.trim()); put("bio", bio.normalized()); put("major", major.normalized()); put("grade", grade.normalized())
        })
    }

    override suspend fun signOut() = client.signOut()

    override suspend fun fetchFeed(query: FeedQuery): List<PostDto> {
        val parameters = buildMap {
            put("limit", query.limit.toString())
            query.mode?.let { put("mode", it) }; query.days?.let { put("days", it.toString()) }
            query.category?.let { put("category", it) }; query.search?.let { put("search", it) }
        }
        val root = client.request("/v1/community/feed", query = parameters).jsonObject
        check(root["posts"] is JsonArray) { "社区 Feed 响应缺少 posts" }
        return backendJson.decodeFromJsonElement<FeedResponse>(root).posts
    }

    override suspend fun fetchPost(postId: String): PostDto? = try {
        client.decodeRequest("/v1/community/posts/${apiID(postId)}")
    } catch (error: BackendException) {
        if (error.status == 404 && error.code == "not_found") null else throw error
    }

    override suspend fun fetchCommentThreads(postId: String, limit: Int): CommentThreadPageDto =
        client.decodeRequest("/v1/community/posts/${apiID(postId)}/comment-threads", query = mapOf("limit" to limit.toString()))

    override suspend fun togglePostLike(postId: String): PostDto = reactions.withLock {
        val post = requireNotNull(fetchPost(postId)) { "帖子不存在或不可访问" }
        val result = client.request("/v1/community/posts/${apiID(postId)}/like", if (post.viewer_has_liked) "DELETE" else "PUT").jsonObject
        post.copy(like_count = result.getValue("like_count").jsonPrimitive.int,
            viewer_has_liked = result.getValue("viewer_has_liked").jsonPrimitive.boolean)
    }

    override suspend fun togglePostFavorite(postId: String): PostDto = reactions.withLock {
        val post = requireNotNull(fetchPost(postId)) { "帖子不存在或不可访问" }
        val result = client.request("/v1/community/posts/${apiID(postId)}/favorite", if (post.viewer_has_favorited) "DELETE" else "PUT").jsonObject
        post.copy(like_count = result.getValue("like_count").jsonPrimitive.int,
            viewer_has_favorited = result.getValue("viewer_has_favorited").jsonPrimitive.boolean)
    }

    override suspend fun fetchNotifications(profileId: String, limit: Int): List<NotificationDto> =
        client.decodeRequest<List<NotificationDto>>("/v1/notifications").take(limit.coerceIn(1, 100))

    override suspend fun markNotificationRead(notificationId: String) { client.request("/v1/notifications/${apiID(notificationId)}/read", "POST") }
    override suspend fun markAllNotificationsRead(profileId: String) { client.request("/v1/notifications/read-all", "POST") }
    override suspend fun deletePost(postId: String) { client.request("/v1/community/posts/${apiID(postId)}", "DELETE") }
    override suspend fun deleteComment(commentId: String) { client.request("/v1/community/comments/${apiID(commentId)}", "DELETE") }
    override suspend fun reportPost(postId: String, reason: String, detail: String?) = report("post", postId, reason, detail)
    override suspend fun reportComment(commentId: String, reason: String, detail: String?) = report("comment", commentId, reason, detail)
    private suspend fun report(type: String, id: String, reason: String, detail: String?) {
        client.request("/v1/community/reports", "POST", buildJsonObject {
            put("target_type", type); put("target_id", apiID(id)); put("reason", reason); put("detail", detail)
        })
    }
    override suspend fun blockUser(userId: String, reason: String?) {
        client.request("/v1/community/blocks/${apiID(userId)}", "PUT", buildJsonObject { put("reason", reason) })
    }

    override suspend fun createPost(postId: String, requestId: String, title: String, body: String, category: String?, isAnonymous: Boolean): PostDto =
        client.decodeRequest("/v1/community/posts", "POST", buildJsonObject {
            put("id", apiID(postId)); put("request_id", apiID(requestId)); put("title", title); put("body", body)
            put("category", category); put("is_anonymous", isAnonymous); put("image_count", 0); put("attachment_count", 0)
        })

    override suspend fun createComment(commentId: String, requestId: String, postId: String, body: String, parentCommentId: String?, replyToCommentId: String?, isAnonymous: Boolean): CommentDto =
        client.decodeRequest("/v1/community/comments", "POST", buildJsonObject {
            put("id", apiID(commentId)); put("request_id", apiID(requestId)); put("post_id", apiID(postId)); put("body", body)
            put("parent_comment_id", parentCommentId?.let(::apiID)); put("reply_to_comment_id", replyToCommentId?.let(::apiID))
            put("is_anonymous", isAnonymous)
        })

    private fun String?.normalized(): String? = this?.trim()?.takeIf(String::isNotEmpty)
}

internal val backendJson = Json { ignoreUnknownKeys = true }
internal fun apiID(value: String): String = java.util.UUID.fromString(value).toString()
internal suspend inline fun <reified T> MyLeafyBackendClient.decodeRequest(
    path: String, method: String = "GET", body: JsonElement? = null, query: Map<String, String> = emptyMap(),
): T = backendJson.decodeFromJsonElement(request(path, method, body, query))
