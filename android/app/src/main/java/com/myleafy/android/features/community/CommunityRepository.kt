package com.myleafy.android.features.community

import com.myleafy.android.services.supabase.CommunityService
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.campus.CampusCapabilities
import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.shared.model.CommentDto
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.CommentThreadPageDto
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.NotificationDto
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.shared.model.ProfileDto
import com.myleafy.android.shared.model.groupCommentThreads
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 社区仓储接口。Supabase 为权威来源（RLS + campus 作用域）。
 */
interface CommunityRepository {
    val isAvailable: Boolean

    /** 占位实现标识：true 时 UI 提示功能未接入，避免误导。 */
    val isPlaceholder: Boolean

    fun feed(query: FeedQuery): Flow<List<PostDto>>

    suspend fun currentProfile(): ProfileDto

    fun cacheCurrentProfile(profile: ProfileDto)

    fun clearProfileCache()

    /** 按 id 获取帖子；不存在返回 null。 */
    suspend fun post(postId: String): PostDto?

    /** 评论线程（根 + 一层回复）。 */
    suspend fun commentThreads(postId: String, limit: Int): List<CommentThread>

    /** 点赞/取消点赞，返回更新后的帖子。 */
    suspend fun togglePostLike(postId: String): PostDto

    suspend fun togglePostFavorite(postId: String): PostDto

    suspend fun notifications(limit: Int = 50): List<NotificationDto>

    suspend fun unreadNotificationCount(limit: Int = 100): Int

    suspend fun markNotificationRead(notificationId: String)

    suspend fun markAllNotificationsRead()

    suspend fun deletePost(postId: String)

    suspend fun deleteComment(commentId: String)

    suspend fun reportPost(postId: String, reason: String, detail: String? = null)

    suspend fun reportComment(commentId: String, reason: String, detail: String? = null)

    suspend fun blockUser(userId: String, reason: String? = null)

    /** 发帖（文本，暂无图片/附件）。 */
    suspend fun createPost(
        postId: String,
        requestId: String,
        title: String,
        body: String,
        category: String?,
        isAnonymous: Boolean,
    ): PostDto

    /** 评论（最多两层：parentCommentId 为根评论 id）。 */
    suspend fun createComment(
        commentId: String,
        requestId: String,
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
    ): CommentDto
}

/** 线上仓储：匿名 Auth + community-feed + postgrest RPC。 */
class LiveCommunityRepository(
    private val serviceProvider: () -> CommunityService?,
    private val sessionState: SchoolSessionState,
    private val activeAppScopeStore: ActiveAppScopeStore,
) : CommunityRepository {

    private val profileMutex = Mutex()
    private var cachedProfile: Pair<String, ProfileDto>? = null

    override val isAvailable: Boolean
        get() = activeAppScopeStore.current.supports(CampusCapabilities.COMMUNITY)
    override val isPlaceholder: Boolean = false

    private fun requireService(): CommunityService =
        serviceProvider() ?: throw IllegalStateException("当前身份不可使用社区，或 Supabase 未配置")

    private suspend fun requireCommunityProfile(requireComplete: Boolean = false): ProfileDto {
        val identity = sessionState.identity
            ?: throw IllegalStateException("请先登录教务，再使用社区互动功能")
        val profile = profileMutex.withLock {
            cachedProfile?.takeIf { it.first == identity.scopeKey }?.second
                ?: requireService().bootstrapCommunityUser(
                    eduId = identity.eduId,
                    displayName = identity.displayName ?: identity.eduId,
                    campusId = identity.campusId.rawValue,
                ).profile.also { cachedProfile = identity.scopeKey to it }
        }
        if (identity.kind == com.myleafy.android.core.network.CampusIdentity.IdentityKind.CUSTOM_SUPABASE &&
            !profile.community_access_status.equals("approved", ignoreCase = true)
        ) {
            throw IllegalStateException(
                when (profile.community_access_status?.lowercase()) {
                    "pending" -> "学校申请正在审核中，社区功能暂未开放"
                    "rejected" -> "学校申请未通过，社区功能暂不可用"
                    else -> "当前学校身份尚未获得社区准入"
                },
            )
        }
        if (requireComplete && (!profile.is_profile_complete || profile.nickname.isBlank())) {
            throw IllegalStateException("请先在“我的”中完善社区资料")
        }
        return profile
    }

    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow {
        requireCommunityProfile()
        emit(requireService().fetchFeed(query))
    }

    override suspend fun currentProfile(): ProfileDto = requireCommunityProfile()

    override fun cacheCurrentProfile(profile: ProfileDto) {
        cachedProfile = activeAppScopeStore.current.scopeKey to profile
    }

    override fun clearProfileCache() {
        cachedProfile = null
    }

    override suspend fun post(postId: String): PostDto? {
        requireCommunityProfile()
        return requireService().fetchPost(postId)
    }

    override suspend fun commentThreads(postId: String, limit: Int): List<CommentThread> {
        requireCommunityProfile()
        val page: CommentThreadPageDto = requireService().fetchCommentThreads(postId, limit)
        return groupCommentThreads(page.comments)
    }

    override suspend fun togglePostLike(postId: String): PostDto {
        requireCommunityProfile(requireComplete = true)
        return requireService().togglePostLike(postId)
    }

    override suspend fun togglePostFavorite(postId: String): PostDto {
        requireCommunityProfile(requireComplete = true)
        return requireService().togglePostFavorite(postId)
    }

    override suspend fun notifications(limit: Int): List<NotificationDto> {
        val profile = requireCommunityProfile()
        return requireService().fetchNotifications(profile.id, limit)
    }

    override suspend fun unreadNotificationCount(limit: Int): Int =
        notifications(limit).count { !it.is_read }

    override suspend fun markNotificationRead(notificationId: String) {
        requireCommunityProfile(requireComplete = true)
        requireService().markNotificationRead(notificationId)
    }

    override suspend fun markAllNotificationsRead() {
        val profile = requireCommunityProfile(requireComplete = true)
        requireService().markAllNotificationsRead(profile.id)
    }

    override suspend fun deletePost(postId: String) {
        requireCommunityProfile(requireComplete = true)
        requireService().deletePost(postId)
    }

    override suspend fun deleteComment(commentId: String) {
        requireCommunityProfile(requireComplete = true)
        requireService().deleteComment(commentId)
    }

    override suspend fun reportPost(postId: String, reason: String, detail: String?) {
        requireCommunityProfile(requireComplete = true)
        requireService().reportPost(postId, reason, detail)
    }

    override suspend fun reportComment(commentId: String, reason: String, detail: String?) {
        requireCommunityProfile(requireComplete = true)
        requireService().reportComment(commentId, reason, detail)
    }

    override suspend fun blockUser(userId: String, reason: String?) {
        val profile = requireCommunityProfile(requireComplete = true)
        require(userId != profile.id) { "不能屏蔽自己" }
        requireService().blockUser(userId, reason)
    }

    override suspend fun createPost(
        postId: String,
        requestId: String,
        title: String,
        body: String,
        category: String?,
        isAnonymous: Boolean,
    ): PostDto {
        requireCommunityProfile(requireComplete = true)
        return requireService().createPost(postId, requestId, title, body, category, isAnonymous)
    }

    override suspend fun createComment(
        commentId: String,
        requestId: String,
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
    ): CommentDto {
        requireCommunityProfile(requireComplete = true)
        return requireService().createComment(
            commentId,
            requestId,
            postId,
            body,
            parentCommentId,
            replyToCommentId,
        )
    }
}

/** 占位实现（如无 Supabase 配置时兜底）。 */
class PlaceholderCommunityRepository : CommunityRepository {
    override val isAvailable: Boolean = true
    override val isPlaceholder: Boolean = true
    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow { emit(emptyList()) }

    override suspend fun currentProfile(): ProfileDto = throw NotImplementedError("社区功能未接入")
    override fun cacheCurrentProfile(profile: ProfileDto) = Unit
    override fun clearProfileCache() = Unit

    override suspend fun post(postId: String): PostDto? = null

    override suspend fun commentThreads(postId: String, limit: Int): List<CommentThread> = emptyList()

    override suspend fun togglePostLike(postId: String): PostDto =
        throw NotImplementedError("社区功能未接入")

    override suspend fun togglePostFavorite(postId: String): PostDto =
        throw NotImplementedError("社区功能未接入")

    override suspend fun notifications(limit: Int): List<NotificationDto> = emptyList()
    override suspend fun unreadNotificationCount(limit: Int): Int = 0
    override suspend fun markNotificationRead(notificationId: String) = Unit
    override suspend fun markAllNotificationsRead() = Unit
    override suspend fun deletePost(postId: String) = throw NotImplementedError("社区功能未接入")
    override suspend fun deleteComment(commentId: String) = throw NotImplementedError("社区功能未接入")
    override suspend fun reportPost(postId: String, reason: String, detail: String?) =
        throw NotImplementedError("社区功能未接入")
    override suspend fun reportComment(commentId: String, reason: String, detail: String?) =
        throw NotImplementedError("社区功能未接入")
    override suspend fun blockUser(userId: String, reason: String?) =
        throw NotImplementedError("社区功能未接入")

    override suspend fun createPost(
        postId: String,
        requestId: String,
        title: String,
        body: String,
        category: String?,
        isAnonymous: Boolean,
    ): PostDto =
        throw NotImplementedError("社区功能未接入")

    override suspend fun createComment(
        commentId: String,
        requestId: String,
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
    ): CommentDto = throw NotImplementedError("社区功能未接入")
}
