package com.myleafy.android.core.network.okhttp

import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.AcademicStage
import com.myleafy.android.core.network.SchoolCaptchaChallenge
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.HttpUrl.Companion.toHttpUrl
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import com.myleafy.android.core.network.AcademicResult
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
import com.myleafy.android.parsers.ParsedTeachingPlanSection
import com.myleafy.android.parsers.ParsedTrainingProgram
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
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
    private val renderTimetable: (suspend (String, Map<String, String>) -> RenderedSchoolPage)? = null,
) : SchoolNetworkClient {

    /** 登录前的验证码会话。成功认证后才迁移到按身份隔离的持久化 Cookie。 */
    private val preAuthenticationCookies = ConcurrentHashMap<String, String>()

    private val client: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(CookieJar.NO_COOKIES)
        .addInterceptor(
            SchoolCookieInterceptor(
                cookieStore = cookieStore,
                identityProvider = { sessionState.identity },
                transientCookiesProvider = { preAuthenticationCookies.toMap() },
                transientCookiesSaver = { cookies ->
                    preAuthenticationCookies.clear()
                    preAuthenticationCookies.putAll(cookies)
                },
            ),
        )
        .cache(null)
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .callTimeout(18, TimeUnit.SECONDS)
        .build()

    private val authenticationClient = client.newBuilder().apply {
        interceptors().clear()
        addInterceptor(SchoolCookieInterceptor(cookieStore, { null }, { preAuthenticationCookies.toMap() }) { cookies ->
            preAuthenticationCookies.clear()
            preAuthenticationCookies.putAll(cookies)
        })
    }.build()

    private fun executeAuthentication(request: Request): Response = authenticationClient.newCall(request).execute()

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

    private val authenticationMutex = Mutex()
    private val authenticationGeneration = java.util.concurrent.atomic.AtomicLong()

    override suspend fun prepareUndergraduateChallenge(): SchoolCaptchaChallenge = withContext(Dispatchers.IO) {
        authenticationMutex.withLock {
            val generation = authenticationGeneration.get()
            val scope = sessionState.identity?.scopeKey
            preAuthenticationCookies.clear()
            try {
                val key = fetchLoginKey()
                val request = requestBuilder("/verifycode.servlet").get().build()
                val bytes = executeAuthentication(request).use {
                    if (!it.isSuccessful) throw SchoolNetworkError.Unexpected("验证码获取失败（HTTP ${it.code}）")
                    it.body?.bytes()?.takeIf { image -> image.isNotEmpty() } ?: throw SchoolNetworkError.Unexpected("验证码为空")
                }
                currentCoroutineContext().ensureActive()
                if (generation != authenticationGeneration.get() || scope != sessionState.identity?.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
                SchoolCaptchaChallenge(bytes, key, preAuthenticationCookies.toMap(), scope, generation, this@OkHttpSchoolNetworkClient)
            } finally { preAuthenticationCookies.clear() }
        }
    }

    override suspend fun loginUndergraduate(
        challenge: SchoolCaptchaChallenge,
        account: String,
        password: String,
        captcha: String,
    ) = withContext(Dispatchers.IO) {
        authenticationMutex.withLock {
        require(challenge.owner === this@OkHttpSchoolNetworkClient && challenge.consumed.compareAndSet(false, true)) { "验证码已失效，请刷新" }
        if (challenge.generation != authenticationGeneration.get() || challenge.scope != sessionState.identity?.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        preAuthenticationCookies.clear()
        preAuthenticationCookies.putAll(challenge.candidateCookies)
        try {
        val key = challenge.key
        val encoded = SchoolLoginEncoder.encodeKey(key, account, password)
        if (encoded.isEmpty()) {
            throw SchoolNetworkError.LoginFailed("登录密钥无效，请重试")
        }

        val bodyText = "useDogCode=&encoded=${SchoolLoginEncoder.formUrlEncode(encoded)}" +
            "&RANDOMCODE=${SchoolLoginEncoder.formUrlEncode(captcha.trim())}"
        val body = bodyText.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val request = requestBuilder("/Logon.do?method=logon", referer = baseUrl).post(body).build()

        val response = executeAuthentication(request)
        if (!response.isSuccessful) { val code = response.code; response.close(); throw SchoolNetworkError.Unexpected("学校连接失败（HTTP $code）") }
        val html = SchoolEncoding.decodeUtf8OrGb18030(response.body?.bytes() ?: byteArrayOf())
        response.close()

        SchoolPageDetector.extractLoginMessage(html)?.let {
            throw SchoolNetworkError.LoginFailed(it)
        }
        if (SchoolPageDetector.isLoginPage(html)) {
            throw SchoolNetworkError.LoginFailed("登录失败，请检查学号与验证码")
        }
        // Verify the candidate cookie jar before committing identity or touching the old session.
        val verification = requestBuilder("/jsxsd/framework/xsMain.jsp").get().build()
        executeAuthentication(verification).use {
            if (!it.isSuccessful) throw SchoolNetworkError.Unexpected("学校连接失败（HTTP ${it.code}）")
            val page = SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf())
            if (!SchoolPageDetector.isAuthenticatedResponse(it.request.url.toString(), page)) {
                throw SchoolNetworkError.LoginFailed("登录失败，请重试")
            }
        }
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        if (challenge.generation != authenticationGeneration.get() || challenge.scope != sessionState.identity?.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
        val identity = undergraduateIdentity(account)
        cookieStore.save(preAuthenticationCookies.toMap(), identity.scopeKey, identity.portal.rawValue)
        preAuthenticationCookies.clear()
        sessionState.markLoggedIn(identity)
        } finally {
            preAuthenticationCookies.clear()
        }
        }
    }

    override suspend fun verifyAuthenticatedSession(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            execute(requestBuilder("/jsxsd/framework/xsMain.jsp").get().build()).use { response ->
                if (!response.isSuccessful) throw SchoolNetworkError.Unexpected("学校连接失败（HTTP ${response.code}）")
                val html = SchoolEncoding.decodeUtf8OrGb18030(response.body?.bytes() ?: byteArrayOf())
                if (SchoolPageDetector.isAuthenticatedResponse(response.request.url.toString(), html)) Result.success(Unit)
                else Result.failure(SchoolNetworkError.SessionExpired)
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: Exception) { Result.failure(failure) }
    }

    override suspend fun fetchGraduatePublicKey(): String = notYet("研究生登录（RSA）")

    override suspend fun loginGraduate(account: String, password: String, captcha: String) {
        notYet("研究生登录（AES）")
    }

    override suspend fun fetchTimetable(semesterId: String): List<CourseRecord> = fetchTimetable(semesterId) {}

    override suspend fun fetchTimetable(semesterId: String, onStage: (AcademicStage) -> Unit): List<CourseRecord> = withContext(Dispatchers.IO) {
        val identity = sessionState.identity ?: throw SchoolNetworkError.SessionExpired
        val origin = baseUrl.toHttpUrl()
        val pending = java.util.ArrayDeque<Request>()
        listOf("/jsxsd/xskb/xskb_list.do?xnxq01id=$semesterId", "/jsxsd/xskb/xskb_list.do",
            "/jsxsd/framework/xsMain.jsp", "/jsxsd/framework/xSMain.jsp").forEach {
            pending.add(requestBuilder(it, referer = "$baseUrl/Logon.do?method=logon").get().build())
        }
        val seen = mutableSetOf<String>()
        var rendered = false
        var loginPageSeen = false
        var lastFailure: Exception? = null
        var lastPage: Pair<String, String>? = null
        onStage(AcademicStage.FETCHING_TIMETABLE)
        while (pending.isNotEmpty() || (!rendered && renderTimetable != null && lastPage != null)) {
            currentCoroutineContext().ensureActive()
            if (sessionState.identity?.scopeKey != identity.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
            val page = if (pending.isEmpty()) {
                rendered = true
                onStage(AcademicStage.INITIALIZING_TIMETABLE)
                val result = try { renderTimetable!!.invoke(lastPage!!.first, loadCookies()) }
                catch (failure: kotlinx.coroutines.TimeoutCancellationException) { throw SchoolNetworkError.TimetableDataUnavailable }
                if (sessionState.identity?.scopeKey != identity.scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
                cookieStore.save(result.cookies, identity.scopeKey, identity.portal.rawValue)
                result.url to result.html
            } else {
                val request = pending.removeFirst()
                val body = okio.Buffer().also { request.body?.writeTo(it) }.readUtf8()
                if (!seen.add("${request.method}:${request.url}:$body")) continue
                if (seen.size > 16) throw SchoolNetworkError.TimetableDataUnavailable
                try {
                    execute(request).use {
                        if (!it.isSuccessful) throw SchoolNetworkError.Unexpected("获取课表失败（HTTP ${it.code}）")
                        it.request.url.toString() to SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf())
                    }
                } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                catch (failure: Exception) { lastFailure = failure; continue }
            }
            val (url, html) = page
            if (SchoolPageDetector.isLoginPage(html)) { loginPageSeen = true; continue }
            val matchingSemester = if (TimetablePageResolver.isTimetable(html)) {
                try { TimetablePageResolver.verifySemester(html, semesterId); true }
                catch (failure: SchoolNetworkError) { lastFailure = failure; false }
            } else false
            if (matchingSemester) {
                onStage(AcademicStage.PROCESSING_TIMETABLE)
                val records = parser.parseTimetable(html)
                return@withContext records.map { r -> CourseRecord(r.courseName, r.teacher, r.classInfo, r.room, r.location, r.dayOfWeek, r.weeks, r.duration) }
            }
            if (html.contains("培养管理") || html.contains("学生个人中心")) lastPage = page
            TimetablePageResolver.candidates(html, url.toHttpUrl(), origin, semesterId).forEach(pending::add)
        }
        if (loginPageSeen) verifyAuthenticatedSession().getOrThrow()
        throw lastFailure ?: SchoolNetworkError.TimetableDataUnavailable
    }

    override suspend fun fetchGrades(): List<ParsedGradeRecord> = fetchAcademicResults().grades

    override suspend fun fetchAcademicResults(): AcademicResult = withContext(Dispatchers.IO) {
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
        val grades = try {
            parser.parseGrades(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.GradeDataUnavailable
        }
        AcademicResult(
            grades = grades,
            rankings = runCatching { parser.parseGradeRankings(html) }.getOrNull(),
            summary = runCatching { parser.parseGradeSummary(html) }.getOrNull(),
        )
    }

    override suspend fun fetchGradeRankings(): List<com.myleafy.android.parsers.ParsedGradeRanking> = withContext(Dispatchers.IO) {
        val origin = baseUrl.toHttpUrl()
        val candidates = ArrayDeque<Request>()
        candidates.add(requestBuilder("/jsxsd/kscj/cjcx_list").get().build())
        val seen = mutableSetOf<String>()
        var loginPageSeen = false
        while (candidates.isNotEmpty() && seen.size < 16) {
            currentCoroutineContext().ensureActive()
            val request = candidates.removeFirst()
            if (!seen.add(request.url.toString())) continue
            val html = execute(request).use { response ->
                if (!response.isSuccessful) return@use null
                SchoolEncoding.decodeUtf8OrGb18030(response.body?.bytes() ?: byteArrayOf())
            } ?: continue
            if (SchoolPageDetector.isLoginPage(html)) { loginPageSeen = true; continue }
            try { return@withContext parser.parseGradeRankings(html) } catch (_: HtmlParseError) { /* try the school's ranking entry */ }
            if (seen.size == 1) {
                val document = org.jsoup.Jsoup.parse(html)
                val links = document.select("a[href],iframe[src]").map { it.attr(if (it.hasAttr("href")) "href" else "src") }
                links.forEach { raw ->
                    val target = request.url.resolve(raw) ?: return@forEach
                    if (target.host == origin.host && target.port == origin.port && target.scheme == origin.scheme &&
                        target.encodedPath.contains("kscj") && (target.encodedPath.contains("pm") || target.encodedPath.contains("rank"))) {
                        candidates.add(SchoolRequests.builder(target.toString(), request.url.toString()).build())
                    }
                }
                listOf("cjpm_query", "cjpm_list", "cjpmcx_query", "cjpmcx_list", "cjcx_pm").forEach {
                    candidates.add(requestBuilder("/jsxsd/kscj/$it", referer = request.url.toString()).get().build())
                }
            }
        }
        if (loginPageSeen && verifyAuthenticatedSession().isFailure) throw SchoolNetworkError.SessionExpired
        throw java.io.IOException("教务暂未开放成绩排名。")
    }

    override suspend fun fetchExams(semesterId: String): List<ParsedExamRecord> = withContext(Dispatchers.IO) {
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
        return@withContext try {
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
    ): List<EmptyClassroom> = withContext(Dispatchers.IO) {
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
        return@withContext try {
            parser.parseEmptyClassrooms(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.ClassroomDataUnavailable
        }
    }

    override suspend fun fetchTeachingPlan(): List<ParsedTeachingPlanSection> = withContext(Dispatchers.IO) {
        val html = fetchJsxsdPage("/jsxsd/pyfa/pyfa_query")
        try {
            parser.parseTeachingPlan(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.TeachingPlanDataUnavailable
        }
    }

    override suspend fun fetchTrainingProgram(): ParsedTrainingProgram = withContext(Dispatchers.IO) {
        val html = fetchJsxsdPage("/jsxsd/pyfa/pyfazd_query")
        try {
            parser.parseTrainingProgram(html)
        } catch (e: HtmlParseError) {
            throw SchoolNetworkError.TrainingProgramDataUnavailable
        }
    }

    private fun fetchJsxsdPage(path: String): String {
        val request = requestBuilder(path, referer = "${baseUrl}/jsxsd/framework/xsMain.jsp").get().build()
        val html = execute(request).use {
            SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf())
        }
        if (SchoolPageDetector.isLoginPage(html)) {
            throw SchoolNetworkError.SessionExpired
        }
        return html
    }

    override fun clearSession() {
        authenticationGeneration.incrementAndGet()
        val identity = sessionState.identity
        if (identity != null) {
            cookieStore.delete(identity.scopeKey, identity.portal.rawValue)
        }
        preAuthenticationCookies.clear()
        sessionState.clear()
    }

    private fun fetchLoginKey(): String {
        val request = requestBuilder("/Logon.do?method=logon&flag=sess").get().build()
        return executeAuthentication(request).use {
            if (!it.isSuccessful) throw SchoolNetworkError.Unexpected("学校连接失败（HTTP ${it.code}）")
            val text = SchoolEncoding.decodeUtf8OrGb18030(it.body?.bytes() ?: byteArrayOf()).trim()
            check(text.isNotBlank()) { "未获取到登录 key" }
            text
        }
    }

    private fun loadCookies(): Map<String, String> {
        val identity = sessionState.identity ?: return preAuthenticationCookies.toMap()
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
