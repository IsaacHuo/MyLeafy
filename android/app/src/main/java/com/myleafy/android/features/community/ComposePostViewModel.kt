package com.myleafy.android.features.community

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

data class PickedPostImage(val id: String, val uri: Uri)

data class ComposePostUiState(
    val title: String = "",
    val body: String = "",
    val category: String = "",
    val isAnonymous: Boolean = false,
    val images: List<PickedPostImage> = emptyList(),
    val isSubmitting: Boolean = false,
    val errorMessage: String? = null,
    val published: Boolean = false,
)

/**
 * 发帖 ViewModel（文本 + 最多 4 张图片）。
 *
 * 图片在上传前按 iOS 同款目标（full ≤1600px / thumb ≤480px）压缩为 JPEG，
 * 上传、校验与挂载顺序由 `CommunityRepository` 统一执行。
 */
class ComposePostViewModel(
    private val repository: CommunityRepository,
    private val context: Context,
) : ViewModel() {

    private val postId = UUID.randomUUID().toString()
    private val requestId = UUID.randomUUID().toString()

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

    fun addImages(uris: List<Uri>) {
        if (uris.isEmpty()) return
        val current = _uiState.value.images
        val remaining = CommunityImageProcessing.postImageLimit - current.size
        if (remaining <= 0) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "单条帖子最多上传 ${CommunityImageProcessing.postImageLimit} 张图片",
            )
            return
        }
        val added = uris.take(remaining).map { PickedPostImage(UUID.randomUUID().toString(), it) }
        _uiState.value = _uiState.value.copy(
            images = current + added,
            errorMessage = if (uris.size > remaining) {
                "已保留前 ${remaining} 张，单条帖子最多 ${CommunityImageProcessing.postImageLimit} 张图片"
            } else {
                null
            },
        )
    }

    fun removeImage(id: String) {
        _uiState.value = _uiState.value.copy(
            images = _uiState.value.images.filterNot { it.id == id },
            errorMessage = null,
        )
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
                val uploads = if (state.images.isEmpty()) {
                    emptyList()
                } else {
                    withContext(Dispatchers.IO) {
                        state.images.map { picked ->
                            CommunityImageProcessing.prepare(context, picked.uri, picked.id)
                        }
                    }
                }
                repository.createPost(
                    postId = postId,
                    requestId = requestId,
                    title = state.title.trim(),
                    body = state.body.trim(),
                    category = state.category.trim().takeIf { it.isNotBlank() },
                    isAnonymous = state.isAnonymous,
                    images = uploads,
                )
            }
            _uiState.value = result.fold(
                onSuccess = { _uiState.value.copy(isSubmitting = false, published = true) },
                onFailure = {
                    _uiState.value.copy(
                        isSubmitting = false,
                        errorMessage = it.toCommunityMessage("发布失败"),
                    )
                },
            )
        }
    }
}
