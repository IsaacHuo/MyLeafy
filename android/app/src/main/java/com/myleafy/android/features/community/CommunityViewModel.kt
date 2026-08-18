package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.shared.model.FeedQuery
import com.myleafy.android.shared.model.PostDto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

sealed interface CommunityUiState {
    data class Placeholder(val message: String) : CommunityUiState
    data object Loading : CommunityUiState
    data class Loaded(val posts: List<PostDto>) : CommunityUiState
    data class Error(val message: String) : CommunityUiState
}

/**
 * 社区 ViewModel。阶段 1.5 为占位（如实展示“未接入”文案）；
 * 阶段 4 用 supabase-kt 对接 community-feed。
 */
class CommunityViewModel(
    repository: CommunityRepository,
    campusId: String,
) : ViewModel() {

    private val feedQuery = FeedQuery(limit = 20, campus_id = campusId)

    val uiState: StateFlow<CommunityUiState> = if (repository.isPlaceholder) {
        MutableStateFlow(
            CommunityUiState.Placeholder("社区功能将在阶段 4 接入 Supabase"),
        ).asStateFlow()
    } else {
        repository.feed(feedQuery)
            .map { posts ->
                if (posts.isEmpty()) {
                    CommunityUiState.Placeholder("暂无内容")
                } else {
                    CommunityUiState.Loaded(posts)
                }
            }
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5_000),
                initialValue = CommunityUiState.Loading,
            )
    }
}
