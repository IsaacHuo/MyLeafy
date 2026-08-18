package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class CommunityUiState(
    val isAvailable: Boolean = true,
)

class CommunityViewModel(
    repository: CommunityRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow(CommunityUiState(isAvailable = repository.isAvailable))
    val uiState: StateFlow<CommunityUiState> = _uiState.asStateFlow()
}
