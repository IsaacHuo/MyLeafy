package com.myleafy.android.services.supabase

import com.myleafy.android.shared.model.BootstrapResponse
import com.myleafy.android.shared.model.CommentDto
import com.myleafy.android.shared.model.CommentThreadPageDto
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.FeedResponse
import com.myleafy.android.shared.model.PostDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpMethod
import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

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

    /** 拉取社区 Feed（community-feed Edge Function，GET）。 */
    suspend fun fetchFeed(query: FeedQuery): List<PostDto> {
        ensureAnonymousSession()
        val path = buildString {
            append("community-feed")
            append("?limit=").append(query.limit)
            append("&campus_id=").append(query.campus_id)
            query.mode?.let { append("&mode=").append(it) }
            query.days?.let { append("&days=").append(it) }
            query.category?.let { append("&category=").append(it) }
            query.search?.let { append("&search=").append(it) }
        }
        val response = client.functions.invoke(path) {
            this.method = HttpMethod.Get
        }
        return json.decodeFromString<FeedResponse>(response.bodyAsText()).posts
    }

    /** 按 id 获取帖子（posts 表，RLS 限定同校园已发布）。 */
    suspend fun fetchPost(postId: String): PostDto? {
        ensureAnonymousSession()
        return client.postgrest.from("posts")
            .select {
                filter { eq("id", postId) }
            }
            .decodeSingleOrNull()
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

    /** 发帖（create_community_post_v4，p_id 为客户端幂等 UUID，暂不支持图片/附件）。 */
    suspend fun createPost(title: String, body: String, category: String?, isAnonymous: Boolean): PostDto {
        ensureAnonymousSession()
        return client.postgrest.rpc(
            "create_community_post_v4",
            buildJsonObject {
                put("p_id", UUID.randomUUID().toString())
                put("p_title", title)
                put("p_body", body)
                if (category != null) put("p_category", category)
                put("p_is_anonymous", isAnonymous)
                put("p_image_count", 0)
                put("p_attachment_count", 0)
            },
        ).decodeAs()
    }

    /** 评论（create_community_comment_v2，p_id 为客户端幂等 UUID；评论最多两层）。 */
    suspend fun createComment(
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
                put("p_id", UUID.randomUUID().toString())
                put("p_post_id", postId)
                put("p_body", body)
                if (parentCommentId != null) put("p_parent_comment_id", parentCommentId)
                if (replyToCommentId != null) put("p_reply_to_comment_id", replyToCommentId)
                put("p_is_anonymous", isAnonymous)
            },
        ).decodeAs()
    }
}
