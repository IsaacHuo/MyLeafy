package com.myleafy.android.features.auth

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class LoginUiState(
    val hasCachedIdentity: Boolean = false,
    val isSubmitting: Boolean = false,
    val errorMessage: String? = null,
    val loginSucceeded: Boolean = false,
    val captchaBytes: ByteArray? = null,
    val isCaptchaLoading: Boolean = false,
)

/**
 * 登录 ViewModel（M2.2 接入强智登录）。
 * 验证码自动获取，登录失败后自动刷新验证码。
 */
class LoginViewModel(
    private val repository: AuthRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        LoginUiState(hasCachedIdentity = repository.hasCachedIdentity),
    )
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    init {
        refreshCaptcha()
    }

    fun refreshCaptcha() {
        _uiState.value = _uiState.value.copy(
            isCaptchaLoading = true,
            captchaBytes = null,
            errorMessage = null,
        )
        viewModelScope.launch {
            val result = runCatching { repository.fetchUndergraduateCaptcha() }
            val failure = result.exceptionOrNull()
            if (failure != null) {
                Log.e(TAG, "Failed to fetch undergraduate captcha", failure)
            }
            _uiState.value = _uiState.value.copy(
                isCaptchaLoading = false,
                captchaBytes = result.getOrNull(),
                errorMessage = failure?.let {
                    "验证码获取失败：${it.message ?: "请检查校园网与代理设置"}"
                },
            )
        }
    }

    fun submit(account: String, password: String, captcha: String) {
        if (account.isBlank() || password.isBlank() || captcha.isBlank()) {
            _uiState.value = _uiState.value.copy(errorMessage = "请填写完整的学号、密码与验证码")
            return
        }
        _uiState.value = _uiState.value.copy(isSubmitting = true, errorMessage = null)
        viewModelScope.launch {
            val result = repository.loginUndergraduate(
                account = account.trim(),
                password = password,
                captcha = captcha.trim(),
            )
            result.fold(
                onSuccess = {
                    _uiState.value = _uiState.value.copy(isSubmitting = false, loginSucceeded = true)
                },
                onFailure = {
                    _uiState.value = _uiState.value.copy(
                        isSubmitting = false,
                        errorMessage = it.message ?: "登录失败",
                    )
                    refreshCaptcha()
                },
            )
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    private companion object {
        const val TAG = "LoginViewModel"
    }
}
