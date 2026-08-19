package com.myleafy.android.shared.model

import kotlinx.serialization.Serializable

/**
 * 社区 DTO（Supabase 表，snake_case 字段名与线格式一致，跨平台契约）。
 * 权威来源为 Supabase；Android 用 supabase-kt（kotlinx-serialization）对接。
 */

/** 社区准入状态（profiles.community_access_status）。 */
enum class CommunityAccessStatus { GENERAL, PENDING, APPROVED, REJECTED }

/** 社区资料（profiles）。 */
@Serializable
data class ProfileDto(
    val id: String,
    val edu_id: String,
    val campus_id: String,
    val nickname: String,
    val display_name: String? = null,
    val avatar_url: String? = null,
    val bio: String? = null,
    val major: String? = null,
    val grade: String? = null,
    val bound_email: String? = null,
    val is_profile_complete: Boolean = false,
    val community_access_status: String? = null,
    val community_school_name: String? = null,
    val community_rejection_reason: String? = null,
    val created_at: String = "",
    val updated_at: String = "",
)

/** 帖子（posts）。 */
@Serializable
data class PostDto(
    val id: String,
    val author_id: String,
    val title: String,
    val body: String,
    val category: String? = null,
    val is_anonymous: Boolean = false,
    val comment_count: Int = 0,
    val like_count: Int = 0,
    val status: String = "published",
    val created_at: String = "",
    val updated_at: String = "",
    val viewer_has_liked: Boolean = false,
    val viewer_has_favorited: Boolean = false,
    val author: ProfileDto? = null,
)

/** 评论（comments，最多两层）。 */
@Serializable
data class CommentDto(
    val id: String,
    val post_id: String,
    val author_id: String,
    val body: String,
    val is_anonymous: Boolean = false,
    val status: String = "published",
    val created_at: String = "",
    val updated_at: String = "",
    val parent_comment_id: String? = null,
    val reply_to_comment_id: String? = null,
    val reply_to_author_id: String? = null,
    val like_count: Int = 0,
    val viewer_has_liked: Boolean = false,
    val author: ProfileDto? = null,
    val reply_to_author: ProfileDto? = null,
)

/** 站内通知（community_notifications）。 */
@Serializable
data class NotificationDto(
    val id: String,
    val recipient_id: String,
    val actor_id: String? = null,
    val post_id: String? = null,
    val comment_id: String? = null,
    val type: String = "",
    val title: String = "",
    val body: String? = null,
    val is_read: Boolean = false,
    val created_at: String = "",
    val actor: ProfileDto? = null,
)

/** Feed 查询契约（community-feed Edge Function 参数）。 */
data class FeedQuery(
    val limit: Int = 20,
    val campus_id: String,
    val mode: String? = null,      // "hot" 时需带 days
    val days: Int? = null,
    val category: String? = null,
    val search: String? = null,
)

/** community-feed 响应：{ generated_at, posts }。 */
@Serializable
data class FeedResponse(
    val generated_at: String? = null,
    val posts: List<PostDto> = emptyList(),
)

/** community-bootstrap-user 响应：{ profile, is_new_user, is_profile_complete }。 */
@Serializable
data class BootstrapResponse(
    val profile: ProfileDto,
    val is_new_user: Boolean = false,
    val is_profile_complete: Boolean = false,
)
