package com.myleafy.android.features.auth

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
)

/**
 * 登录 ViewModel。阶段 1.5 校验输入并调用 AuthRepository；
 * 占位实现会如实返回失败（错误状态可见），阶段 2 接入强智登录。
 */
class LoginViewModel(
    private val repository: AuthRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        LoginUiState(hasCachedIdentity = repository.hasCachedIdentity),
    )
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

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
                },
            )
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }
}
