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
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyButtonDefaults
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.leafyMinimumTouchTarget
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ProfileEditUiState(
    val nickname: String = "",
    val bio: String = "",
    val major: String = "",
    val grade: String = "",
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val saved: Boolean = false,
    val error: String? = null,
)

class ProfileEditViewModel(private val repository: ProfileRepository) : ViewModel() {
    private val _uiState = MutableStateFlow(ProfileEditUiState())
    val uiState: StateFlow<ProfileEditUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            runCatching { repository.fetchProfile() ?: error("当前身份没有社区资料") }.fold(
                onSuccess = { profile ->
                    _uiState.value = ProfileEditUiState(
                        nickname = profile.nickname,
                        bio = profile.bio.orEmpty(),
                        major = profile.major.orEmpty(),
                        grade = profile.grade.orEmpty(),
                        isLoading = false,
                    )
                },
                onFailure = { _uiState.value = ProfileEditUiState(isLoading = false, error = it.message) },
            )
        }
    }

    fun updateNickname(value: String) { _uiState.value = _uiState.value.copy(nickname = value, error = null) }
    fun updateBio(value: String) { _uiState.value = _uiState.value.copy(bio = value, error = null) }
    fun updateMajor(value: String) { _uiState.value = _uiState.value.copy(major = value, error = null) }
    fun updateGrade(value: String) { _uiState.value = _uiState.value.copy(grade = value, error = null) }

    fun save() {
        val state = _uiState.value
        if (state.nickname.isBlank() || state.isSaving) {
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
    LeafySecondaryScaffold(title = "编辑社区资料", onBack = onBack) { contentModifier ->
        if (state.isLoading) {
            LeafyLoadingState(modifier = contentModifier.fillMaxSize())
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
                OutlinedTextField(
                    value = state.nickname,
                    onValueChange = viewModel::updateNickname,
                    label = { Text("昵称（必填）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.bio,
                    onValueChange = viewModel::updateBio,
                    label = { Text("简介") },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.major,
                    onValueChange = viewModel::updateMajor,
                    label = { Text("专业") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.grade,
                    onValueChange = viewModel::updateGrade,
                    label = { Text("年级") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    "只更新昵称、简介、专业和年级；学号、校园与社区准入状态不能在客户端修改。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = viewModel::save,
                    enabled = state.nickname.isNotBlank() && !state.isSaving,
                    modifier = Modifier.fillMaxWidth().leafyMinimumTouchTarget(),
                    shape = LeafyButtonDefaults.shape,
                ) {
                    if (state.isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(LeafyIconSize.standard), strokeWidth = 2.dp)
                    }
                    else Text("保存资料")
                }
            }
            }
        }
    }
}
