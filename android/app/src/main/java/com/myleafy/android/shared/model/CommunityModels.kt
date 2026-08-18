package com.myleafy.android.shared.model

/**
 * 社区 DTO（Supabase 表，snake_case 字段名与线格式一致，跨平台契约）。
 * 权威来源为 Supabase；阶段 4 用 supabase-kt 对接，阶段 1.5 仅定义契约。
 */

/** 社区准入状态（profiles.community_access_status）。 */
enum class CommunityAccessStatus { GENERAL, PENDING, APPROVED, REJECTED }

/** 社区资料（profiles）。 */
data class ProfileDto(
    val id: String,
    val edu_id: String,
    val campus_id: String,
    val nickname: String,
    val display_name: String?,
    val avatar_url: String?,
    val bio: String?,
    val major: String?,
    val grade: String?,
    val bound_email: String?,
    val is_profile_complete: Boolean,
    val community_access_status: String?,
    val community_school_name: String?,
    val community_rejection_reason: String?,
    val created_at: String,
    val updated_at: String,
)

/** 帖子（posts）。 */
data class PostDto(
    val id: String,
    val author_id: String,
    val title: String,
    val body: String,
    val category: String?,
    val is_anonymous: Boolean,
    val comment_count: Int,
    val like_count: Int,
    val status: String,
    val created_at: String,
    val updated_at: String,
    val viewer_has_liked: Boolean = false,
    val viewer_has_favorited: Boolean = false,
    val author: ProfileDto? = null,
)

/** 评论（comments，最多两层）。 */
data class CommentDto(
    val id: String,
    val post_id: String,
    val author_id: String,
    val body: String,
    val is_anonymous: Boolean,
    val status: String,
    val created_at: String,
    val updated_at: String,
    val parent_comment_id: String? = null,
    val reply_to_comment_id: String? = null,
    val reply_to_author_id: String? = null,
    val like_count: Int = 0,
    val viewer_has_liked: Boolean = false,
    val author: ProfileDto? = null,
    val reply_to_author: ProfileDto? = null,
)

/** 站内通知（community_notifications）。 */
data class NotificationDto(
    val id: String,
    val recipient_id: String,
    val actor_id: String? = null,
    val post_id: String? = null,
    val comment_id: String? = null,
    val type: String,
    val title: String,
    val body: String? = null,
    val is_read: Boolean,
    val created_at: String,
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
