package com.myleafy.android.features.community

import com.myleafy.android.services.cloudflare.CommunityService
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 社区仓储接口。Cloudflare 为权威来源（服务端授权 + campus 作用域）。
 */
interface CommunityRepository {
    fun events(scope: String): Flow<Unit>
    suspend fun hasAcceptedTerms(): Boolean
    suspend fun acceptTerms()

    val isAvailable: Boolean

    /** 占位实现标识：true 时 UI 提示功能未接入，避免误导。 */

    fun feed(query: FeedQuery): Flow<List<PostDto>>
    suspend fun feedPage(query: FeedQuery): com.myleafy.android.shared.model.FeedResponse =
        com.myleafy.android.shared.model.FeedResponse(posts = feed(query).first())

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

    /** 发帖（文本 + 可选图片，最多 4 张）。 */
    suspend fun createPost(
        postId: String,
        requestId: String,
        title: String,
        body: String,
        category: String?,
        isAnonymous: Boolean,
        images: List<CommunityPostImageUpload> = emptyList(),
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

/** 线上仓储：Cloudflare 匿名会话与 /v1 API。 */
class LiveCommunityRepository(
    private val serviceProvider: () -> CommunityService?,
    private val sessionState: SchoolSessionState,
    private val activeAppScopeStore: ActiveAppScopeStore,
) : CommunityRepository {

    private val profileMutex = Mutex()
    private var cachedProfile: Pair<String, ProfileDto>? = null

    override val isAvailable: Boolean
        get() = activeAppScopeStore.current.supports(CampusCapabilities.COMMUNITY)

    override fun events(scope: String): Flow<Unit> = flow {
        currentProfile()
        requireService().events(scope).collect { emit(it) }
    }

    override suspend fun hasAcceptedTerms(): Boolean {
        currentProfile()
        return requireService().hasAcceptedTerms()
    }
    override suspend fun acceptTerms() {
        currentProfile()
        requireService().acceptTerms()
    }

    private fun requireService(): CommunityService =
        serviceProvider() ?: throw IllegalStateException("当前身份不可使用社区，请稍后重试")

    private suspend fun requireCommunityProfile(requireComplete: Boolean = false): ProfileDto {
        val identity = sessionState.identity
            ?: throw IllegalStateException("请先登录教务，再使用社区互动功能")
        val profile = profileMutex.withLock {
            cachedProfile?.takeIf { it.first == identity.scopeKey && requireService().hasSession }?.second
                ?: requireService().bootstrapCommunityUser(
                    eduId = identity.eduId,
                    displayName = identity.displayName ?: identity.eduId,
                    campusId = identity.campusId.rawValue,
                ).profile.also {
                    if (sessionState.identity?.scopeKey != identity.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
                    cachedProfile = identity.scopeKey to it
                }
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

    override suspend fun feedPage(query: FeedQuery): com.myleafy.android.shared.model.FeedResponse {
        val scope = activeAppScopeStore.current.scopeKey
        requireCommunityProfile()
        if (scope != activeAppScopeStore.current.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        val result = requireService().fetchFeedPage(query)
        if (scope != activeAppScopeStore.current.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        return result
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

    override suspend fun unreadNotificationCount(limit: Int): Int {
        requireCommunityProfile()
        return requireService().unreadNotificationCount()
    }

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
        images: List<CommunityPostImageUpload>,
    ): PostDto {
        val profile = requireCommunityProfile(requireComplete = true)
        require(images.size <= CommunityImageProcessing.postImageLimit) {
            "单条帖子最多上传 ${CommunityImageProcessing.postImageLimit} 张图片"
        }
        val service = requireService()
        service.createPost(
            postId = postId,
            requestId = requestId,
            title = title,
            body = body,
            category = category,
            isAnonymous = isAnonymous,
            imageCount = images.size,
        )
        images.forEachIndexed { index, image ->
            service.uploadPostImage(
                profileId = profile.id,
                postId = postId,
                imageId = image.id,
                fullBytes = image.bytes,
                thumbnailBytes = image.thumbnailBytes,
                sortOrder = index,
            )
        }
        return service.fetchPost(postId) ?: throw IllegalStateException("帖子发布后未能读取结果")
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
