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
    val loginErrorMessage: String? = null,
    val captchaErrorMessage: String? = null,
    val loginSucceeded: Boolean = false,
    val captchaBytes: ByteArray? = null,
    val isCaptchaLoading: Boolean = false,
) {
    val errorMessage: String?
        get() = listOfNotNull(loginErrorMessage, captchaErrorMessage)
            .distinct()
            .takeIf { it.isNotEmpty() }
            ?.joinToString("\n")
}

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

    private var captchaJob: kotlinx.coroutines.Job? = null

    init {
        refreshCaptcha()
    }

    fun refreshCaptcha() {
        if (_uiState.value.isCaptchaLoading || _uiState.value.isSubmitting) return
        _uiState.value = _uiState.value.copy(
            isCaptchaLoading = true,
            captchaBytes = null,
            captchaErrorMessage = null,
        )
        captchaJob = viewModelScope.launch {
            val result = runCatching { repository.fetchUndergraduateCaptcha() }
            val failure = result.exceptionOrNull()
            if (failure is kotlinx.coroutines.CancellationException) throw failure
            if (failure != null) {
                Log.e(TAG, "Failed to fetch undergraduate captcha", failure)
            }
            _uiState.value = _uiState.value.copy(
                isCaptchaLoading = false,
                captchaBytes = result.getOrNull(),
                captchaErrorMessage = failure?.let {
                    "验证码获取失败：${it.message ?: "请检查校园网与代理设置"}"
                },
            )
        }
    }

    fun resumeCaptcha() {
        if (_uiState.value.captchaBytes == null && _uiState.value.captchaErrorMessage == null) refreshCaptcha()
    }

    fun pauseCaptcha() {
        captchaJob?.cancel()
        captchaJob = null
        _uiState.value = _uiState.value.copy(isCaptchaLoading = false)
    }

    fun submit(account: String, password: String, captcha: String) {
        if (_uiState.value.isSubmitting || _uiState.value.isCaptchaLoading) return
        if (account.isBlank() || password.isBlank() || captcha.isBlank()) {
            _uiState.value = _uiState.value.copy(
                loginErrorMessage = "请填写完整的学号、密码与验证码",
            )
            return
        }
        _uiState.value = _uiState.value.copy(
            isSubmitting = true,
            loginErrorMessage = null,
            captchaErrorMessage = null,
        )
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
                    if (it is kotlinx.coroutines.CancellationException) throw it
                    _uiState.value = _uiState.value.copy(
                        isSubmitting = false,
                        loginErrorMessage = it.message ?: "登录失败",
                    )
                    refreshCaptcha()
                },
            )
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(
            loginErrorMessage = null,
            captchaErrorMessage = null,
        )
    }

    private companion object {
        const val TAG = "LoginViewModel"
    }
}
