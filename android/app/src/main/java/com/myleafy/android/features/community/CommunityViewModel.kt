package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

sealed interface CommunityUiState {
    data object Loading : CommunityUiState
    data class Loaded(val posts: List<PostDto>) : CommunityUiState
    data class Error(val message: String) : CommunityUiState
}

/**
 * 社区 ViewModel。用 supabase-kt 对接 community-feed；
 * 无配置/未登录/网络错误如实进入 Error 状态（可重试）。
 */
class CommunityViewModel(
    private val repository: CommunityRepository,
    campusId: String,
) : ViewModel() {

    private val feedQuery = FeedQuery(limit = 20, campus_id = campusId)
    private val refreshKey = MutableStateFlow(0)

    private val mapped: Flow<CommunityUiState> = refreshKey
        .flatMapLatest { repository.feed(feedQuery) }
        .map { posts ->
            CommunityUiState.Loaded(posts)
        }

    val uiState: StateFlow<CommunityUiState> = mapped
        .catch { emit(CommunityUiState.Error(it.message ?: "社区加载失败")) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = CommunityUiState.Loading,
        )

    fun refresh() {
        refreshKey.value++
    }
}
