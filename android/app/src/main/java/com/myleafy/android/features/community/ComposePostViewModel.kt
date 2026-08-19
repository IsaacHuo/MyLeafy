package com.myleafy.android.features.community

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ComposePostUiState(
    val title: String = "",
    val body: String = "",
    val category: String = "",
    val isAnonymous: Boolean = false,
    val isSubmitting: Boolean = false,
    val errorMessage: String? = null,
    val published: Boolean = false,
)

/**
 * 发帖 ViewModel（文本帖，暂无图片/附件）。
 */
class ComposePostViewModel(
    private val repository: CommunityRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ComposePostUiState())
    val uiState: StateFlow<ComposePostUiState> = _uiState.asStateFlow()

    fun updateTitle(title: String) {
        _uiState.value = _uiState.value.copy(title = title, errorMessage = null)
    }

    fun updateBody(body: String) {
        _uiState.value = _uiState.value.copy(body = body, errorMessage = null)
    }

    fun updateCategory(category: String) {
        _uiState.value = _uiState.value.copy(category = category, errorMessage = null)
    }

    fun toggleAnonymous() {
        _uiState.value = _uiState.value.copy(isAnonymous = !_uiState.value.isAnonymous)
    }

    fun submit() {
        val state = _uiState.value
        if (state.isSubmitting) return
        if (state.title.isBlank() || state.body.isBlank()) {
            _uiState.value = state.copy(errorMessage = "请填写标题与正文")
            return
        }
        _uiState.value = state.copy(isSubmitting = true, errorMessage = null)
        viewModelScope.launch {
            val result = runCatching {
                repository.createPost(
                    title = state.title.trim(),
                    body = state.body.trim(),
                    category = state.category.trim().takeIf { it.isNotBlank() },
                    isAnonymous = state.isAnonymous,
                )
            }
            _uiState.value = result.fold(
                onSuccess = { _uiState.value.copy(isSubmitting = false, published = true) },
                onFailure = {
                    _uiState.value.copy(
                        isSubmitting = false,
                        errorMessage = it.message ?: "发布失败",
                    )
                },
            )
        }
    }
}
