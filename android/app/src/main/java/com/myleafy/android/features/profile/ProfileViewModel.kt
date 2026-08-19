package com.myleafy.android.features.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.shared.model.ProfileDto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface ProfileUiState {
    data class Local(
        val campusId: String,
        val eduId: String?,
    ) : ProfileUiState

    data object ProfileLoading : ProfileUiState
    data class Community(
        val campusId: String,
        val eduId: String,
        val profile: ProfileDto,
    ) : ProfileUiState

    data class Error(val campusId: String, val eduId: String?, val message: String) : ProfileUiState
}

/**
 * “我的”ViewModel：本地身份（SettingsStore）+ 社区资料（bootstrap）。
 */
class ProfileViewModel(
    private val repository: ProfileRepository,
    private val settings: SettingsStore,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ProfileUiState>(ProfileUiState.Local("bjfu", null))
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            settings.settings.collect { s ->
                val local = ProfileUiState.Local(s.campusId, s.eduId)
                _uiState.value = if (s.eduId.isNullOrBlank()) {
                    local
                } else {
                    loadProfile(s.campusId, s.eduId)
                }
            }
        }
    }

    private suspend fun loadProfile(campusId: String, eduId: String): ProfileUiState {
        _uiState.value = ProfileUiState.ProfileLoading
        return runCatching { repository.fetchProfile() }
            .fold(
                onSuccess = { profile ->
                    if (profile != null) {
                        ProfileUiState.Community(campusId, eduId, profile)
                    } else {
                        ProfileUiState.Local(campusId, eduId)
                    }
                },
                onFailure = { ProfileUiState.Error(campusId, eduId, it.message ?: "资料加载失败") },
            )
    }
}
