package com.myleafy.android.features.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.shared.model.ProfileDto
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

data class ProfileUiState(
    val campusId: String = "bjfu",
    val eduId: String? = null,
    val isCommunityPlaceholder: Boolean = true,
    val profile: ProfileDto? = null,
)

/**
 * “我的”ViewModel：本地身份（SettingsStore）+ 社区资料占位。
 */
class ProfileViewModel(
    repository: ProfileRepository,
    private val settings: com.myleafy.android.core.prefs.SettingsStore,
) : ViewModel() {

    val uiState: StateFlow<ProfileUiState> = settings.settings
        .map { s ->
            ProfileUiState(
                campusId = s.campusId,
                eduId = s.eduId,
                isCommunityPlaceholder = repository.isPlaceholder,
                profile = repository.profile,
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = ProfileUiState(),
        )
}
