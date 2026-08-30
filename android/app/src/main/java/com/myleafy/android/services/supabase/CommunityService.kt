package com.myleafy.android.services.supabase

import com.myleafy.android.shared.model.BootstrapResponse
import com.myleafy.android.shared.model.CommentDto
import com.myleafy.android.shared.model.CommentThreadPageDto
import com.myleafy.android.shared.model.CommunityBlockDto
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.FeedResponse
import com.myleafy.android.shared.model.NotificationDto
import com.myleafy.android.shared.model.PostDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.postgrest.query.Order
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant

/** 社区服务：匿名 Auth、身份引导（bootstrap）、Feed。 */
class CommunityService(private val client: SupabaseClient) {

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    /** 确保存在匿名 Supabase 会话（对应 iOS `ensureAnonymousSession`）。 */
    suspend fun ensureAnonymousSession() {
        if (client.auth.currentSessionOrNull() != null) return
        client.auth.signInAnonymously()
    }

    /** 按 (edu_id, campus_id) 引导/继承社区 profile（对应 community-bootstrap-user）。 */
    suspend fun bootstrapCommunityUser(eduId: String, displayName: String, campusId: String): BootstrapResponse {
        ensureAnonymousSession()
        val response = client.functions.invoke(
            "community-bootstrap-user",
            buildJsonObject {
                put("edu_id", eduId)
                put("display_name", displayName)
                put("campus_id", campusId)
            },
        )
        return json.decodeFromString(response.bodyAsText())
    }

    /** 只更新允许用户编辑的资料字段；身份、校园和准入字段始终由服务端维护。 */
    suspend fun updateProfile(
        profileId: String,
        nickname: String,
        bio: String?,
        major: String?,
        grade: String?,
    ): com.myleafy.android.shared.model.ProfileDto {
        ensureAnonymousSession()
        val normalizedNickname = nickname.trim()
        require(normalizedNickname.isNotEmpty()) { "昵称不能为空" }
        val now = Instant.now().toString()
        return client.postgrest["profiles"].update(
            buildJsonObject {
                put("nickname", normalizedNickname)
                put("bio", bio.normalizedOrNull())
                put("major", major.normalizedOrNull())
                put("grade", grade.normalizedOrNull())
                put("profile_edited_at", now)
                put("is_profile_complete", true)
                put("updated_at", now)
            },
        ) {
            filter { eq("id", profileId) }
            select()
            single()
        }.decodeAs()
    }

    suspend fun signOut() {
        if (client.auth.currentSessionOrNull() != null) client.auth.signOut()
    }

    /** 拉取社区 Feed（community-feed Edge Function，GET）。 */
    suspend fun fetchFeed(query: FeedQuery): List<PostDto> {
        ensureAnonymousSession()
        val response = client.functions.invoke("community-feed") {
            this.method = HttpMethod.Get
            url.parameters.append("limit", query.limit.toString())
            url.parameters.append("campus_id", query.campus_id)
            query.mode?.let { url.parameters.append("mode", it) }
            query.days?.let { url.parameters.append("days", it.toString()) }
            query.category?.let { url.parameters.append("category", it) }
            query.search?.let { url.parameters.append("search", it) }
        }
        val body = response.bodyAsText()
        val root = json.parseToJsonElement(body) as? JsonObject
            ?: throw IllegalStateException("社区 Feed 返回了非对象响应")
        if (root["posts"] !is JsonArray) {
            throw IllegalStateException("社区 Feed 响应缺少 posts，字段：${root.keys.sorted().joinToString()}")
        }
        return json.decodeFromString<FeedResponse>(body).posts
    }

    /** 按 id 获取完整帖子摘要（含作者与当前用户点赞状态）。 */
    suspend fun fetchPost(postId: String): PostDto? {
        ensureAnonymousSession()
        return client.postgrest.rpc(
            "community_post_summary_v1",
            buildJsonObject { put("p_post_id", postId) },
        ).decodeAs<PostDto?>()
    }

    /** 拉取评论线程（list_community_comment_threads_v1）。 */
    suspend fun fetchCommentThreads(postId: String, limit: Int = 20): CommentThreadPageDto {
        ensureAnonymousSession()
        return client.postgrest.rpc(
            "list_community_comment_threads_v1",
            buildJsonObject {
                put("p_post_id", postId)
                put("p_after_created_at", JsonNull)
                put("p_after_id", JsonNull)
                put("p_limit", limit)
            },
        ).decodeAs()
    }

    /** 点赞/取消点赞（toggle_post_like_v1，返回更新后的帖子）。 */
    suspend fun togglePostLike(postId: String): PostDto {
        ensureAnonymousSession()
        return client.postgrest.rpc(
            "toggle_post_like_v1",
            buildJsonObject { put("p_post_id", postId) },
        ).decodeAs()
    }

    /** 收藏/取消收藏（服务端返回与详情一致的更新后摘要）。 */
    suspend fun togglePostFavorite(postId: String): PostDto {
        ensureAnonymousSession()
        return client.postgrest.rpc(
            "toggle_post_favorite_v1",
            buildJsonObject { put("p_post_id", postId) },
        ).decodeAs()
    }

    /** RLS 只允许读取当前 profile 的通知；屏蔽关系用于过滤历史通知。 */
    suspend fun fetchNotifications(profileId: String, limit: Int = 50): List<NotificationDto> {
        ensureAnonymousSession()
        val blockedIds = client.postgrest["community_blocks"]
            .select {
                filter { eq("blocker_id", profileId) }
            }
            .decodeList<CommunityBlockDto>()
            .mapTo(mutableSetOf()) { it.blocked_id }
        return client.postgrest["community_notifications"]
            .select {
                filter { eq("recipient_id", profileId) }
                order("created_at", Order.DESCENDING)
                limit(limit.toLong())
            }
            .decodeList<NotificationDto>()
            .filter { it.dismissed_at == null && (it.actor_id == null || it.actor_id !in blockedIds) }
    }

    suspend fun markNotificationRead(notificationId: String) {
        ensureAnonymousSession()
        client.postgrest["community_notifications"].update({ set("is_read", true) }) {
            filter { eq("id", notificationId) }
        }
    }

    suspend fun markAllNotificationsRead(profileId: String) {
        ensureAnonymousSession()
        client.postgrest["community_notifications"].update({ set("is_read", true) }) {
            filter {
                eq("recipient_id", profileId)
                eq("is_read", false)
                exact("dismissed_at", null)
            }
        }
    }

    suspend fun deletePost(postId: String) {
        ensureAnonymousSession()
        client.postgrest.rpc(
            "soft_delete_own_post",
            buildJsonObject { put("target_post_id", postId) },
        )
    }

    suspend fun deleteComment(commentId: String) {
        ensureAnonymousSession()
        client.postgrest.rpc(
            "soft_delete_own_comment",
            buildJsonObject { put("target_comment_id", commentId) },
        )
    }

    suspend fun reportPost(postId: String, reason: String, detail: String?) {
        reportContent("post", postId = postId, commentId = null, reason = reason, detail = detail)
    }

    suspend fun reportComment(commentId: String, reason: String, detail: String?) {
        reportContent("comment", postId = null, commentId = commentId, reason = reason, detail = detail)
    }

    private suspend fun reportContent(
        targetType: String,
        postId: String?,
        commentId: String?,
        reason: String,
        detail: String?,
    ) {
        ensureAnonymousSession()
        client.postgrest.rpc(
            "report_community_content",
            buildJsonObject {
                put("p_target_type", targetType)
                if (postId != null) put("p_post_id", postId) else put("p_post_id", JsonNull)
                if (commentId != null) put("p_comment_id", commentId) else put("p_comment_id", JsonNull)
                put("p_reported_user_id", JsonNull)
                put("p_reason", reason)
                if (detail != null) put("p_detail", detail) else put("p_detail", JsonNull)
            },
        )
    }

    suspend fun blockUser(userId: String, reason: String?) {
        ensureAnonymousSession()
        client.postgrest.rpc(
            "block_community_user",
            buildJsonObject {
                put("p_blocked_id", userId)
                if (reason != null) put("p_reason", reason) else put("p_reason", JsonNull)
            },
        )
    }

    /** 发帖（create_community_post_v4，p_id 为客户端幂等 UUID，暂不支持图片/附件）。 */
    suspend fun createPost(
        postId: String,
        requestId: String,
        title: String,
        body: String,
        category: String?,
        isAnonymous: Boolean,
    ): PostDto {
        ensureAnonymousSession()
        return client.postgrest.rpc(
            "create_community_post_v4",
            buildJsonObject {
                put("p_id", postId)
                put("p_request_id", requestId)
                put("p_title", title)
                put("p_body", body)
                if (category != null) put("p_category", category) else put("p_category", JsonNull)
                put("p_is_anonymous", isAnonymous)
                put("p_image_count", 0)
                put("p_attachment_count", 0)
            },
        ).decodeAs()
    }

    /** 评论（create_community_comment_v2，p_id 为客户端幂等 UUID；评论最多两层）。 */
    suspend fun createComment(
        commentId: String,
        requestId: String,
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
        isAnonymous: Boolean = false,
    ): CommentDto {
        ensureAnonymousSession()
        return client.postgrest.rpc(
            "create_community_comment_v2",
            buildJsonObject {
                put("p_id", commentId)
                put("p_request_id", requestId)
                put("p_post_id", postId)
                put("p_body", body)
                if (parentCommentId != null) {
                    put("p_parent_comment_id", parentCommentId)
                } else {
                    put("p_parent_comment_id", JsonNull)
                }
                if (replyToCommentId != null) {
                    put("p_reply_to_comment_id", replyToCommentId)
                } else {
                    put("p_reply_to_comment_id", JsonNull)
                }
                put("p_is_anonymous", isAnonymous)
            },
        ).decodeAs()
    }

    private fun String?.normalizedOrNull(): kotlinx.serialization.json.JsonElement =
        this?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { kotlinx.serialization.json.JsonPrimitive(it) }
            ?: JsonNull
}
