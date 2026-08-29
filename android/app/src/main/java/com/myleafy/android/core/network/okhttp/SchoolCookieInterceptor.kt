package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.SchoolCookies
import com.myleafy.android.core.security.SchoolSessionCookieStore
import okhttp3.Interceptor
import okhttp3.Response

/**
 * 教务 Cookie 拦截器：复刻 iOS Cookie 契约。
 *
 * - 应用自持 Cookie 名值对字典为事实来源（按身份 scopeKey 持久化于 store）。
 * - 每个请求显式携带 `Cookie` 头：按名称排序、`"; "` 拼接（SchoolCookies）。
 * - 每个响应解析 `Set-Cookie`（只取 name=value）合并回字典并持久化。
 *
 * 配合 `CookieJar.NO_COOKIES`（不启用 OkHttp 默认 Cookie 管理），
 * 保证行为与 iOS 完全一致。
 */
class SchoolCookieInterceptor(
    private val cookieStore: SchoolSessionCookieStore,
    private val identityProvider: () -> CampusIdentity?,
    private val transientCookiesProvider: () -> Map<String, String>,
    private val transientCookiesSaver: (Map<String, String>) -> Unit,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val identity = identityProvider()
        val cookies = if (identity == null) {
            transientCookiesProvider()
        } else {
            cookieStore.load(identity.scopeKey, identity.portal.rawValue)
        }

        val request = chain.request().newBuilder()
            .apply {
                SchoolCookies.headerValue(cookies)?.let { header("Cookie", it) }
                header("Cache-Control", "no-cache")
                header("Pragma", "no-cache")
            }
            .build()

        val response = chain.proceed(request)

        val setCookieHeaders = response.headers.values("Set-Cookie")
        if (setCookieHeaders.isNotEmpty()) {
            val merged = SchoolCookies.mergeSetCookie(cookies, setCookieHeaders)
            if (identity == null) {
                transientCookiesSaver(merged)
            } else {
                cookieStore.save(merged, identity.scopeKey, identity.portal.rawValue)
            }
        }
        return response
    }
}
