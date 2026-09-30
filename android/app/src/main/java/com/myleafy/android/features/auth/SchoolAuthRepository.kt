package com.myleafy.android.features.auth

import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.core.security.SchoolLoginCredentialStore
import com.myleafy.android.core.security.StoredSchoolCredential

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

    override fun cachedCredential(): StoredSchoolCredential? = credentialStore.load(
        CampusID.bjfu.rawValue, "undergraduate", sessionState.identity?.eduId)

    override suspend fun prepareUndergraduateChallenge() =
        recovery?.manualChallenge() ?: client.prepareUndergraduateChallenge()

    override suspend fun loginUndergraduate(challenge: com.myleafy.android.core.network.SchoolCaptchaChallenge, account: String, password: String, captcha: String): Result<Unit> =
        runCatching {
            client.loginUndergraduate(challenge, account, password, captcha)
            recovery?.manualAuthenticationCompleted()
            credentialStore.save(
                StoredSchoolCredential(
                    campusId = CampusID.bjfu.rawValue,
                    portal = "undergraduate",
                    account = account,
                    password = password,
                    savedAt = System.currentTimeMillis(),
                ),
            )
            settingsStore.setCampus(CampusID.bjfu.rawValue, account)
        }

    override suspend fun logout() {
        val campusId = sessionState.identity?.campusId?.rawValue ?: CampusID.bjfu.rawValue
        client.clearSession()
        credentialStore.delete(campusId)
        settingsStore.clearIdentity()
    }
}
