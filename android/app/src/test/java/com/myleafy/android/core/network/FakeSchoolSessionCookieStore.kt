package com.myleafy.android.core.network

import com.myleafy.android.core.security.SchoolSessionCookieStore

/** 测试用内存版 Cookie 存储。 */
class FakeSchoolSessionCookieStore : SchoolSessionCookieStore {
    private val data = mutableMapOf<String, Map<String, String>>()

    override fun save(cookies: Map<String, String>, scopeKey: String, portal: String) {
        if (cookies.isEmpty()) {
            data.remove(key(scopeKey, portal))
        } else {
            data[key(scopeKey, portal)] = cookies
        }
    }

    override fun load(scopeKey: String, portal: String): Map<String, String> =
        data[key(scopeKey, portal)] ?: emptyMap()

    override fun delete(scopeKey: String, portal: String) {
        data.remove(key(scopeKey, portal))
    }

    private fun key(scopeKey: String, portal: String) = "$scopeKey:$portal"
}
