package com.myleafy.android.features.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.core.prefs.Settings
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
    private val signOut: suspend () -> Unit,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ProfileUiState>(ProfileUiState.Local("bjfu", null))
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()
    private val _isSigningOut = MutableStateFlow(false)
    val isSigningOut: StateFlow<Boolean> = _isSigningOut.asStateFlow()
    private var latestSettings = Settings()

    init {
        viewModelScope.launch {
            settings.settings.collect { s ->
                latestSettings = s
                val local = ProfileUiState.Local(s.campusId, s.eduId)
                _uiState.value = if (s.eduId.isNullOrBlank()) {
                    local
                } else {
                    loadProfile(s.campusId, s.eduId)
                }
            }
        }
    }

    fun refreshProfile() {
        val current = latestSettings
        if (current.eduId.isNullOrBlank()) return
        viewModelScope.launch { _uiState.value = loadProfile(current.campusId, current.eduId) }
    }

    fun logout() {
        if (_isSigningOut.value) return
        _isSigningOut.value = true
        viewModelScope.launch {
            runCatching { signOut() }
                .onFailure { error ->
                    _uiState.value = ProfileUiState.Error(
                        latestSettings.campusId,
                        latestSettings.eduId,
                        error.message ?: "退出登录失败",
                    )
                }
            _isSigningOut.value = false
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
