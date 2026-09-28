package com.myleafy.android.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import com.myleafy.android.ui.components.LeafyTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException

data class ProfileEditUiState(
    val nickname: String = "",
    val bio: String = "",
    val major: String = "",
    val grade: String = "",
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val saved: Boolean = false,
    val error: String? = null,
    val dirty: Boolean = false,
    val loaded: Boolean = false,
)

class ProfileEditViewModel(private val repository: ProfileRepository) : ViewModel() {
    private val _uiState = MutableStateFlow(ProfileEditUiState())
    val uiState: StateFlow<ProfileEditUiState> = _uiState.asStateFlow()

    private var original = ProfileEditUiState()

    init { load() }

    fun load() {
        _uiState.value = ProfileEditUiState()
        viewModelScope.launch {
            runCatching { repository.fetchProfile() ?: error("当前身份没有社区资料") }.fold(
                onSuccess = { profile ->
                    _uiState.value = ProfileEditUiState(
                        nickname = profile.nickname,
                        bio = profile.bio.orEmpty(),
                        major = profile.major.orEmpty(),
                        grade = profile.grade.orEmpty(),
                        isLoading = false,
                        loaded = true,
                    )
                    original = _uiState.value
                },
                onFailure = {
                    if (it is CancellationException) throw it
                    _uiState.value = ProfileEditUiState(isLoading = false, error = it.message ?: "资料加载失败")
                },
            )
        }
    }

    fun updateNickname(value: String) = update(_uiState.value.copy(nickname = value))
    fun updateBio(value: String) = update(_uiState.value.copy(bio = value))
    fun updateMajor(value: String) = update(_uiState.value.copy(major = value))
    fun updateGrade(value: String) = update(_uiState.value.copy(grade = value))

    private fun update(value: ProfileEditUiState) {
        if (_uiState.value.isSaving || _uiState.value.saved) return
        _uiState.value = value.copy(error = null, dirty = value.nickname != original.nickname ||
            value.bio != original.bio || value.major != original.major || value.grade != original.grade)
    }

    fun save() {
        val state = _uiState.value
        if (!state.loaded || state.nickname.isBlank() || state.isSaving || state.saved) {
            if (state.nickname.isBlank()) _uiState.value = state.copy(error = "昵称不能为空")
            return
        }
        _uiState.value = state.copy(isSaving = true, error = null)
        viewModelScope.launch {
            runCatching {
                repository.updateProfile(state.nickname, state.bio, state.major, state.grade)
            }.fold(
                onSuccess = { profile ->
                    _uiState.value = state.copy(
                        nickname = profile.nickname,
                        bio = profile.bio.orEmpty(),
                        major = profile.major.orEmpty(),
                        grade = profile.grade.orEmpty(),
                        isSaving = false,
                        saved = true,
                    )
                },
                onFailure = { error ->
                    if (error is CancellationException) throw error
                    _uiState.value = state.copy(isSaving = false, error = error.message ?: "资料保存失败")
                },
            )
        }
    }
}

@Composable
fun ProfileEditScreen(
    onBack: () -> Unit,
    onSaved: () -> Unit = onBack,
    viewModel: ProfileEditViewModel = viewModel(
        factory = appViewModelFactory { ProfileEditViewModel(it.profileRepository) },
    ),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(state.saved) { if (state.saved) onSaved() }
    val requestExit = com.myleafy.android.ui.components.rememberEditorExit(state.dirty, state.isSaving, onBack)
    LeafySecondaryScaffold(title = "编辑社区资料", onBack = requestExit) { contentModifier ->
        if (state.isLoading) {
            LeafyLoadingState(modifier = contentModifier.fillMaxSize())
        } else if (!state.loaded) {
            com.myleafy.android.ui.components.LeafyErrorState(
                title = "资料加载失败",
                message = state.error ?: "资料加载失败",
                modifier = contentModifier.fillMaxSize(),
                action = { com.myleafy.android.ui.components.LeafyTextButton(onClick = viewModel::load) { Text("重试") } },
            )
        } else {
            Box(modifier = contentModifier.fillMaxSize().imePadding()) {
                Column(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .widthIn(max = LeafyComponentSize.formMaxWidth)
                        .verticalScroll(rememberScrollState())
                        .padding(LeafySpacing.page),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                ) {
                state.error?.let { LeafyStatusBanner(it, isError = true) }
                LeafyTextField(
                enabled = !state.isSaving,
                    value = state.nickname,
                    onValueChange = viewModel::updateNickname,
                    label = { Text("昵称（必填）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                LeafyTextField(
                enabled = !state.isSaving,
                    value = state.bio,
                    onValueChange = viewModel::updateBio,
                    label = { Text("简介") },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
                LeafyTextField(
                enabled = !state.isSaving,
                    value = state.major,
                    onValueChange = viewModel::updateMajor,
                    label = { Text("专业") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                LeafyTextField(
                enabled = !state.isSaving,
                    value = state.grade,
                    onValueChange = viewModel::updateGrade,
                    label = { Text("年级") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                LeafyPrimaryButton(
                    onClick = viewModel::save,
                    enabled = state.nickname.isNotBlank() && !state.isSaving,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (state.isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(LeafyIconSize.standard), strokeWidth = LeafyStroke.progress)
                    }
                    Text(if (state.isSaving) "保存中…" else "保存资料")
                }
            }
            }
        }
    }
}
