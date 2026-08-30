package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

enum class CommunityFeedMode { LATEST, HOT }

data class CommunityFeedSelection(
    val mode: CommunityFeedMode = CommunityFeedMode.LATEST,
    val category: String? = null,
) {
    fun toQuery(campusId: String, search: String? = null): FeedQuery = FeedQuery(
        limit = 20,
        campus_id = campusId,
        mode = if (mode == CommunityFeedMode.HOT) "hot" else null,
        days = if (mode == CommunityFeedMode.HOT) 7 else null,
        // community-feed 的 hot RPC 不接受分类或搜索，切换热门时必须清空二者。
        category = category.takeIf { mode == CommunityFeedMode.LATEST },
        search = search?.trim()?.takeIf { it.isNotEmpty() && mode == CommunityFeedMode.LATEST },
    )
}

data class CommunityUiState(
    val posts: List<PostDto> = emptyList(),
    val selection: CommunityFeedSelection = CommunityFeedSelection(),
    val isInitialLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val unreadCount: Int = 0,
)

/** 社区 Feed 状态持有者；刷新失败时保留最近一次成功列表。 */
class CommunityViewModel(
    private val repository: CommunityRepository,
    private val campusId: String,
) : ViewModel() {

    private val _uiState = MutableStateFlow(CommunityUiState())
    val uiState: StateFlow<CommunityUiState> = _uiState.asStateFlow()
    private var loadJob: Job? = null

    init {
        refresh(initial = true)
    }

    fun selectLatest(category: String?) {
        val selection = CommunityFeedSelection(mode = CommunityFeedMode.LATEST, category = category)
        if (_uiState.value.selection == selection) return
        _uiState.value = _uiState.value.copy(selection = selection, error = null)
        refresh(initial = _uiState.value.posts.isEmpty())
    }

    fun selectHot() {
        val selection = CommunityFeedSelection(mode = CommunityFeedMode.HOT)
        if (_uiState.value.selection == selection) return
        _uiState.value = _uiState.value.copy(selection = selection, error = null)
        refresh(initial = _uiState.value.posts.isEmpty())
    }

    fun refresh(initial: Boolean = false) {
        loadJob?.cancel()
        val current = _uiState.value
        _uiState.value = current.copy(
            isInitialLoading = initial && current.posts.isEmpty(),
            isRefreshing = !initial || current.posts.isNotEmpty(),
            error = null,
        )
        loadJob = viewModelScope.launch {
            runCatching {
                repository.feed(_uiState.value.selection.toQuery(campusId)).first()
            }.fold(
                onSuccess = { posts ->
                    _uiState.value = _uiState.value.copy(
                        posts = posts,
                        isInitialLoading = false,
                        isRefreshing = false,
                        error = null,
                    )
                    refreshUnreadCount()
                },
                onFailure = { error ->
                    _uiState.value = _uiState.value.copy(
                        isInitialLoading = false,
                        isRefreshing = false,
                        error = error.toCommunityMessage("社区加载失败"),
                    )
                },
            )
        }
    }

    fun refreshUnreadCount() {
        viewModelScope.launch {
            runCatching { repository.unreadNotificationCount() }
                .onSuccess { count -> _uiState.value = _uiState.value.copy(unreadCount = count) }
        }
    }
}
