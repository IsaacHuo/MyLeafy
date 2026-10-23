package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

sealed interface PostDetailUiState {
    data object Loading : PostDetailUiState
    data class Loaded(
        val post: PostDto,
        val threads: List<CommentThread>,
        val currentProfileId: String,
        val hasMoreComments: Boolean = false,
        val nextCommentCreatedAt: String? = null,
        val nextCommentId: String? = null,
        val isLoadingMoreComments: Boolean = false,
        val commentLoadError: String? = null,
        val isLikePending: Boolean = false,
        val isFavoritePending: Boolean = false,
        val commentLikePending: Set<String> = emptySet(),
        val isCommentPending: Boolean = false,
        val pendingModerationTarget: String? = null,
        val mutationError: String? = null,
        val mutationMessage: String? = null,
        val shouldClose: Boolean = false,
    ) : PostDetailUiState

    data class Error(val message: String) : PostDetailUiState
}

/**
 * 帖子详情 ViewModel：帖子 + 评论线程 + 点赞。
 */
class PostDetailViewModel(
    private val repository: CommunityRepository,
    private val postId: String,
) : ViewModel() {

    private data class PendingComment(
        val body: String,
        val parentCommentId: String?,
        val replyToCommentId: String?,
        val commentId: String,
        val requestId: String,
    )

    private var pendingComment: PendingComment? = null
    private val commentLikeRequestIds = mutableMapOf<String, String>()

    private val _uiState = MutableStateFlow<PostDetailUiState>(PostDetailUiState.Loading)
    val uiState: StateFlow<PostDetailUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        _uiState.value = PostDetailUiState.Loading
        viewModelScope.launch {
            val result = runCatching {
                val profile = repository.currentProfile()
                val post = repository.post(postId)
                    ?: throw IllegalStateException("帖子不存在或不可见")
                val comments = repository.commentThreads(postId, limit = COMMENT_PAGE_SIZE)
                Triple(post, comments, profile.id)
            }
            _uiState.value = result.fold(
                onSuccess = { (post, comments, profileId) ->
                    PostDetailUiState.Loaded(
                        post = post,
                        threads = comments.threads,
                        currentProfileId = profileId,
                        hasMoreComments = comments.hasMore,
                        nextCommentCreatedAt = comments.nextCreatedAt,
                        nextCommentId = comments.nextId,
                    )
                },
                onFailure = { PostDetailUiState.Error(it.toCommunityMessage("加载失败")) },
            )
        }
    }

    fun loadMoreComments() {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (!current.hasMoreComments || current.isLoadingMoreComments) return
        _uiState.value = current.copy(isLoadingMoreComments = true, commentLoadError = null)
        viewModelScope.launch {
            runCatching {
                repository.commentThreads(
                    postId = postId,
                    limit = COMMENT_PAGE_SIZE,
                    afterCreatedAt = current.nextCommentCreatedAt,
                    afterId = current.nextCommentId,
                )
            }.fold(
                onSuccess = { page ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    val existing = live.threads.mapTo(mutableSetOf()) { it.root.id }
                    val appended = page.threads.filter { existing.add(it.root.id) }
                    _uiState.value = live.copy(
                        threads = live.threads + appended,
                        hasMoreComments = page.hasMore,
                        nextCommentCreatedAt = page.nextCreatedAt,
                        nextCommentId = page.nextId,
                        isLoadingMoreComments = false,
                    )
                },
                onFailure = { error ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(
                        isLoadingMoreComments = false,
                        commentLoadError = error.toCommunityMessage("加载更多评论失败"),
                    )
                },
            )
        }
    }

    fun toggleLike() {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (current.isLikePending || current.isFavoritePending || current.pendingModerationTarget != null) return
        _uiState.value = current.copy(isLikePending = true)
        viewModelScope.launch {
            val result = runCatching { repository.togglePostLike(postId) }
            val live = _uiState.value as? PostDetailUiState.Loaded ?: return@launch
            _uiState.value = result.fold(
                onSuccess = { updated -> live.copy(post = updated, isLikePending = false) },
                onFailure = {
                    live.copy(
                        isLikePending = false,
                        mutationError = it.toCommunityMessage("点赞失败"),
                    )
                },
            )
        }
    }

    fun toggleFavorite() {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (current.isFavoritePending || current.isLikePending || current.pendingModerationTarget != null) return
        _uiState.value = current.copy(isFavoritePending = true, mutationError = null)
        viewModelScope.launch {
            runCatching { repository.togglePostFavorite(postId) }.fold(
                onSuccess = { updated ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(post = updated, isFavoritePending = false)
                },
                onFailure = { error ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(
                        isFavoritePending = false,
                        mutationError = error.toCommunityMessage("收藏失败"),
                    )
                },
            )
        }
    }

    fun toggleCommentLike(commentId: String) {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (commentId in current.commentLikePending) return
        val requestId = commentLikeRequestIds.getOrPut(commentId) { UUID.randomUUID().toString() }
        _uiState.value = current.copy(commentLikePending = current.commentLikePending + commentId)
        viewModelScope.launch {
            runCatching { repository.toggleCommentLike(commentId, requestId) }.fold(
                onSuccess = { result ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(
                        threads = live.threads.map { thread ->
                            thread.copy(
                                root = thread.root.withCommentLike(result),
                                replies = thread.replies.map { it.withCommentLike(result) },
                            )
                        },
                        commentLikePending = live.commentLikePending - commentId,
                    )
                    commentLikeRequestIds.remove(commentId)
                },
                onFailure = { error ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(
                        commentLikePending = live.commentLikePending - commentId,
                        mutationError = error.toCommunityMessage("评论点赞失败"),
                    )
                },
            )
        }
    }

    fun createComment(body: String, parentCommentId: String? = null, replyToCommentId: String? = null) {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (body.isBlank() || current.isCommentPending || current.pendingModerationTarget != null) return
        val trimmedBody = body.trim()
        val request = pendingComment
            ?.takeIf {
                it.body == trimmedBody &&
                    it.parentCommentId == parentCommentId &&
                    it.replyToCommentId == replyToCommentId
            }
            ?: PendingComment(
                body = trimmedBody,
                parentCommentId = parentCommentId,
                replyToCommentId = replyToCommentId,
                commentId = UUID.randomUUID().toString(),
                requestId = UUID.randomUUID().toString(),
            ).also { pendingComment = it }
        _uiState.value = current.copy(isCommentPending = true, mutationError = null)
        viewModelScope.launch {
            val result = runCatching {
                repository.createComment(
                    commentId = request.commentId,
                    requestId = request.requestId,
                    postId = postId,
                    body = request.body,
                    parentCommentId = request.parentCommentId,
                    replyToCommentId = request.replyToCommentId,
                )
            }
            result.fold(
                onSuccess = {
                    pendingComment = null
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(isCommentPending = false)
                    // 只刷新评论，不把整页重置成 Loading：保留帖子、滚动位置和已展开的图片。
                    refreshComments()
                },
                onFailure = {
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(
                        isCommentPending = false,
                        mutationError = it.toCommunityMessage("评论发送失败"),
                    )
                },
            )
        }
    }

    fun deletePost() = moderate("post:$postId", "删除帖子失败") {
        repository.deletePost(postId)
        _uiState.value = (_uiState.value as PostDetailUiState.Loaded).copy(shouldClose = true)
    }

    fun deleteComment(commentId: String) = moderate("comment:$commentId", "删除评论失败") {
        repository.deleteComment(commentId)
        val page = repository.commentThreads(postId, limit = COMMENT_PAGE_SIZE)
        val current = _uiState.value as PostDetailUiState.Loaded
        _uiState.value = current.copy(
            threads = page.threads,
            hasMoreComments = page.hasMore,
            nextCommentCreatedAt = page.nextCreatedAt,
            nextCommentId = page.nextId,
            pendingModerationTarget = null,
            mutationMessage = "评论已删除",
        )
    }

    /** 评论变更后只刷新第一页评论；失败时保留当前列表并显示错误。 */
    private fun refreshComments() {
        viewModelScope.launch {
            runCatching { repository.commentThreads(postId, limit = COMMENT_PAGE_SIZE) }.fold(
                onSuccess = { page ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(
                        threads = page.threads,
                        hasMoreComments = page.hasMore,
                        nextCommentCreatedAt = page.nextCreatedAt,
                        nextCommentId = page.nextId,
                        commentLoadError = null,
                    )
                },
                onFailure = { error ->
                    val live = _uiState.value as? PostDetailUiState.Loaded ?: return@fold
                    _uiState.value = live.copy(commentLoadError = error.toCommunityMessage("评论刷新失败"))
                },
            )
        }
    }

    fun reportPost(reason: String) = moderate("post:$postId", "举报失败") {
        repository.reportPost(postId, reason)
        moderationSucceeded("举报已提交")
    }

    fun reportComment(commentId: String, reason: String) = moderate("comment:$commentId", "举报失败") {
        repository.reportComment(commentId, reason)
        moderationSucceeded("举报已提交")
    }

    fun blockUser(userId: String) = moderate("user:$userId", "屏蔽失败") {
        repository.blockUser(userId, "用户主动屏蔽")
        _uiState.value = (_uiState.value as PostDetailUiState.Loaded).copy(shouldClose = true)
    }

    fun clearMessage() {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        _uiState.value = current.copy(mutationError = null, mutationMessage = null)
    }

    private fun moderate(target: String, fallback: String, action: suspend () -> Unit) {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (current.pendingModerationTarget != null) return
        _uiState.value = current.copy(
            pendingModerationTarget = target,
            mutationError = null,
            mutationMessage = null,
        )
        viewModelScope.launch {
            runCatching { action() }.onFailure { error ->
                val latest = _uiState.value as? PostDetailUiState.Loaded ?: current
                _uiState.value = latest.copy(
                    pendingModerationTarget = null,
                    mutationError = error.toCommunityMessage(fallback),
                )
            }
        }
    }

    private fun moderationSucceeded(message: String) {
        val current = _uiState.value as PostDetailUiState.Loaded
        _uiState.value = current.copy(
            pendingModerationTarget = null,
            mutationMessage = message,
        )
    }

    private companion object {
        const val COMMENT_PAGE_SIZE = 20
    }
}

private fun com.myleafy.android.shared.model.CommentThreadDto.withCommentLike(
    result: com.myleafy.android.shared.model.CommentLikeResultDto,
): com.myleafy.android.shared.model.CommentThreadDto =
    if (id == result.comment_id) {
        copy(like_count = result.like_count, viewer_has_liked = result.viewer_has_liked)
    } else {
        this
    }
