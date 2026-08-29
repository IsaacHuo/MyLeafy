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
        val isLikePending: Boolean = false,
        val isCommentPending: Boolean = false,
        val mutationError: String? = null,
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
                val post = repository.post(postId)
                    ?: throw IllegalStateException("帖子不存在或不可见")
                val threads = repository.commentThreads(postId, limit = 20)
                post to threads
            }
            _uiState.value = result.fold(
                onSuccess = { (post, threads) -> PostDetailUiState.Loaded(post, threads) },
                onFailure = { PostDetailUiState.Error(it.toCommunityMessage("加载失败")) },
            )
        }
    }

    fun toggleLike() {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (current.isLikePending) return
        _uiState.value = current.copy(isLikePending = true)
        viewModelScope.launch {
            val result = runCatching { repository.togglePostLike(postId) }
            _uiState.value = result.fold(
                onSuccess = { updated -> PostDetailUiState.Loaded(updated, current.threads) },
                onFailure = {
                    current.copy(
                        isLikePending = false,
                        mutationError = it.toCommunityMessage("点赞失败"),
                    )
                },
            )
        }
    }

    fun createComment(body: String, parentCommentId: String? = null, replyToCommentId: String? = null) {
        val current = _uiState.value as? PostDetailUiState.Loaded ?: return
        if (body.isBlank() || current.isCommentPending) return
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
}
