package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.CourseRecord
import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.core.network.SchoolPortal
import com.myleafy.android.core.security.SchoolSessionCookieStore
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import okhttp3.CookieJar
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

/**
 * OkHttp 教务客户端（M2.1：骨架 + Cookie 契约）。
 *
 * - Cookie 管理完全复刻 iOS（SchoolCookieInterceptor + NO_COOKIES jar）。
 * - 请求头/缓存策略与 iOS 一致（UA、no-cache、超时）。
 * - 登录（M2.2）、课表/成绩抓取（M2.3）等业务方法尚未实现，失败时明确抛出，
 *   不做假数据。
 */
class OkHttpSchoolNetworkClient(
    private val cookieStore: SchoolSessionCookieStore,
    private val identityProvider: () -> CampusIdentity?,
    private val baseUrl: String,
    private val graduateBaseUrl: String?,
) : SchoolNetworkClient {

    private val client: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(CookieJar.NO_COOKIES)
        .addInterceptor(SchoolCookieInterceptor(cookieStore, identityProvider))
        .cache(null)
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .callTimeout(18, TimeUnit.SECONDS)
        .build()

    override val cookies: Map<String, String>
        get() = loadCookies()

    /** 构造教务请求（默认本科门户）。Referer 按 iOS 协议指定。 */
    fun requestBuilder(
        path: String,
        portal: SchoolPortal = SchoolPortal.UNDERGRADUATE,
        referer: String? = null,
    ): Request.Builder {
        val base = if (portal == SchoolPortal.GRADUATE) {
            graduateBaseUrl ?: error("研究生门户未配置")
        } else {
            baseUrl
        }
        return SchoolRequests.builder(base + path, referer = referer)
    }

    /** 执行请求并解析响应 Set-Cookie（供后续登录/抓取复用）。 */
    internal fun execute(request: Request): Response = client.newCall(request).execute()

    override suspend fun fetchUndergraduateCaptcha(): ByteArray = notYet("M2.2 强智登录")

    override suspend fun fetchGraduatePublicKey(): String = notYet("M2.2 研究生登录")

    override suspend fun loginUndergraduate(account: String, password: String, captcha: String) {
        notYet("M2.2 强智登录")
    }

    override suspend fun loginGraduate(account: String, password: String, captcha: String) {
        notYet("M2.2 研究生登录")
    }

    override suspend fun verifyAuthenticatedSession(): Result<Unit> = notYet("M2.2 会话验证")

    override suspend fun fetchTimetable(semesterId: String): Flow<List<CourseRecord>> =
        flow { throw NotImplementedError("课表抓取将在 M2.3 接入（jsoup 解析）") }

    override fun clearSession() {
        val identity = identityProvider() ?: return
        cookieStore.delete(identity.scopeKey, identity.portal.rawValue)
    }

    private fun loadCookies(): Map<String, String> {
        val identity = identityProvider() ?: return emptyMap()
        return cookieStore.load(identity.scopeKey, identity.portal.rawValue)
    }

    private fun notYet(stage: String): Nothing =
        throw NotImplementedError("$stage 尚未实现（M2.1 仅完成客户端骨架与 Cookie 契约）")
}
