package com.myleafy.android.features.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.network.SchoolCaptchaChallenge
import com.myleafy.android.core.network.SchoolNetworkError
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.io.IOException
import javax.net.ssl.SSLException

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
    private var prefilledAccount: String? = null
    private var lastCaptchaAttemptAt = 0L

    init {
        viewModelScope.launch {
            val credential = withContext(Dispatchers.IO) { repository.cachedCredential() }
            if (!credentialsEdited && credential != null) {
                accountState.value = credential.account
                passwordState.value = credential.password
                prefilledAccount = credential.account
            }
        }
        refreshCaptcha()
    }

    /**
     * 学号改掉后不再保留上一个账号的密码：否则用户会用一个账号的密码去登录另一个账号，
     * 失败原因还会被误读成验证码或网络问题。与 iOS 的预填账号比较逻辑一致。
     */
    fun setAccount(value: String) {
        val normalized = value.trim()
        val prefilled = prefilledAccount
        if (prefilled != null && normalized != prefilled) {
            passwordState.value = ""
            prefilledAccount = null
        }
        credentialsEdited = true
        accountState.value = value
    }

    fun setPassword(value: String) { credentialsEdited = true; passwordState.value = value }
    fun setCaptcha(value: String) { captchaState.value = value }

    fun refreshCaptcha() {
        if (state.value.isSubmitting) return
        lastCaptchaAttemptAt = System.currentTimeMillis()
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
                    captchaErrorMessage = captchaErrorMessage(error))
            }
        }
    }

    /**
     * 回到前台或网络恢复时调用。只在当前没有可用验证码时重试，避免覆盖用户已填写的图片；
     * 2 秒节流防止恢复事件密集触发连续请求。
     */
    fun resumeCaptcha() {
        if (state.value.isSubmitting || state.value.isCaptchaLoading) return
        if (challenge != null) return
        if (System.currentTimeMillis() - lastCaptchaAttemptAt < CAPTCHA_RETRY_INTERVAL_MS) return
        refreshCaptcha()
    }

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
                loginErrorMessage = error?.let(::loginErrorMessage))
            if (error != null) refreshCaptcha()
        }
    }

    fun clearError() {
        state.value = state.value.copy(loginErrorMessage = null, captchaErrorMessage = null)
    }

    private fun loginErrorMessage(error: Throwable): String = when (error) {
        is SchoolNetworkError.LoginFailed ->
            error.message?.takeIf { it.isNotBlank() } ?: "登录失败，请检查学号、密码与验证码"
        is SchoolNetworkError.AuthenticationExpired -> "登录状态已变化，请重新输入验证码"
        is SSLException -> "校园网证书校验失败，请切换网络后重试"
        is IOException -> "无法连接教务系统，请连接 bjfu-wifi 或北林 VPN 后重试"
        else -> error.message?.takeIf { it.isNotBlank() } ?: "登录失败，请重试"
    }

    private fun captchaErrorMessage(error: Throwable): String = when (error) {
        is SSLException -> "验证码加载失败：校园网证书校验未通过，请切换网络"
        is IOException -> "验证码加载失败：无法连接教务系统，请连接 bjfu-wifi 或北林 VPN"
        else -> "验证码获取失败：${error.message ?: "请检查校园网与代理设置"}"
    }

    private companion object {
        const val CAPTCHA_RETRY_INTERVAL_MS = 2_000L
    }
}
