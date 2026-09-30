package com.myleafy.android.features.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.network.SchoolCaptchaChallenge
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

data class LoginUiState(
    val hasCachedIdentity: Boolean = false,
    val isSubmitting: Boolean = false,
    val loginErrorMessage: String? = null,
    val captchaErrorMessage: String? = null,
    val loginSucceeded: Boolean = false,
    val captchaBytes: ByteArray? = null,
    val isCaptchaLoading: Boolean = false,
) {
    val errorMessage: String? get() = listOfNotNull(loginErrorMessage, captchaErrorMessage)
        .distinct().takeIf { it.isNotEmpty() }?.joinToString("\n")
}

/** Passwords live only in this ViewModel and encrypted storage, never saved instance state. */
class LoginViewModel(
    private val repository: AuthRepository,
) : ViewModel() {
    private val state = MutableStateFlow(LoginUiState(hasCachedIdentity = repository.hasCachedIdentity))
    val uiState = state.asStateFlow()
    private val accountState = MutableStateFlow("")
    private val passwordState = MutableStateFlow("")
    private val captchaState = MutableStateFlow("")
    val account = accountState.asStateFlow()
    val password = passwordState.asStateFlow()
    val captcha = captchaState.asStateFlow()
    private var challenge: SchoolCaptchaChallenge? = null
    private var captchaJob: Job? = null
    private var credentialsEdited = false

    init {
        viewModelScope.launch {
            val credential = withContext(Dispatchers.IO) { repository.cachedCredential() }
            if (!credentialsEdited && credential != null) {
                accountState.value = credential.account
                passwordState.value = credential.password
            }
        }
        refreshCaptcha()
    }

    fun setAccount(value: String) { credentialsEdited = true; accountState.value = value }
    fun setPassword(value: String) { credentialsEdited = true; passwordState.value = value }
    fun setCaptcha(value: String) { captchaState.value = value }

    fun refreshCaptcha() {
        if (state.value.isSubmitting) return
        captchaJob?.cancel()
        challenge = null
        captchaState.value = ""
        state.value = state.value.copy(isCaptchaLoading = true,
            captchaBytes = null, captchaErrorMessage = null)
        captchaJob = viewModelScope.launch {
            try {
                val next = repository.prepareUndergraduateChallenge()
                ensureActive()
                challenge = next
                state.value = state.value.copy(isCaptchaLoading = false, captchaBytes = next.imageBytes)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                state.value = state.value.copy(isCaptchaLoading = false,
                    captchaErrorMessage = "验证码获取失败：${error.message ?: "请检查校园网与代理设置"}")
            }
        }
    }

    fun resumeCaptcha() { if (challenge == null && !state.value.isCaptchaLoading && state.value.captchaErrorMessage == null) refreshCaptcha() }
    fun pauseCaptcha() {
        captchaJob?.cancel()
        state.value = state.value.copy(isCaptchaLoading = false)
    }

    fun submit(account: String = accountState.value, password: String = passwordState.value, captcha: String = captchaState.value) {
        if (state.value.isSubmitting || state.value.isCaptchaLoading) return
        val current = challenge
        if (account.isBlank() || password.isBlank() || captcha.isBlank() || current == null) {
            state.value = state.value.copy(loginErrorMessage = "请填写完整的学号、密码与验证码")
            return
        }
        captchaJob?.cancel()
        state.value = state.value.copy(isSubmitting = true, loginErrorMessage = null, captchaErrorMessage = null)
        viewModelScope.launch {
            val result = repository.loginUndergraduate(current, account.trim(), password, captcha.trim())
            val error = result.exceptionOrNull()
            if (error is CancellationException) throw error
            state.value = state.value.copy(isSubmitting = false, loginSucceeded = error == null,
                loginErrorMessage = error?.message ?: if (error != null) "登录失败" else null)
            if (error != null) refreshCaptcha()
        }
    }

    fun clearError() { state.value = state.value.copy(loginErrorMessage = null, captchaErrorMessage = null) }
}
