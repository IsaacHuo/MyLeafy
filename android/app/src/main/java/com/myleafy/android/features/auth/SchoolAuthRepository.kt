package com.myleafy.android.features.auth

import android.util.Log
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.core.security.SchoolLoginCredentialStore
import com.myleafy.android.core.security.StoredSchoolCredential
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 学校登录仓储（强智本科）。
 * 登录成功后：保存凭据（Keystore）、记录本地身份（SettingsStore），
 * 会话状态由 SchoolNetworkClient 维护（Cookie 持久化 + markLoggedIn）。
 */
class SchoolAuthRepository(
    private val client: SchoolNetworkClient,
    private val sessionState: SchoolSessionState,
    private val credentialStore: SchoolLoginCredentialStore,
    private val settingsStore: SettingsStore,
    private val recovery: SchoolAuthenticationRecovery? = null,
) : AuthRepository {

    override val hasCachedIdentity: Boolean
        get() = sessionState.identity != null

    override fun cachedCredential(): StoredSchoolCredential? = credentialStore.load(CampusID.bjfu.rawValue, "undergraduate", sessionState.identity?.eduId)

    override suspend fun prepareUndergraduateChallenge() =
        recovery?.manualChallenge() ?: client.prepareUndergraduateChallenge()

    /**
     * 登录成功以会话建立为准。自动填充凭据、记录本机身份都是尽力而为：
     * 它们失败不能让用户看到“登录失败”，否则会重复提交一个已经成功的登录。
     */
    override suspend fun loginUndergraduate(
        challenge: com.myleafy.android.core.network.SchoolCaptchaChallenge,
        account: String,
        password: String,
        captcha: String,
    ): Result<Unit> = try {
        client.loginUndergraduate(challenge, account, password, captcha)
        recovery?.manualAuthenticationCompleted()

        withContext(Dispatchers.IO) {
            runCatching {
                credentialStore.save(
                    StoredSchoolCredential(
                        campusId = CampusID.bjfu.rawValue,
                        portal = "undergraduate",
                        account = account,
                        password = password,
                        savedAt = System.currentTimeMillis(),
                    ),
                )
            }.onFailure { Log.w(TAG, "Login succeeded but credential autofill was not saved", it) }
        }

        runCatching { settingsStore.setCampus(CampusID.bjfu.rawValue, account) }
            .onFailure { Log.w(TAG, "Login succeeded but local identity was not persisted", it) }

        Result.success(Unit)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        Result.failure(failure)
    }

    override suspend fun logout() = withContext(Dispatchers.IO) {
        val campusId = sessionState.identity?.campusId?.rawValue ?: CampusID.bjfu.rawValue
        client.clearSession()
        credentialStore.delete(campusId)
        settingsStore.clearIdentity()
    }

    private companion object {
        const val TAG = "SchoolAuth"
    }
}
