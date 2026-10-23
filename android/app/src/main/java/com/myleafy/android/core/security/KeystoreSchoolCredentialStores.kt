package com.myleafy.android.core.security

import android.util.Log

/**
 * Keystore 加密的结构化凭据；可可靠读取的旧分隔符记录在读取时迁移。
 */
class KeystoreSchoolLoginCredentialStore(
    private val secureStorage: SecureStorage,
) : SchoolLoginCredentialStore {

    override fun save(credential: StoredSchoolCredential) {
        val key = keyFor(credential.campusId, credential.portal)
        secureStorage.save(key, SchoolCredentialCodec.encode(credential))
    }

    override fun loadMostRecent(campusId: String): StoredSchoolCredential? {
        return listOf(PORTAL_UNDERGRAD, PORTAL_GRADUATE).mapNotNull { read(campusId, it) }.maxByOrNull { it.savedAt }
    }

    override fun load(campusId: String, portal: String, account: String?) =
        read(campusId, portal)?.takeIf { account == null || it.account == account }

    private fun read(campusId: String, portal: String): StoredSchoolCredential? {
        val key = keyFor(campusId, portal)
        val raw = when (val result = secureStorage.read(key)) {
            SecureReadResult.Missing -> return null
            is SecureReadResult.Found -> result.value
            is SecureReadResult.Unreadable -> {
                Log.e(TAG, "Dropping unreadable school credential for $campusId/$portal", result.cause)
                runCatching { secureStorage.remove(key) }
                return null
            }
        }
        val value = SchoolCredentialCodec.decode(raw)?.takeIf { it.campusId == campusId && it.portal == portal }
        if (value == null) {
            Log.e(TAG, "Dropping malformed school credential for $campusId/$portal")
            runCatching { secureStorage.remove(key) }
            return null
        }
        if (!raw.startsWith("{")) secureStorage.save(key, SchoolCredentialCodec.encode(value))
        return value
    }

    override fun delete(campusId: String) {
        var failure: Throwable? = null
        listOf(PORTAL_UNDERGRAD, PORTAL_GRADUATE).forEach { portal ->
            try {
                secureStorage.remove(keyFor(campusId, portal))
            } catch (error: Exception) {
                failure = failure ?: error
            }
        }
        failure?.let { throw it }
    }

    private fun keyFor(campusId: String, portal: String) = "$PREFIX:$campusId:$portal"

    private companion object {
        const val TAG = "SchoolCredentials"
        const val PREFIX = "school-login"
        const val PORTAL_UNDERGRAD = "undergraduate"
        const val PORTAL_GRADUATE = "graduate"
    }
}

class KeystoreSchoolSessionCookieStore(
    private val secureStorage: SecureStorage,
) : SchoolSessionCookieStore {

    override fun save(cookies: Map<String, String>, scopeKey: String, portal: String) {
        if (cookies.isEmpty()) {
            secureStorage.remove(keyFor(scopeKey, portal))
            return
        }
        val encoded = cookies.entries.joinToString(ENTRY_SEPARATOR) { (name, value) ->
            name.escape() + KV_SEPARATOR + value.escape()
        }
        secureStorage.save(keyFor(scopeKey, portal), encoded)
    }

    override fun load(scopeKey: String, portal: String): Map<String, String> {
        val key = keyFor(scopeKey, portal)
        val raw = when (val result = secureStorage.read(key)) {
            SecureReadResult.Missing -> return emptyMap()
            is SecureReadResult.Found -> result.value
            is SecureReadResult.Unreadable -> {
                Log.e(TAG, "Dropping an unreadable school session for portal $portal", result.cause)
                runCatching { secureStorage.remove(key) }
                return emptyMap()
            }
        }
        return raw.split(ENTRY_SEPARATOR)
            .filter { it.isNotEmpty() }
            .mapNotNull { entry ->
                val index = entry.indexOf(KV_SEPARATOR)
                if (index <= 0) null else entry.take(index).unescape() to entry.drop(index + 1).unescape()
            }
            .toMap()
    }

    override fun delete(scopeKey: String, portal: String) {
        secureStorage.remove(keyFor(scopeKey, portal))
    }

    private fun keyFor(scopeKey: String, portal: String) = "$PREFIX:$scopeKey:$portal"

    private fun String.escape() = replace(KV_SEPARATOR, KV_SEPARATOR + KV_SEPARATOR)

    private fun String.unescape() = replace(KV_SEPARATOR + KV_SEPARATOR, KV_SEPARATOR)

    private companion object {
        const val TAG = "SchoolSession"
        const val PREFIX = "school-session"
        const val ENTRY_SEPARATOR = "\n"
        const val KV_SEPARATOR = "="
    }
}
