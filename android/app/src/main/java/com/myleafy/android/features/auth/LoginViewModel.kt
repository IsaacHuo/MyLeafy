package com.myleafy.android.features.auth

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class LoginUiState(
    val hasCachedIdentity: Boolean = false,
)

class LoginViewModel(
    repository: AuthRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow(LoginUiState(hasCachedIdentity = repository.hasCachedIdentity))
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()
}
