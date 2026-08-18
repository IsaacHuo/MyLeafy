package com.myleafy.android.core.security

/**
 * Keystore 实现的学校凭据存储。明文以 `|` 拼接加密，兼容任意包含该字符的
 * 值通过转义处理（值中的 `|` 编码为 `||`）。
 */
class KeystoreSchoolLoginCredentialStore(
    private val secureStorage: SecureStorage,
) : SchoolLoginCredentialStore {

    override fun save(credential: StoredSchoolCredential) {
        val key = keyFor(credential.campusId, credential.portal)
        secureStorage.save(
            key,
            listOf(
                credential.campusId,
                credential.portal,
                credential.account.escape(),
                credential.password.escape(),
                credential.savedAt.toString(),
            ).joinToString(SEPARATOR),
        )
    }

    override fun loadMostRecent(campusId: String): StoredSchoolCredential? {
        val candidates = listOf(PORTAL_UNDERGRAD, PORTAL_GRADUATE)
            .mapNotNull { portal ->
                secureStorage.read(keyFor(campusId, portal))?.let { it to portal }
            }
            .sortedByDescending { (raw, _) ->
                raw.split(SEPARATOR).lastOrNull()?.toLongOrNull() ?: 0L
            }
        val (raw, portal) = candidates.firstOrNull() ?: return null
        val parts = raw.split(SEPARATOR).map { it.unescape() }
        if (parts.size != 5) return null
        return StoredSchoolCredential(
            campusId = parts[0],
            portal = portal,
            account = parts[2],
            password = parts[3],
            savedAt = parts[4].toLongOrNull() ?: 0L,
        )
    }

    override fun delete(campusId: String) {
        listOf(PORTAL_UNDERGRAD, PORTAL_GRADUATE).forEach { portal ->
            secureStorage.remove(keyFor(campusId, portal))
        }
    }

    private fun keyFor(campusId: String, portal: String) = "$PREFIX:$campusId:$portal"

    private fun String.escape() = replace(SEPARATOR, SEPARATOR + SEPARATOR)

    private fun String.unescape() = replace(SEPARATOR + SEPARATOR, SEPARATOR)

    private companion object {
        const val PREFIX = "school-login"
        const val SEPARATOR = "|"
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
        val raw = secureStorage.read(keyFor(scopeKey, portal)) ?: return emptyMap()
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
        const val PREFIX = "school-session"
        const val ENTRY_SEPARATOR = "\n"
        const val KV_SEPARATOR = "="
    }
}
