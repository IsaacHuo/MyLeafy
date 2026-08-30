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
        val isLikePending: Boolean = false,
        val isFavoritePending: Boolean = false,
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
                val threads = repository.commentThreads(postId, limit = 20)
                Triple(post, threads, profile.id)
            }
            _uiState.value = result.fold(
                onSuccess = { (post, threads, profileId) ->
                    PostDetailUiState.Loaded(post, threads, profileId)
                },
                onFailure = { PostDetailUiState.Error(it.toCommunityMessage("加载失败")) },
            )
        }
    }

    fun toggleLike() {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (current.isLikePending || current.isFavoritePending || current.pendingModerationTarget != null) return
        _uiState.value = current.copy(isLikePending = true)
        viewModelScope.launch {
            val result = runCatching { repository.togglePostLike(postId) }
            _uiState.value = result.fold(
                onSuccess = { updated -> current.copy(post = updated, isLikePending = false) },
                onFailure = {
                    current.copy(
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
                    _uiState.value = current.copy(post = updated, isFavoritePending = false)
                },
                onFailure = { error ->
                    _uiState.value = current.copy(
                        isFavoritePending = false,
                        mutationError = error.toCommunityMessage("收藏失败"),
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
                    load()
                },
                onFailure = {
                    _uiState.value = current.copy(
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
        val current = _uiState.value as PostDetailUiState.Loaded
        val threads = repository.commentThreads(postId, limit = 20)
        _uiState.value = current.copy(
            threads = threads,
            pendingModerationTarget = null,
            mutationMessage = "评论已删除",
        )
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
}
