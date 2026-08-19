package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.CourseRecord
import com.myleafy.android.core.network.SchoolCookies
import com.myleafy.android.core.network.SchoolEncoding
import com.myleafy.android.core.network.SchoolLoginEncoder
import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.core.network.SchoolNetworkError
import com.myleafy.android.core.network.SchoolPageDetector
import com.myleafy.android.core.network.SchoolPortal
import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.core.security.SchoolSessionCookieStore
import com.myleafy.android.parsers.EmptyClassroom
import com.myleafy.android.parsers.HtmlParser
import com.myleafy.android.parsers.HtmlParseError
import com.myleafy.android.parsers.ParsedExamRecord
import com.myleafy.android.parsers.ParsedGradeRecord
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.delay
import okhttp3.CookieJar
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/**
 * OkHttp 教务客户端。
 *
 * - M2.1：骨架 + Cookie 契约（SchoolCookieInterceptor + NO_COOKIES jar）。
 * - M2.2：强智本科生登录（key / 验证码 / encodeKey / 会话验证）与页面识别。
 * - M2.3：强智课表抓取 + jsoup 解析。
 * - 研究生登录（RSA + AES）后续接入，fail-fast。
 */
class OkHttpSchoolNetworkClient(
    private val cookieStore: SchoolSessionCookieStore,
    private val sessionState: SchoolSessionState,
    private val baseUrl: String,
    private val graduateBaseUrl: String?,
    private val parser: HtmlParser,
) : SchoolNetworkClient {

    private val client: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(CookieJar.NO_COOKIES)
        .addInterceptor(SchoolCookieInterceptor(cookieStore) { sessionState.identity })
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
        val rawBase = if (portal == SchoolPortal.GRADUATE) {
            graduateBaseUrl ?: error("研究生门户未配置")
        } else {
            baseUrl
        }
        val base = rawBase.trimEnd('/')
        val url = "$base/${path.trimStart('/')}"
        return SchoolRequests.builder(url, referer = referer)
    }

    /** 执行请求并解析响应 Set-Cookie。 */
    internal fun execute(request: Request): Response = client.newCall(request).execute()

    override suspend fun fetchUndergraduateCaptcha(): ByteArray {
        clearSession()
        fetchLoginKey()
        val request = requestBuilder("/verifycode.servlet").get().build()
        return execute(request).use { it.body?.bytes() ?: byteArrayOf() }
    }

    override suspend fun loginUndergraduate(account: String, password: String, captcha: String) {
        clearSession()
        val key = fetchLoginKey()
        val encoded = SchoolLoginEncoder.encodeKey(key, account, password)
        if (encoded.isEmpty()) {
            throw SchoolNetworkError.LoginFailed("登录密钥无效，请重试")
        }

        val bodyText = "useDogCode=&encoded=${SchoolLoginEncoder.formUrlEncode(encoded)}" +
            "&RANDOMCODE=${SchoolLoginEncoder.formUrlEncode(captcha.trim())}"
        val body = bodyText.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val request = requestBuilder("/Logon.do?method=logon", referer = baseUrl).post(body).build()

        val response = execute(request)
        val html = SchoolEncoding.decodeUtf8OrGb18030(response.body?.bytes() ?: byteArrayOf())
        val responseUrl = response.request.url.toString()
        val loginSetCookies = response.headers.values("Set-Cookie")
        response.close()

        SchoolPageDetector.extractLoginMessage(html)?.let {
            throw SchoolNetworkError.LoginFailed(it)
        }
        if (SchoolPageDetector.isLoginPage(html)) {
            throw SchoolNetworkError.LoginFailed("登录失败，请检查学号与验证码")
        }
        val loginResponseAuthenticated = SchoolPageDetector.isAuthenticatedResponse(responseUrl, html)

        // 提交身份与登录 Cookie，供会话验证请求携带
        val identity = undergraduateIdentity(account)
        sessionState.identity = identity
        if (loginSetCookies.isNotEmpty()) {
            val merged = SchoolCookies.mergeSetCookie(loadCookies(), loginSetCookies)
            cookieStore.save(merged, identity.scopeKey, identity.portal.rawValue)
        }

        val sessionAuthenticated = verifyAuthenticatedSession().isSuccess
        val success = loginResponseAuthenticated && sessionAuthenticated || sessionAuthenticated
        if (!success) {
            sessionState.clear()
            cookieStore.delete(identity.scopeKey, identity.portal.rawValue)
            throw SchoolNetworkError.LoginFailed("登录失败，请重试")
        }

        sessionState.markLoggedIn(identity)
    }

    override suspend fun verifyAuthenticatedSession(): Result<Unit> {
        val retryCount = 1
        for (attempt in 0..retryCount) {
            try {
                val request = requestBuilder("/jsxsd/framework/xsMain.jsp").get().build()
                val response = execute(request)
                val html = SchoolEncoding.decodeUtf8OrGb18030(response.body?.bytes() ?: byteArrayOf())
                val responseUrl = response.request.url.toString()
                response.close()
                if (SchoolPageDetector.isAuthenticatedResponse(responseUrl, html)) {
                    return Result.success(Unit)
                }
            } catch (_: Exception) {
                // 重试
            }
            if (attempt < retryCount) delay(300)
        }
        return Result.failure(SchoolNetworkError.SessionExpired)
    }

    override suspend fun fetchGraduatePublicKey(): String = notYet("研究生登录（RSA）")

    override suspend fun loginGraduate(account: String, password: String, captcha: String) {
        notYet("研究生登录（AES）")
    }

    override suspend fun fetchTimetable(semesterId: String): List<CourseRecord> {
        val request = requestBuilder(
            "/jsxsd/xskb/xskb_list.do?xnxq01id=$semesterId",
            referer = "${baseUrl}/Logon.do?method=logon",
        ).get().build()
        val html = execute(request).use {
            SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf())
        }
        if (SchoolPageDetector.isLoginPage(html)) {
            throw SchoolNetworkError.SessionExpired
        }
        val records = try {
            parser.parseTimetable(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.TimetableDataUnavailable
        }
        return records.map { r ->
            CourseRecord(
                courseName = r.courseName,
                teacher = r.teacher,
                classInfo = r.classInfo,
                room = r.room,
                location = r.location,
                dayOfWeek = r.dayOfWeek,
                weeks = r.weeks,
                duration = r.duration,
            )
        }
    }

    override suspend fun fetchGrades(): List<ParsedGradeRecord> {
        val request = requestBuilder(
            "/jsxsd/kscj/cjcx_list",
            referer = "${baseUrl}/jsxsd/framework/xsMain.jsp",
        ).get().build()
        val html = execute(request).use {
            SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf())
        }
        if (SchoolPageDetector.isLoginPage(html)) {
            throw SchoolNetworkError.SessionExpired
        }
        return try {
            parser.parseGrades(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.GradeDataUnavailable
        }
    }

    override suspend fun fetchExams(semesterId: String): List<ParsedExamRecord> {
        val bodyText = "xqlbmc=&xnxqid=${SchoolLoginEncoder.formUrlEncode(semesterId)}&xqlb="
        val body = bodyText.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val request = requestBuilder(
            "/jsxsd/xsks/xsksap_list",
            referer = "${baseUrl}/jsxsd/framework/xsMain.jsp",
        ).post(body).build()
        val html = execute(request).use {
            SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf())
        }
        if (SchoolPageDetector.isLoginPage(html)) {
            throw SchoolNetworkError.SessionExpired
        }
        return try {
            parser.parseExams(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.ExamDataUnavailable
        }
    }

    override suspend fun fetchEmptyClassrooms(
        semesterId: String,
        week: Int,
        day: Int,
        startPeriod: Int,
        endPeriod: Int,
    ): List<EmptyClassroom> {
        val path = buildString {
            append("/jsxsd/kbxx/jsjy_query2")
            append("?xnxqh=").append(semesterId)
            append("&zc=").append(week).append("&zc2=").append(week)
            append("&jc=").append(startPeriod).append("&jc2=").append(endPeriod)
            append("&xqbh=&jxqbh=&jxlbh=&jsbh=&bjfh=&rnrs=&xnxqhmc=")
            append("&xq=").append(day).append("&xq2=").append(day)
            append("&jszt=5")
        }
        val request = requestBuilder(path, referer = "${baseUrl}/jsxsd/framework/xsMain.jsp").get().build()
        val html = execute(request).use {
            SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf())
        }
        if (SchoolPageDetector.isLoginPage(html)) {
            throw SchoolNetworkError.SessionExpired
        }
        return try {
            parser.parseEmptyClassrooms(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.ClassroomDataUnavailable
        }
    }

    override fun clearSession() {
        val identity = sessionState.identity
        if (identity != null) {
            cookieStore.delete(identity.scopeKey, identity.portal.rawValue)
        }
        sessionState.clear()
    }

    private fun fetchLoginKey(): String {
        val request = requestBuilder("/Logon.do?method=logon&flag=sess").get().build()
        return execute(request).use {
            val text = SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf()).trim()
            check(text.isNotBlank()) { "未获取到登录 key" }
            text
        }
    }

    private fun loadCookies(): Map<String, String> {
        val identity = sessionState.identity ?: return emptyMap()
        return cookieStore.load(identity.scopeKey, identity.portal.rawValue)
    }

    private fun undergraduateIdentity(account: String): CampusIdentity = CampusIdentity(
        // M2.2 仅支持 BJFU 本科门户；多校园/研究生在后续阶段扩展
        campusId = CampusID.bjfu,
        eduId = account,
        displayName = null,
        portal = SchoolPortal.UNDERGRADUATE,
        kind = CampusIdentity.IdentityKind.SCHOOL_PORTAL,
    )

    private fun notYet(stage: String): Nothing =
        throw NotImplementedError("$stage 尚未实现")
}
