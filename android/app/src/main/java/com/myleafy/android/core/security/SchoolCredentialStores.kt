package com.myleafy.android.core.security

/**
 * 学校登录凭据存储（对应 iOS `SchoolLoginCredentialStore`，Keychain）。
 * 按校园 + 门户隔离。
 */
data class StoredSchoolCredential(
    val campusId: String,
    val portal: String,
    val account: String,
    val password: String,
    val savedAt: Long,
)

interface SchoolLoginCredentialStore {
    fun save(credential: StoredSchoolCredential)
    fun loadMostRecent(campusId: String): StoredSchoolCredential?
    fun delete(campusId: String)
}

/**
 * 教务会话 Cookie 存储（对应 iOS `SchoolSessionCredentialStore`，Keychain）。
 * 按 identity scopeKey + 门户隔离；Cookie 名值对为教务服务器契约，原样保存。
 */
interface SchoolSessionCookieStore {
    fun save(cookies: Map<String, String>, scopeKey: String, portal: String)
    fun load(scopeKey: String, portal: String): Map<String, String>
    fun delete(scopeKey: String, portal: String)
}
