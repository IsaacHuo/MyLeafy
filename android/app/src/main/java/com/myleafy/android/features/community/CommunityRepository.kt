package com.myleafy.android.features.community

import com.myleafy.android.services.supabase.CommunityService
import com.myleafy.android.shared.model.CommentDto
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.CommentThreadPageDto
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.shared.model.groupCommentThreads
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * 社区仓储接口。Supabase 为权威来源（RLS + campus 作用域）。
 */
interface CommunityRepository {
    val isAvailable: Boolean

    /** 占位实现标识：true 时 UI 提示功能未接入，避免误导。 */
    val isPlaceholder: Boolean

    fun feed(query: FeedQuery): Flow<List<PostDto>>

    /** 按 id 获取帖子；不存在返回 null。 */
    suspend fun post(postId: String): PostDto?

    /** 评论线程（根 + 一层回复）。 */
    suspend fun commentThreads(postId: String, limit: Int): List<CommentThread>

    /** 点赞/取消点赞，返回更新后的帖子。 */
    suspend fun togglePostLike(postId: String): PostDto

    /** 发帖（文本，暂无图片/附件）。 */
    suspend fun createPost(title: String, body: String, category: String?, isAnonymous: Boolean): PostDto

    /** 评论（最多两层：parentCommentId 为根评论 id）。 */
    suspend fun createComment(
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
    ): CommentDto
}

/** 线上仓储：匿名 Auth + community-feed + postgrest RPC。 */
class LiveCommunityRepository(
    private val service: CommunityService?,
) : CommunityRepository {

    override val isAvailable: Boolean = true
    override val isPlaceholder: Boolean = false

    private fun requireService(): CommunityService =
        service ?: throw IllegalStateException("Supabase 未配置，请在 secrets.properties 填写 anon key")

    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow {
        emit(requireService().fetchFeed(query))
    }

    override suspend fun post(postId: String): PostDto? = requireService().fetchPost(postId)

    override suspend fun commentThreads(postId: String, limit: Int): List<CommentThread> {
        val page: CommentThreadPageDto = requireService().fetchCommentThreads(postId, limit)
        return groupCommentThreads(page.comments)
    }

    override suspend fun togglePostLike(postId: String): PostDto =
        requireService().togglePostLike(postId)

    override suspend fun createPost(title: String, body: String, category: String?, isAnonymous: Boolean): PostDto =
        requireService().createPost(title, body, category, isAnonymous)

    override suspend fun createComment(
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
    ): CommentDto = requireService().createComment(postId, body, parentCommentId, replyToCommentId)
}

/** 占位实现（如无 Supabase 配置时兜底）。 */
class PlaceholderCommunityRepository : CommunityRepository {
    override val isAvailable: Boolean = true
    override val isPlaceholder: Boolean = true
    override fun feed(query: FeedQuery): Flow<List<PostDto>> = flow { emit(emptyList()) }

    override suspend fun post(postId: String): PostDto? = null

    override suspend fun commentThreads(postId: String, limit: Int): List<CommentThread> = emptyList()

    override suspend fun togglePostLike(postId: String): PostDto =
        throw NotImplementedError("社区功能未接入")

    override suspend fun createPost(title: String, body: String, category: String?, isAnonymous: Boolean): PostDto =
        throw NotImplementedError("社区功能未接入")

    override suspend fun createComment(
        postId: String,
        body: String,
        parentCommentId: String?,
        replyToCommentId: String?,
    ): CommentDto = throw NotImplementedError("社区功能未接入")
}
