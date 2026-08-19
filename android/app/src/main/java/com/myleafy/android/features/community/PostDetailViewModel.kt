package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.shared.model.CommentThread
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface PostDetailUiState {
    data object Loading : PostDetailUiState
    data class Loaded(
        val post: PostDto,
        val threads: List<CommentThread>,
        val isLikePending: Boolean = false,
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
                onFailure = { PostDetailUiState.Error(it.message ?: "加载失败") },
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
                onFailure = { PostDetailUiState.Loaded(current.post, current.threads, isLikePending = false) },
            )
        }
    }
}
